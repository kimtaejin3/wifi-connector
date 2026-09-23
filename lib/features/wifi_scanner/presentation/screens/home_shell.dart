import 'package:flutter/material.dart';

import 'camera_screen.dart';
import 'history_screen.dart';
import 'qr_scan_screen.dart';

/// 하단 메뉴: 안내문 촬영 · QR 인식 · 인식 기록.
///
/// 카메라를 쓰는 탭은 하나만 살아 있어야 하므로 선택된 탭만 만든다 (IndexedStack 사용 안 함).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final dark = _index != 2;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: dark ? Colors.black : scheme.surface,
      body: switch (_index) {
        0 => const CameraScreen(key: ValueKey('camera')),
        1 => const QrScanScreen(key: ValueKey('qr')),
        _ => const HistoryScreen(key: ValueKey('history')),
      },
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: dark ? const Color(0xFF111111) : scheme.surface,
          indicatorColor: dark ? Colors.white24 : scheme.surfaceContainerHighest,
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(color: dark ? Colors.white : scheme.onSurface),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: dark ? Colors.white : scheme.onSurface,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.document_scanner_outlined),
              selectedIcon: Icon(Icons.document_scanner_rounded),
              label: '안내문',
            ),
            NavigationDestination(
              icon: Icon(Icons.qr_code_scanner_rounded),
              label: 'QR',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history_rounded),
              label: '기록',
            ),
          ],
        ),
      ),
    );
  }
}
