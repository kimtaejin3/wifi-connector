import 'package:flutter/material.dart';

import 'camera_screen.dart';
import 'history_screen.dart';

/// 하단 메뉴: 안내문 촬영 · 기록.
///
/// 카메라 탭을 떠나면 카메라를 놓아야 하므로 선택된 탭만 만든다 (IndexedStack 사용 안 함).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _index == 0 ? Colors.black : null,
      body: _index == 0
          ? const CameraScreen(key: ValueKey('camera'))
          : const HistoryScreen(key: ValueKey('history')),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon: Icon(Icons.document_scanner_rounded),
            label: '안내문',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: '기록',
          ),
        ],
      ),
    );
  }
}
