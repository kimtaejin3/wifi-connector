import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/services/wifi_service.dart';

/// 연결 요청 결과와 그 뒤의 실제 연결 확인 결과를 보여준다.
class ConnectionStatusCard extends StatelessWidget {
  const ConnectionStatusCard({
    super.key,
    required this.result,
    this.check,
    this.verifying = false,
    this.onOpenWifiSettings,
  });

  final WifiConnectResult result;

  /// [WifiService.awaitConnection] 결과. 아직 확인 전이면 null.
  final WifiConnectionCheck? check;

  /// 연결 확인이 진행 중.
  final bool verifying;

  /// Wi-Fi 설정 화면으로 보내는 버튼. Android에서만 표시.
  final VoidCallback? onOpenWifiSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = AppPalette.of(context);
    final state = _state(scheme, p);

    final showSettings = onOpenWifiSettings != null &&
        defaultTargetPlatform == TargetPlatform.android &&
        state.suggestSettings;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: state.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: state.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: state.icon == null
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: state.color),
                    )
                  : Icon(state.icon, color: state.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.title,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.ink),
                  ),
                  if (state.body != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      state.body!,
                      style: TextStyle(fontSize: 13, color: p.muted, height: 1.45),
                    ),
                  ],
                  if (showSettings)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: p.accent,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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

  _CardState _state(ColorScheme scheme, AppPalette p) {
    switch (result.status) {
      case WifiConnectStatus.connected:
        return _CardState(Icons.check_circle_rounded, p.success, 'Wi-Fi에 연결되었습니다.');

      case WifiConnectStatus.cancelled:
        return _CardState(Icons.info_rounded, p.muted, 'Wi-Fi 연결이 취소되었습니다.');

      case WifiConnectStatus.failed:
        return switch (result.failure) {
          WifiConnectFailure.invalidPassword => _CardState(
              Icons.error_rounded,
              p.danger,
              '연결할 수 없습니다.',
              body: '비밀번호를 확인해주세요.',
            ),
          WifiConnectFailure.invalidSsid => _CardState(
              Icons.error_rounded,
              p.danger,
              'Wi-Fi에 연결하지 못했습니다.',
              body: 'Wi-Fi 이름을 확인해주세요.',
            ),
          WifiConnectFailure.wifiDisabled => _CardState(
              Icons.wifi_off_rounded,
              p.danger,
              'Wi-Fi가 꺼져 있어요.',
              body: 'Wi-Fi를 켠 뒤 다시 시도해주세요.',
              suggestSettings: true,
            ),
          WifiConnectFailure.unsupported => _CardState(
              Icons.error_rounded,
              p.danger,
              '이 기기에서는 자동 연결을 지원하지 않아요.',
              body: 'Wi-Fi 설정에서 직접 연결해주세요.',
              suggestSettings: true,
            ),
          _ => _CardState(
              Icons.error_rounded,
              p.danger,
              'Wi-Fi에 연결하지 못했습니다.',
              body: 'SSID 또는 비밀번호를 확인해주세요.',
            ),
        };

      case WifiConnectStatus.requested:
      case WifiConnectStatus.suggested:
        final suggested = result.status == WifiConnectStatus.suggested;
        if (result.alreadySaved && check == null && !verifying) {
          return _CardState(
            Icons.info_rounded,
            p.success,
            '이미 저장된 네트워크예요.',
            body: '이미 연결돼 있다면 그대로 쓰시면 돼요. 연결돼 있지 않으면 Wi-Fi 설정에서 이 네트워크를 선택하고, '
                '비밀번호가 바뀌었으면 설정에서 지운 뒤 다시 시도해주세요.',
            suggestSettings: true,
          );
        }
        if (verifying) {
          return _CardState(
            null,
            p.accent,
            '연결 요청이 완료되었습니다.',
            body: suggested
                ? '알림에서 네트워크 연결을 허용하면 연결돼요. 확인하고 있어요…'
                : '연결되는지 확인하고 있어요…',
          );
        }
        final c = check;
        if (c == null) {
          return _CardState(
            Icons.check_circle_rounded,
            p.success,
            'Wi-Fi 연결 요청이 완료되었습니다.',
            body: suggested
                ? '알림에서 네트워크 연결을 허용하면 자동으로 연결돼요.'
                : '잠시 후에도 연결되지 않으면 비밀번호를 확인해주세요.',
          );
        }
        if (c.connected) {
          return _CardState(
            Icons.check_circle_rounded,
            p.success,
            'Wi-Fi에 연결되었습니다.',
            body: c.captivePortal ? '브라우저 로그인이 필요한 Wi-Fi예요. 상단 알림을 눌러 로그인하세요.' : null,
          );
        }
        final String why;
        if (result.alreadySaved) {
          why = '이미 저장된 네트워크예요. 이미 연결돼 있을 수 있고, 저장된 비밀번호가 다르면 '
              'Wi-Fi 설정에서 이 네트워크를 지운 뒤 다시 시도해주세요.';
        } else if (suggested) {
          why = '알림에서 허용했는지 확인해주세요. 그래도 연결되지 않으면 Wi-Fi 이름의 대소문자와 비밀번호를 확인해주세요.';
        } else {
          why = '잠시 후에도 연결되지 않으면 Wi-Fi 이름의 대소문자와 비밀번호를 확인해주세요.';
        }
        return _CardState(
          Icons.help_rounded,
          p.muted,
          '아직 연결을 확인하지 못했어요.',
          body: why,
          suggestSettings: true,
        );
    }
  }
}

class _CardState {
  const _CardState(this.icon, this.color, this.title, {this.body, this.suggestSettings = false});

  /// null이면 진행 표시를 보여준다.
  final IconData? icon;
  final Color color;
  final String title;
  final String? body;
  final bool suggestSettings;
}
