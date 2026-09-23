import 'package:flutter/material.dart';

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
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF5DD39E), size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Wi-Fi 정보를 찾았어요',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasPassword ? '$ssid · 비밀번호 인식됨' : '$ssid · 비밀번호 없음',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              onPressed: onConfirm,
              child: const Text('확인'),
            ),
          ],
        ),
      ),
    );
  }
}
