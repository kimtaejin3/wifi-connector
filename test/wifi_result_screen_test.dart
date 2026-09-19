import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/core/theme/app_theme.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/wifi_credential.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/wifi_service.dart';
import 'package:wifi_connector/features/wifi_scanner/presentation/screens/wifi_result_screen.dart';

class FakeWifiService extends WifiService {
  FakeWifiService(this.result);

  final WifiConnectResult result;
  final calls = <(String, String)>[];

  @override
  Future<WifiConnectResult> connect({required String ssid, required String password}) async {
    calls.add((ssid, password));
    return result;
  }
}

Future<void> pumpResult(
  WidgetTester tester,
  WifiCredential credential, {
  WifiService service = const WifiService(),
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: WifiResultScreen(credential: credential, wifiService: service),
  ));
  await tester.pumpAndSettle();
}

const found = WifiCredential(
  ssid: 'TestCafe',
  password: 'Test12345',
  ssidConfidence: 0.95,
  passwordConfidence: 0.97,
);

void main() {
  testWidgets('인식한 SSID와 비밀번호를 보여주고 연결 요청한다', (tester) async {
    final service = FakeWifiService(const WifiConnectResult(WifiConnectStatus.requested));
    await pumpResult(tester, found, service: service);

    expect(find.text('Wi-Fi를 찾았어요'), findsOneWidget);
    expect(find.text('TestCafe'), findsOneWidget);
    expect(find.text('Test12345'), findsOneWidget);

    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();

    expect(service.calls, [('TestCafe', 'Test12345')]);
    expect(find.text('Wi-Fi 연결 요청이 완료되었습니다.'), findsOneWidget);
    expect(find.text('완료'), findsOneWidget);
  });

  testWidgets('수정한 값으로 연결한다', (tester) async {
    final service = FakeWifiService(const WifiConnectResult(WifiConnectStatus.requested));
    await pumpResult(tester, found, service: service);

    await tester.enterText(find.byType(TextField).last, 'Fixed12345');
    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();

    expect(service.calls.single, ('TestCafe', 'Fixed12345'));
  });

  testWidgets('사용자가 거절하면 취소 안내와 다시 연결 버튼', (tester) async {
    final service = FakeWifiService(const WifiConnectResult(WifiConnectStatus.cancelled));
    await pumpResult(tester, found, service: service);

    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();

    expect(find.text('Wi-Fi 연결이 취소되었습니다.'), findsOneWidget);
    expect(find.text('다시 연결'), findsOneWidget);
  });

  testWidgets('연결 실패 시 안내와 다시 시도 버튼', (tester) async {
    final service = FakeWifiService(
      const WifiConnectResult.failed(WifiConnectFailure.invalidPassword),
    );
    await pumpResult(tester, found, service: service);

    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();

    expect(find.text('연결할 수 없습니다.'), findsOneWidget);
    expect(find.text('비밀번호를 확인해주세요.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('비밀번호만 찾으면 SSID 입력 전까지 연결 버튼 비활성화', (tester) async {
    final service = FakeWifiService(const WifiConnectResult(WifiConnectStatus.requested));
    await pumpResult(
      tester,
      const WifiCredential(password: 'hello1234', passwordConfidence: 0.9),
      service: service,
    );

    expect(find.textContaining('Wi-Fi 이름을 찾지 못했어요'), findsOneWidget);
    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();
    expect(service.calls, isEmpty);

    await tester.enterText(find.byType(TextField).first, 'MOMO_CAFE');
    await tester.pump();
    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();
    expect(service.calls.single, ('MOMO_CAFE', 'hello1234'));
  });

  testWidgets('8자 미만 비밀번호는 요청 전에 막는다', (tester) async {
    final service = FakeWifiService(const WifiConnectResult(WifiConnectStatus.requested));
    await pumpResult(
      tester,
      const WifiCredential(ssid: 'cafe', password: '1234', ssidConfidence: 0.95),
      service: service,
    );

    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();

    expect(service.calls, isEmpty);
    expect(find.textContaining('8자 이상'), findsOneWidget);
  });

  testWidgets('아무것도 찾지 못하면 재촬영 안내, 직접 입력 가능', (tester) async {
    await pumpResult(tester, WifiCredential.empty);

    expect(find.text('Wi-Fi 정보를 찾지 못했어요.'), findsOneWidget);
    expect(find.text('다시 촬영'), findsOneWidget);

    await tester.tap(find.text('직접 입력하기'));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi 정보를 입력해주세요'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('비밀번호 보기/숨기기', (tester) async {
    await pumpResult(tester, found);

    EditableText password() => tester.widget<EditableText>(find.byType(EditableText).last);
    expect(password().obscureText, isFalse);

    await tester.tap(find.byTooltip('비밀번호 숨기기'));
    await tester.pump();
    expect(password().obscureText, isTrue);
  });
}
