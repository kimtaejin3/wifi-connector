import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/platform_channel.dart';
import '../../data/models/wifi_credential.dart';
import '../../data/services/ocr_service.dart';
import '../../domain/services/wifi_credential_parser.dart';
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
  final _parser = const WifiCredentialParser();

  CameraController? _controller;
  _CameraStatus _status = _CameraStatus.initializing;
  bool _initializing = false;
  bool _processing = false;
  bool _torchOn = false;
  bool _resultOpen = false;

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

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        _processing) {
      return;
    }

    setState(() => _processing = true);
    HapticFeedback.mediumImpact();

    WifiCredential? credential;
    String? rawText;
    try {
      final file = await controller.takePicture();
      try {
        final ocr = await _ocr.recognizeFile(file.path);
        rawText = ocr.text;
        credential = _parser.parse(ocr.layoutText);
        if (credential.isEmpty) credential = _parser.parse(ocr.text);
      } finally {
        // 촬영 이미지에는 비밀번호가 담겨 있으므로 인식 직후 지운다.
        _deleteQuietly(file.path);
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

    return Stack(
      fit: StackFit.expand,
      children: [
        if (ready) _CoverCameraPreview(controller: controller),
        ScanGuideOverlay(processing: _processing),
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
