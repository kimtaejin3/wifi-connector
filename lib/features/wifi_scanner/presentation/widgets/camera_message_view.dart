import 'package:flutter/material.dart';

/// 카메라를 쓸 수 없을 때(권한 거절, 카메라 없음) 보여주는 안내.
class CameraMessageView extends StatelessWidget {
  const CameraMessageView({
    super.key,
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.onManualEntry,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onManualEntry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          children: [
            const Spacer(),
            Icon(icon, size: 48, color: Colors.white70),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: onAction,
              child: Text(actionLabel),
            ),
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              onPressed: onManualEntry,
              child: const Text('직접 입력하기'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
