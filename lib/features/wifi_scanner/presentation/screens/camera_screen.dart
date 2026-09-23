import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/utils/platform_channel.dart';
import '../../data/models/wifi_credential.dart';
import '../../data/services/camera_frame.dart';
import '../../data/services/image_cropper.dart';
import '../../data/services/ocr_service.dart';
import '../../domain/services/credential_voter.dart';
import '../../domain/services/wifi_credential_extractor.dart';
import '../widgets/camera_message_view.dart';
import '../widgets/cover_camera_preview.dart';
import '../widgets/live_result_banner.dart';
import '../widgets/scan_guide_overlay.dart';
import '../widgets/shutter_button.dart';
import 'wifi_result_screen.dart';

enum _CameraStatus { initializing, ready, permissionDenied, unavailable }

/// 앱 첫 화면. 카메라로 Wi-Fi 안내문을 촬영해 OCR → 파싱 후 결과 화면으로 보낸다.
///
/// 프리뷰가 켜져 있는 동안 프레임을 계속 인식해 여러 프레임의 다수결로 값을 정한다
/// ([CredentialVoter]). 결과가 안정되면 셔터 없이 넘어갈 수 있는 카드를 띄우고,
/// 셔터를 누르면 고해상도 사진의 결과를 다수결에 합친다.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  static const _permissionErrors = {
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
  };

  /// 실시간 인식 프레임 간격. 두 인식기를 함께 돌리므로 너무 촘촘하면 발열만 늘어난다.
  static const _liveInterval = Duration(milliseconds: 350);

  final _ocr = OcrService();
  final _extractor = const WifiCredentialExtractor();
  final _voter = CredentialVoter();
  final _picker = ImagePicker();

  CameraController? _controller;
  _CameraStatus _status = _CameraStatus.initializing;
  bool _initializing = false;
  bool _processing = false;
  bool _torchOn = false;
  bool _resultOpen = false;

  /// 프리뷰가 그려지는 영역 크기. 가이드 영역을 사진 좌표로 옮길 때 쓴다.
  Size? _viewSize;

  /// 탭 초점 위치 표시.
  Offset? _focusRing;
  Timer? _focusRingTimer;

  /// 실시간 인식 상태.
  bool _streaming = false;
  bool _frameBusy = false;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  VoteResult _liveVote = const VoteResult();

  /// 백그라운드로 가면서 카메라를 해제했으면 복귀할 때 다시 연다.
  bool _releasedForBackground = false;

  /// 권한 설정 화면에서 돌아오면 카메라를 다시 시도한다.
  bool _awaitingSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusRingTimer?.cancel();
    _controller?.dispose();
    _ocr.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_resultOpen) return;
    switch (state) {
      case AppLifecycleState.inactive:
        // 권한 요청 알림도 inactive를 발생시키므로, 초기화가 끝난 카메라만 해제한다.
        if (_controller?.value.isInitialized ?? false) {
          _releaseCamera();
          _releasedForBackground = true;
        }
      case AppLifecycleState.resumed:
        // 권한을 거절한 직후 바로 다시 요청하지 않도록, 필요한 경우에만 다시 연다.
        if (_releasedForBackground || _awaitingSettings) {
          _releasedForBackground = false;
          _awaitingSettings = false;
          _initCamera();
        }
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // 카메라

  Future<void> _initCamera() async {
    if (_initializing) return;
    _initializing = true;
    if (_status != _CameraStatus.initializing) {
      setState(() => _status = _CameraStatus.initializing);
    }

    CameraController? controller;
    try {
      final cameras = await availableCameras();
      final camera = cameras
              .where((c) => c.lensDirection == CameraLensDirection.back)
              .firstOrNull ??
          cameras.firstOrNull;
      if (camera == null) {
        if (mounted) setState(() => _status = _CameraStatus.unavailable);
        return;
      }

      controller = CameraController(
        camera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        // ML Kit이 그대로 받을 수 있는 프레임 형식.
        imageFormatGroup: mlKitImageFormatGroup,
      );
      await controller.initialize();
      try {
        await controller.setFlashMode(FlashMode.off);
      } on CameraException {
        // 플래시가 없는 기기
      }

      if (!mounted || _resultOpen) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _torchOn = false;
        _status = _CameraStatus.ready;
      });
      // 초점과 노출을 안내문이 놓일 가이드 중앙에 맞춘다.
      final view = _viewSize;
      if (view != null) _setFocus(ScanGuideOverlay.guideRect(view).center, showRing: false);
      await _startLive();
    } on CameraException catch (e) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        _status = _permissionErrors.contains(e.code)
            ? _CameraStatus.permissionDenied
            : _CameraStatus.unavailable;
      });
    } finally {
      _initializing = false;
    }
  }

  void _releaseCamera() {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    _torchOn = false;
    _streaming = false;
    _voter.clear();
    _liveVote = const VoteResult();
    if (mounted) setState(() {});
    controller.dispose();
  }

  /// 화면 위의 점에 초점·노출을 맞춘다. 프리뷰는 cover로 잘려 보이므로 좌표를 변환한다.
  Future<void> _setFocus(Offset viewPoint, {bool showRing = true}) async {
    final controller = _controller;
    final view = _viewSize;
    final preview = controller?.value.previewSize;
    if (controller == null || !controller.value.isInitialized || view == null || preview == null) {
      return;
    }
    // previewSize는 가로 기준이라 세로 화면에서는 너비/높이를 뒤집는다.
    final content = Size(preview.height, preview.width);
    final p = mapCoverPointToImage(viewPoint, viewSize: view, imageSize: content);
    final normalized = Offset(
      (p.dx / content.width).clamp(0.0, 1.0),
      (p.dy / content.height).clamp(0.0, 1.0),
    );

    if (showRing) {
      _focusRingTimer?.cancel();
      setState(() => _focusRing = viewPoint);
      _focusRingTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _focusRing = null);
      });
    }
    try {
      await controller.setFocusPoint(normalized);
      await controller.setExposurePoint(normalized);
    } on CameraException {
      // 초점 영역 지정을 지원하지 않는 기기
    }
  }

  // ---------------------------------------------------------------------------
  // 실시간 인식

  Future<void> _startLive() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _streaming) return;
    try {
      await controller.startImageStream(_onFrame);
      _streaming = true;
    } on CameraException {
      // 프레임 스트림을 지원하지 않는 기기. 셔터 촬영만 쓴다.
    }
  }

  Future<void> _stopLive() async {
    final controller = _controller;
    if (controller == null || !_streaming) return;
    _streaming = false;
    try {
      await controller.stopImageStream();
    } on CameraException {
      // 이미 멈춤
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_frameBusy || !_streaming || _processing || _resultOpen) return;
    if (DateTime.now().difference(_lastFrameAt) < _liveInterval) return;
    final controller = _controller;
    if (controller == null) return;
    final input = inputImageFromFrame(image, controller);
    final rotation = frameRotation(controller);
    if (input == null || rotation == null) return;

    _frameBusy = true;
    _lastFrameAt = DateTime.now();
    try {
      final results = await _ocr.recognizeImage(input);
      final credential = _extractor.fromOcrResults(_insideGuide(results, image, rotation));
      _voter.add(credential);
      final vote = _voter.vote();
      if (mounted && _streaming) setState(() => _liveVote = vote);
    } on Exception {
      // 프레임 하나의 실패는 무시한다.
    } finally {
      _frameBusy = false;
    }
  }

  /// 가이드 영역 안의 줄만 남긴다. 좌표계가 어긋나 모두 걸러지면 원본을 쓴다.
  List<OcrResult> _insideGuide(List<OcrResult> results, CameraImage image, InputImageRotation rotation) {
    final view = _viewSize;
    if (view == null) return results;
    // 프레임과 프리뷰의 비율이 조금 다를 수 있어 여유를 넉넉히 둔다.
    final guide = mapCoverRectToImage(
      viewRect: ScanGuideOverlay.guideRect(view),
      viewSize: view,
      imageSize: uprightFrameSize(image, rotation),
      margin: 0.25,
    );
    final filtered = [
      for (final r in results) r.withLines(r.lines.where((l) => guide.contains(l.box.center)).toList()),
    ];
    return filtered.every((r) => r.lines.isEmpty) ? results : filtered;
  }

  // ---------------------------------------------------------------------------
  // 촬영

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        _processing) {
      return;
    }

    setState(() => _processing = true);
    // 사진 촬영과 프레임 분석을 동시에 쓰지 못하는 기기가 있어 스트림을 먼저 멈춘다.
    await _stopLive();

    WifiCredential? credential;
    try {
      final file = await controller.takePicture();
      // 진동은 촬영이 끝난 뒤에. 촬영 직전에 울리면 손떨림으로 글자가 번진다.
      HapticFeedback.mediumImpact();

      String? cropPath;
      try {
        final stopwatch = Stopwatch()..start();
        // 가이드 영역만 인식해 주변 글자(메뉴판 등)가 섞이지 않게 한다.
        final view = _viewSize;
        if (view != null) {
          cropPath = await cropImageFile(
            path: file.path,
            viewRect: ScanGuideOverlay.guideRect(view),
            viewSize: view,
          );
        }
        final cropMs = stopwatch.elapsedMilliseconds;
        final results = await _ocr.recognizeFileWithAllScripts(cropPath ?? file.path);
        credential = _extractor.fromOcrResults(results);
        // 시간만 기록한다. 인식된 내용(비밀번호 포함)은 절대 로그에 남기지 않는다.
        if (kDebugMode) {
          debugPrint('[ocr] crop ${cropMs}ms, recognize ${stopwatch.elapsedMilliseconds - cropMs}ms, '
              'live readings ${_voter.count}');
        }

        // 안내문이 가이드보다 크게 찍혀 글자가 잘렸을 수 있으니, 빠진 값이 있으면
        // 전체 사진으로 한 번 더 인식해 채운다. 가이드 안에서 찾은 값이 우선이다.
        if (cropPath != null && (!credential.hasSsid || !credential.hasPassword)) {
          final full = await _ocr.recognizeFileWithAllScripts(file.path);
          credential = _extractor.fillMissing(credential, _extractor.fromOcrResults(full));
        }

        // 프리뷰 동안 읽은 여러 프레임과 다수결로 합쳐 한 장짜리 오류를 걸러낸다.
        credential = _voter.combine(credential);
      } finally {
        // 촬영 이미지에는 비밀번호가 담겨 있으므로 인식 직후 지운다.
        _deleteQuietly(file.path);
        if (cropPath != null) _deleteQuietly(cropPath);
      }
    } on CameraException {
      _showMessage('촬영하지 못했어요. 다시 시도해주세요.');
    } on Exception {
      _showMessage('글자를 인식하지 못했어요. 다시 시도해주세요.');
    }

    if (!mounted) return;
    setState(() => _processing = false);
    if (credential != null) {
      await _openResult(credential);
    } else {
      await _startLive();
    }
  }

  /// 갤러리에서 고른 안내문 사진을 인식한다. 가이드 영역이 없으므로 사진 전체를 읽는다.
  Future<void> _pickFromGallery() async {
    if (_processing) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    setState(() => _processing = true);
    await _stopLive();
    WifiCredential? credential;
    try {
      final results = await _ocr.recognizeFileWithAllScripts(picked.path);
      credential = _extractor.fromOcrResults(results);
    } on Exception {
      _showMessage('사진에서 글자를 인식하지 못했어요.');
    } finally {
      // image_picker가 앱 캐시에 복사한 사본. 비밀번호가 담겨 있으니 바로 지운다.
      _deleteQuietly(picked.path);
    }
    if (!mounted) return;
    setState(() => _processing = false);
    if (credential != null) {
      await _openResult(credential);
    } else {
      await _startLive();
    }
  }

  /// 실시간 인식이 안정된 값을 셔터 없이 결과 화면으로 넘긴다.
  Future<void> _confirmLive() async {
    final vote = _liveVote;
    if (!vote.isStable || _processing) return;
    setState(() => _processing = true);
    await _stopLive();
    final credential = _voter.toCredential(vote, sources: const []);
    if (!mounted) return;
    setState(() => _processing = false);
    await _openResult(credential);
  }

  Future<void> _openResult(WifiCredential credential, {bool manualEntry = false}) async {
    final reopenCamera = _status == _CameraStatus.ready;
    _resultOpen = true;
    // 결과 화면에 있는 동안에는 카메라를 끈다 (배터리, OS 연결 확인 화면과의 충돌 방지).
    _releaseCamera();

    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WifiResultScreen(credential: credential, manualEntry: manualEntry),
    ));

    _resultOpen = false;
    if (mounted && reopenCamera) _initCamera();
  }

  void _openManualEntry() => _openResult(WifiCredential.empty, manualEntry: true);

  void _openSettings() {
    _awaitingSettings = true;
    openAppSettings();
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    final next = !_torchOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchOn = next);
    } on CameraException {
      _showMessage('플래시를 사용할 수 없어요.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _deleteQuietly(String path) {
    File(path).delete().then((_) {}, onError: (_) {});
  }

  // ---------------------------------------------------------------------------
  // 화면

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: switch (_status) {
          _CameraStatus.permissionDenied => CameraMessageView(
              icon: Icons.no_photography_outlined,
              message: 'Wi-Fi 안내문을 촬영하려면\n카메라 권한이 필요합니다.',
              actionLabel: '설정 열기',
              onAction: _openSettings,
              onManualEntry: _openManualEntry,
            ),
          _CameraStatus.unavailable => CameraMessageView(
              icon: Icons.videocam_off_outlined,
              message: '카메라를 사용할 수 없어요.',
              actionLabel: '다시 시도',
              onAction: _initCamera,
              onManualEntry: _openManualEntry,
            ),
          _ => _buildScanner(),
        },
      ),
    );
  }

  Widget _buildScanner() {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final vote = _liveVote;
    final showBanner = ready && !_processing && vote.isStable;

    return LayoutBuilder(builder: (context, constraints) {
      _viewSize = constraints.biggest;
      final ring = _focusRing;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (ready) CoverCameraPreview(controller: controller),
          ScanGuideOverlay(
            processing: _processing,
            reading: !_processing && _voter.count > 0 && !vote.isStable,
          ),
          // 탭한 곳에 초점을 맞춘다 (글자가 흐리면 인식률이 크게 떨어진다).
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: ready && !_processing ? (d) => _setFocus(d.localPosition) : null,
            ),
          ),
          if (ring != null)
            Positioned(
              left: ring.dx - 32,
              top: ring.dy - 32,
              child: const IgnorePointer(child: _FocusRing()),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: showBanner
                        ? Padding(
                            key: const ValueKey('banner'),
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                            child: LiveResultBanner(
                              ssid: vote.ssid!.value,
                              hasPassword: vote.password!.value.isNotEmpty,
                              onConfirm: _confirmLive,
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('none')),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: '갤러리에서 선택',
                                iconSize: 26,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white24,
                                  foregroundColor: Colors.white,
                                  fixedSize: const Size(52, 52),
                                ),
                                onPressed: _processing ? null : _pickFromGallery,
                                icon: const Icon(Icons.photo_library_outlined),
                              ),
                              const SizedBox(width: 4),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(44, 48),
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                onPressed: _processing ? null : _openManualEntry,
                                child: const Text('직접 입력'),
                              ),
                            ],
                          ),
                        ),
                        ShutterButton(onPressed: ready && !_processing ? _capture : null),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              tooltip: _torchOn ? '플래시 끄기' : '플래시 켜기',
                              iconSize: 26,
                              style: IconButton.styleFrom(
                                backgroundColor: _torchOn ? Colors.white : Colors.white24,
                                foregroundColor: _torchOn ? Colors.black : Colors.white,
                                fixedSize: const Size(52, 52),
                              ),
                              onPressed: ready && !_processing ? _toggleTorch : null,
                              icon: Icon(_torchOn ? Icons.flashlight_on : Icons.flashlight_off),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _FocusRing extends StatelessWidget {
  const _FocusRing();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
      ),
    );
  }
}
