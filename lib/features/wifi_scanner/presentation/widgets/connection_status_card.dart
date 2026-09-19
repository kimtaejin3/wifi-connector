import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/services/wifi_service.dart';

/// 연결 요청 결과를 보여준다.
class ConnectionStatusCard extends StatelessWidget {
  const ConnectionStatusCard({super.key, required this.result, this.onOpenWifiSettings});

  final WifiConnectResult result;

  /// Wi-Fi 꺼짐 / 미지원 기기에서 설정 화면으로 보내는 버튼. Android에서만 표시.
  final VoidCallback? onOpenWifiSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, title, body) = switch (result.status) {
      WifiConnectStatus.connected => (
          Icons.check_circle_rounded,
          AppTheme.success,
          'Wi-Fi에 연결되었습니다.',
          null,
        ),
      WifiConnectStatus.requested => (
          Icons.check_circle_rounded,
          AppTheme.success,
          'Wi-Fi 연결 요청이 완료되었습니다.',
          '잠시 후에도 연결되지 않으면 비밀번호를 확인해주세요.',
        ),
      WifiConnectStatus.suggested => (
          Icons.check_circle_rounded,
          AppTheme.success,
          'Wi-Fi 연결 요청이 완료되었습니다.',
          '알림에서 네트워크 연결을 허용하면 자동으로 연결돼요.',
        ),
      WifiConnectStatus.cancelled => (
          Icons.info_rounded,
          scheme.onSurfaceVariant,
          'Wi-Fi 연결이 취소되었습니다.',
          null,
        ),
      WifiConnectStatus.failed => switch (result.failure) {
          WifiConnectFailure.invalidPassword => (
              Icons.error_rounded,
              scheme.error,
              '연결할 수 없습니다.',
              '비밀번호를 확인해주세요.',
            ),
          WifiConnectFailure.invalidSsid => (
              Icons.error_rounded,
              scheme.error,
              'Wi-Fi에 연결하지 못했습니다.',
              'Wi-Fi 이름을 확인해주세요.',
            ),
          WifiConnectFailure.wifiDisabled => (
              Icons.wifi_off_rounded,
              scheme.error,
              'Wi-Fi가 꺼져 있어요.',
              'Wi-Fi를 켠 뒤 다시 시도해주세요.',
            ),
          WifiConnectFailure.unsupported => (
              Icons.error_rounded,
              scheme.error,
              '이 기기에서는 자동 연결을 지원하지 않아요.',
              'Wi-Fi 설정에서 직접 연결해주세요.',
            ),
          _ => (
              Icons.error_rounded,
              scheme.error,
              'Wi-Fi에 연결하지 못했습니다.',
              'SSID 또는 비밀번호를 확인해주세요.',
            ),
        },
    };

    final showSettings = onOpenWifiSettings != null &&
        defaultTargetPlatform == TargetPlatform.android &&
        (result.failure == WifiConnectFailure.wifiDisabled ||
            result.failure == WifiConnectFailure.unsupported);

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface),
                  ),
                  if (body != null) ...[
                    const SizedBox(height: 4),
                    Text(body, style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
                  ],
                  if (showSettings)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        onPressed: onOpenWifiSettings,
                        child: const Text('Wi-Fi 설정 열기'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
