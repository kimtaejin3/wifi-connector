import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/core/theme/app_theme.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/wifi_history_store.dart';
import 'package:wifi_connector/features/wifi_scanner/presentation/screens/history_screen.dart';

import 'wifi_history_store_test.dart' show InMemoryStore, entry;

void main() {
  Future<void> pump(WidgetTester tester, WifiHistoryStore store) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: HistoryScreen(store: store)));
    await tester.pumpAndSettle();
  }

  testWidgets('기록이 없어도 개인정보 처리방침 링크가 보인다', (tester) async {
    await pump(tester, WifiHistoryStore(store: InMemoryStore()));
    expect(find.text('개인정보 처리방침'), findsOneWidget);
  });

  testWidgets('기록이 있으면 목록 아래에 개인정보 처리방침 링크가 있다', (tester) async {
    final store = WifiHistoryStore(store: InMemoryStore());
    await store.save(entry('cafe'));
    await pump(tester, store);
    expect(find.text('cafe'), findsOneWidget);
    expect(find.text('개인정보 처리방침'), findsOneWidget);
    expect(tester.getTopLeft(find.text('개인정보 처리방침')).dy, greaterThan(tester.getTopLeft(find.text('cafe')).dy));
  });

  test('링크는 스토어에 등록한 개인정보 처리방침 주소다', () {
    expect(privacyPolicyUrl.toString(), 'https://wifi-lens.vercel.app/privacy');
  });
}
