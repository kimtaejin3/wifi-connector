import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/platform_channel.dart';
import '../../data/models/wifi_credential.dart';
import '../../data/services/image_cropper.dart';
import '../../data/services/ocr_service.dart';
import '../../domain/services/wifi_credential_extractor.dart';
import '../widgets/camera_message_view.dart';
import '../widgets/scan_guide_overlay.dart';
import '../widgets/shutter_button.dart';
import 'wifi_result_screen.dart';

enum _CameraStatus { initializing, ready, permissionDenied, unavailable }

/// 앱 첫 화면. 카메라로 Wi-Fi 안내문을 촬영해 OCR → 파싱 후 결과 화면으로 보낸다.
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

  final _ocr = OcrService();
  final _extractor = const WifiCredentialExtractor();

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

      controller = CameraController(camera, ResolutionPreset.veryHigh, enableAudio: false);
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

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        _processing) {
      return;
    }

    setState(() => _processing = true);

    WifiCredential? credential;
    String? rawText;
    try {
      final file = await controller.takePicture();
      // 진동은 촬영이 끝난 뒤에. 촬영 직전에 울리면 손떨림으로 글자가 번진다.
      HapticFeedback.mediumImpact();

      String? cropPath;
      try {
        // 가이드 영역만 인식해 주변 글자(메뉴판 등)가 섞이지 않게 한다.
        final view = _viewSize;
        if (view != null) {
          cropPath = await cropImageFile(
            path: file.path,
            viewRect: ScanGuideOverlay.guideRect(view),
            viewSize: view,
          );
        }
        final results = await _ocr.recognizeFileWithAllScripts(cropPath ?? file.path);
        credential = _extractor.fromOcrResults(results);
        rawText = _debugText(results);

        // 안내문이 가이드보다 크게 찍혀 글자가 잘렸을 수 있으니, 빠진 값이 있으면
        // 전체 사진으로 한 번 더 인식해 채운다. 가이드 안에서 찾은 값이 우선이다.
        if (cropPath != null && (!credential.hasSsid || !credential.hasPassword)) {
          final full = await _ocr.recognizeFileWithAllScripts(file.path);
          credential = _extractor.parser.merge([credential, _extractor.fromOcrResults(full)]);
          rawText = _debugText([...results, ...full]);
        }
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
    if (credential != null) await _openResult(credential, rawText: rawText);
  }

  /// 디버그 화면용 원문. 릴리스에서는 만들지 않는다.
  String? _debugText(List<OcrResult> results) {
    if (!kDebugMode) return null;
    return results.map((r) => '── ${r.script.name} ──\n${r.layoutText}').join('\n\n');
  }

  Future<void> _openResult(
    WifiCredential credential, {
    String? rawText,
    bool manualEntry = false,
  }) async {
    final reopenCamera = _status == _CameraStatus.ready;
    _resultOpen = true;
    // 결과 화면에 있는 동안에는 카메라를 끈다 (배터리, OS 연결 확인 화면과의 충돌 방지).
    _releaseCamera();

    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WifiResultScreen(
        credential: credential,
        rawText: rawText,
        manualEntry: manualEntry,
      ),
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

    return LayoutBuilder(builder: (context, constraints) {
      _viewSize = constraints.biggest;
      final ring = _focusRing;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (ready) _CoverCameraPreview(controller: controller),
          ScanGuideOverlay(processing: _processing),
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: _processing ? null : _openManualEntry,
                          child: const Text('직접 입력'),
                        ),
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

/// 프리뷰를 비율을 유지한 채 화면 전체를 채우도록 확대한다.
class _CoverCameraPreview extends StatelessWidget {
  const _CoverCameraPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return const SizedBox.shrink();
    // previewSize는 가로 기준이므로 세로 화면에서는 너비/높이를 뒤집는다.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}
