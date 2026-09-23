import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import '../../../../core/utils/platform_channel.dart';
import '../../data/models/wifi_credential.dart';
import '../../data/services/camera_frame.dart';
import '../../domain/services/wifi_qr_parser.dart';
import '../widgets/camera_message_view.dart';
import '../widgets/cover_camera_preview.dart';
import '../widgets/scan_guide_overlay.dart';
import 'wifi_result_screen.dart';

enum _CameraStatus { initializing, ready, permissionDenied, unavailable }

/// Wi-Fi QR 코드(`WIFI:T:WPA;S:...;P:...;;`)를 프리뷰에서 바로 읽는다.
/// 인식은 ML Kit 바코드 스캐너로 기기 안에서만 처리한다.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> with WidgetsBindingObserver {
  static const _permissionErrors = {
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
  };
  static const _frameInterval = Duration(milliseconds: 250);

  final _scanner = BarcodeScanner(formats: const [BarcodeFormat.qrCode]);

  CameraController? _controller;
  _CameraStatus _status = _CameraStatus.initializing;
  bool _initializing = false;
  bool _streaming = false;
  bool _frameBusy = false;
  bool _resultOpen = false;
  bool _torchOn = false;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastNoticeAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _releasedForBackground = false;
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
    _scanner.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_resultOpen) return;
    switch (state) {
      case AppLifecycleState.inactive:
        if (_controller?.value.isInitialized ?? false) {
          _releaseCamera();
          _releasedForBackground = true;
        }
      case AppLifecycleState.resumed:
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
      controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: mlKitImageFormatGroup,
      );
      await controller.initialize();
      if (!mounted || _resultOpen) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _torchOn = false;
        _status = _CameraStatus.ready;
      });
      try {
        await controller.startImageStream(_onFrame);
        _streaming = true;
      } on CameraException {
        if (mounted) setState(() => _status = _CameraStatus.unavailable);
      }
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
    _streaming = false;
    _torchOn = false;
    if (mounted) setState(() {});
    controller.dispose();
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_frameBusy || !_streaming || _resultOpen) return;
    if (DateTime.now().difference(_lastFrameAt) < _frameInterval) return;
    final controller = _controller;
    if (controller == null) return;
    final input = inputImageFromFrame(image, controller);
    if (input == null) return;

    _frameBusy = true;
    _lastFrameAt = DateTime.now();
    try {
      final barcodes = await _scanner.processImage(input);
      if (!mounted || _resultOpen) return;
      for (final barcode in barcodes) {
        final wifi = _wifiOf(barcode);
        if (wifi != null) {
          await _found(wifi);
          return;
        }
      }
      if (barcodes.isNotEmpty) _notice('Wi-Fi QR 코드가 아니에요.');
    } on Exception {
      // 프레임 하나의 실패는 무시한다.
    } finally {
      _frameBusy = false;
    }
  }

  WifiQr? _wifiOf(Barcode barcode) {
    final value = barcode.value;
    if (value is BarcodeWifi && (value.ssid ?? '').isNotEmpty) {
      final open = value.encryptionType == 1; // BarcodeWifiEncryptionType.open
      return WifiQr(ssid: value.ssid!, password: open ? '' : (value.password ?? ''));
    }
    return parseWifiQr(barcode.rawValue);
  }

  Future<void> _found(WifiQr wifi) async {
    _resultOpen = true;
    HapticFeedback.mediumImpact();
    _releaseCamera();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WifiResultScreen(
        credential: WifiCredential(
          ssid: wifi.ssid,
          password: wifi.password,
          ssidConfidence: 1,
          passwordConfidence: 1,
          candidates: [
            WifiCandidate(value: wifi.ssid, type: WifiCandidateType.ssid, score: 1),
            WifiCandidate(value: wifi.password, type: WifiCandidateType.password, score: 1),
          ],
        ),
        title: 'Wi-Fi QR을 찾았어요',
        retakeLabel: '다시 스캔',
      ),
    ));
    _resultOpen = false;
    if (mounted) _initCamera();
  }

  void _notice(String message) {
    if (DateTime.now().difference(_lastNoticeAt) < const Duration(seconds: 3)) return;
    _lastNoticeAt = DateTime.now();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openSettings() {
    _awaitingSettings = true;
    openAppSettings();
  }

  void _openManualEntry() async {
    _resultOpen = true;
    _releaseCamera();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const WifiResultScreen(credential: WifiCredential.empty, manualEntry: true),
    ));
    _resultOpen = false;
    if (mounted) _initCamera();
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    final next = !_torchOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchOn = next);
    } on CameraException {
      _notice('플래시를 사용할 수 없어요.');
    }
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
              message: 'QR 코드를 읽으려면\n카메라 권한이 필요합니다.',
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
        if (ready) CoverCameraPreview(controller: controller),
        const ScanGuideOverlay(caption: 'Wi-Fi QR 코드를\n영역 안에 맞춰주세요'),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: _openManualEntry,
                    child: const Text('직접 입력'),
                  ),
                  IconButton(
                    tooltip: _torchOn ? '플래시 끄기' : '플래시 켜기',
                    iconSize: 26,
                    style: IconButton.styleFrom(
                      backgroundColor: _torchOn ? Colors.white : Colors.white24,
                      foregroundColor: _torchOn ? Colors.black : Colors.white,
                      fixedSize: const Size(52, 52),
                    ),
                    onPressed: ready ? _toggleTorch : null,
                    icon: Icon(_torchOn ? Icons.flashlight_on : Icons.flashlight_off),
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
