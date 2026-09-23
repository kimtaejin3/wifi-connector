import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// 실시간 인식이 여러 프레임에서 일치했을 때 셔터 없이 결과로 넘어갈 수 있게 하는 카드.
class LiveResultBanner extends StatelessWidget {
  const LiveResultBanner({
    super.key,
    required this.ssid,
    required this.hasPassword,
    required this.onConfirm,
  });

  final String ssid;
  final bool hasPassword;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Semantics(
      liveRegion: true,
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(AppPalette.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppPalette.cardRadius),
          onTap: onConfirm,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppPalette.cardRadius),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 10))],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(13)),
                  child: Icon(Icons.check_rounded, color: p.accent, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Wi-Fi 정보를 찾았어요',
                        style: TextStyle(color: p.ink, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasPassword ? '$ssid · 비밀번호 인식됨' : '$ssid · 비밀번호 없음',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  onPressed: onConfirm,
                  child: const Text('확인'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
