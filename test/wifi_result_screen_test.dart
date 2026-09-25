import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/core/theme/app_theme.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/wifi_credential.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/wifi_history_store.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/wifi_service.dart';
import 'package:wifi_connector/features/wifi_scanner/presentation/screens/wifi_result_screen.dart';

class FakeWifiService extends WifiService {
  FakeWifiService(this.result, {this.check = const WifiConnectionCheck(connected: true)});

  final WifiConnectResult result;
  final WifiConnectionCheck check;
  final calls = <(String, String)>[];
  final awaited = <String>[];

  @override
  Future<WifiConnectResult> connect({required String ssid, required String password}) async {
    calls.add((ssid, password));
    return result;
  }

  @override
  Future<WifiConnectionCheck> awaitConnection({required String ssid, Duration? timeout}) async {
    awaited.add(ssid);
    return check;
  }
}

class InMemoryStore implements SecureKeyValueStore {
  final map = <String, String>{};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);
}

Future<WifiHistoryStore> pumpResult(
  WidgetTester tester,
  WifiCredential credential, {
  WifiService service = const WifiService(),
  String? retakeLabel = '다시 촬영',
}) async {
  final history = WifiHistoryStore(store: InMemoryStore());
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: WifiResultScreen(
      credential: credential,
      wifiService: service,
      historyStore: history,
      retakeLabel: retakeLabel,
    ),
  ));
  await tester.pumpAndSettle();
  return history;
}


const found = WifiCredential(
  ssid: 'TestCafe',
  password: 'Test12345',
  ssidConfidence: 0.95,
  passwordConfidence: 0.97,
);

const requested = WifiConnectResult(WifiConnectStatus.requested);

void main() {
  testWidgets('인식한 SSID와 비밀번호를 보여주고, 요청 후 실제 연결을 확인하고, 기록에 남긴다', (tester) async {
    final service = FakeWifiService(requested);
    final history = await pumpResult(tester, found, service: service);

    expect(find.text('Wi-Fi를 찾았어요'), findsOneWidget);
    expect(find.text('TestCafe'), findsOneWidget);
    expect(find.text('Test12345'), findsOneWidget);
    // 인식 결과는 읽기 전용(입력창 없음)으로 시작한다.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('수정'), findsOneWidget);

    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();

    expect(service.calls, [('TestCafe', 'Test12345')]);
    expect(service.awaited, ['TestCafe']);
    expect(find.text('Wi-Fi에 연결되었습니다.'), findsOneWidget);
    expect(find.text('완료'), findsNothing);
    expect(find.text('수정'), findsNothing);

    final saved = await history.load();
    expect(saved.single.ssid, 'TestCafe');
    expect(saved.single.password, 'Test12345');
  });

  testWidgets('수정하기를 누르면 편집할 수 있다', (tester) async {
    await pumpResult(tester, found);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('수정'), findsNothing);
  });

  testWidgets('기록에서 열면 닫기 버튼만 있고 제목이 바뀐다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: WifiResultScreen(
        credential: found,
        historyStore: WifiHistoryStore(store: InMemoryStore()),
        title: '저장된 Wi-Fi',
        retakeLabel: null,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('저장된 Wi-Fi'), findsOneWidget);
    expect(find.text('다시 촬영'), findsNothing);
    expect(find.text('수정'), findsOneWidget);
  });

  testWidgets('연결을 확인하지 못하면 안내와 다시 시도 버튼', (tester) async {
    final service = FakeWifiService(requested, check: WifiConnectionCheck.unconfirmed);
    await pumpResult(tester, found, service: service);

    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();

    expect(find.text('아직 연결을 확인하지 못했어요.'), findsOneWidget);
    expect(find.textContaining('대소문자와 비밀번호'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('이미 저장된 네트워크면 기다리지 않고 바로 안내한다', (tester) async {
    final service = FakeWifiService(
      const WifiConnectResult(WifiConnectStatus.requested, alreadySaved: true),
      check: WifiConnectionCheck.unconfirmed,
    );
    await pumpResult(tester, found, service: service);

    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();

    expect(find.text('이미 저장된 네트워크예요.'), findsOneWidget);
    expect(find.textContaining('확인하고 있어요'), findsNothing);
    expect(service.awaited, isEmpty);
    expect(find.text('완료'), findsNothing);
    expect(find.text('수정'), findsNothing);
  });

  testWidgets('캡티브 포털이면 로그인 안내', (tester) async {
    final service = FakeWifiService(
      requested,
      check: const WifiConnectionCheck(connected: true, captivePortal: true),
    );
    await pumpResult(tester, found, service: service);

    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();

    expect(find.text('Wi-Fi에 연결되었습니다.'), findsOneWidget);
    expect(find.textContaining('브라우저 로그인'), findsOneWidget);
  });

  testWidgets('수정한 값으로 연결한다', (tester) async {
    final service = FakeWifiService(requested);
    await pumpResult(tester, found, service: service);

    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Fixed12345');
    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();

    expect(service.calls.single, ('TestCafe', 'Fixed12345'));
  });

  testWidgets('사용자가 거절하면 취소 안내와 다시 연결 버튼, 확인도 기록도 하지 않는다', (tester) async {
    final service = FakeWifiService(const WifiConnectResult(WifiConnectStatus.cancelled));
    final history = await pumpResult(tester, found, service: service);

    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();

    expect(find.text('Wi-Fi 연결이 취소되었습니다.'), findsOneWidget);
    expect(find.text('다시 연결'), findsOneWidget);
    expect(service.awaited, isEmpty);
    expect(await history.load(), isEmpty);
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

  testWidgets('값을 고치면 이전 결과 카드가 사라진다', (tester) async {
    final service = FakeWifiService(requested, check: WifiConnectionCheck.unconfirmed);
    await pumpResult(tester, found, service: service);

    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();
    expect(find.text('아직 연결을 확인하지 못했어요.'), findsOneWidget);

    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Other12345');
    await tester.pumpAndSettle();
    expect(find.text('아직 연결을 확인하지 못했어요.'), findsNothing);
    expect(find.text('Wi-Fi 연결'), findsOneWidget);
  });

  testWidgets('비밀번호만 찾으면 SSID 입력 전까지 연결 버튼 비활성화', (tester) async {
    final service = FakeWifiService(requested);
    await pumpResult(
      tester,
      const WifiCredential(password: 'hello1234', passwordConfidence: 0.9),
      service: service,
    );

    expect(find.text('Wi-Fi 이름을 찾지 못했어요'), findsOneWidget);
    // 빠진 값이 있으면 바로 편집 상태로 시작한다.
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();
    expect(service.calls, isEmpty);

    await tester.enterText(find.byType(TextField).first, 'MOMO_CAFE');
    await tester.pump();
    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();
    expect(service.calls.single, ('MOMO_CAFE', 'hello1234'));
  });

  testWidgets('공개 네트워크로 인식하면 안내하고 빈 비밀번호로 연결한다', (tester) async {
    final service = FakeWifiService(requested);
    await pumpResult(
      tester,
      const WifiCredential(ssid: 'cafe_open', password: '', ssidConfidence: 0.95, passwordConfidence: 0.9),
      service: service,
    );

    expect(find.textContaining('비밀번호가 없는 Wi-Fi로 인식'), findsOneWidget);
    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();
    expect(service.calls.single, ('cafe_open', ''));
  });

  testWidgets('8자 미만 비밀번호는 요청 전에 막는다', (tester) async {
    final service = FakeWifiService(requested);
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

    expect(find.text('Wi-Fi 정보를 찾지 못했어요'), findsOneWidget);
    expect(find.text('다시 촬영'), findsOneWidget);

    await tester.tap(find.text('직접 입력'));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi 정보를 입력해주세요'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('1순위와 점수 차가 큰 후보는 칩으로 보여주지 않는다', (tester) async {
    await pumpResult(
      tester,
      const WifiCredential(
        ssid: 'kkk_5G',
        ssidConfidence: 0.75,
        candidates: [
          WifiCandidate(value: 'kkk_5G', type: WifiCandidateType.ssid, score: 0.86),
          WifiCandidate(value: 'kkk 5G', type: WifiCandidateType.ssid, score: 0.85),
          WifiCandidate(value: '들니다', type: WifiCandidateType.ssid, score: 0.6),
        ],
      ),
    );
    expect(find.text('kkk 5G'), findsOneWidget);
    expect(find.text('들니다'), findsNothing);
  });

}
