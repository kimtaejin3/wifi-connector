import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/core/theme/app_theme.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/saved_wifi.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/wifi_credential.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/wifi_history_store.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/wifi_service.dart';
import 'package:wifi_connector/features/wifi_scanner/presentation/screens/wifi_result_screen.dart';

class FakeWifiService extends WifiService {
  FakeWifiService(this.result, {this.check = const WifiConnectionCheck(connected: true), this.laterChecks = const []});

  final WifiConnectResult result;
  final WifiConnectionCheck check;

  /// 두 번째 확인부터 차례로 돌려줄 결과. 다 쓰면 [check]를 돌려준다.
  final List<WifiConnectionCheck> laterChecks;
  final calls = <(String, String)>[];
  final replaceFlags = <bool>[];
  final retryFlags = <bool>[];
  final awaited = <String>[];

  @override
  Future<WifiConnectResult> connect({
    required String ssid,
    required String password,
    bool replaceExisting = true,
    bool retry = false,
  }) async {
    calls.add((ssid, password));
    replaceFlags.add(replaceExisting);
    retryFlags.add(retry);
    return result;
  }

  @override
  Future<WifiConnectionCheck> awaitConnection({required String ssid, Duration? timeout}) async {
    awaited.add(ssid);
    final n = awaited.length - 2;
    return n >= 0 && n < laterChecks.length ? laterChecks[n] : check;
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
  List<SavedWifi> saved = const [],
}) async {
  final history = WifiHistoryStore(store: InMemoryStore());
  for (final e in saved) {
    await history.save(e);
  }
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
    // 인식한 값은 테두리 없는 입력창에 바로 놓여 그 자리에서 고칠 수 있고, 그 사실을 글로 알려준다.
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('탭해서 수정'), findsNWidgets(2));

    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();

    expect(service.calls, [('TestCafe', 'Test12345')]);
    expect(service.awaited, ['TestCafe']);
    expect(find.text('Wi-Fi에 연결되었습니다.'), findsOneWidget);
    expect(find.text('완료'), findsNothing);
    // 연결이 끝나면 더 고칠 수 없게 잠근다.
    expect(find.text('탭해서 수정'), findsNothing);
    expect(find.byType(TextField), findsNothing);

    final saved = await history.load();
    expect(saved.single.ssid, 'TestCafe');
    expect(saved.single.password, 'Test12345');
  });

  testWidgets('입력창을 눌러 바로 고칠 수 있고, 후보 칩도 그대로 쓸 수 있다', (tester) async {
    const withCandidates = WifiCredential(
      ssid: 'TestCafe',
      password: 'Test12345',
      ssidConfidence: 0.95,
      passwordConfidence: 0.9,
      candidates: [
        WifiCandidate(value: 'Test12345', type: WifiCandidateType.password, score: 0.9),
        WifiCandidate(value: 'TestI2345', type: WifiCandidateType.password, score: 0.85),
      ],
    );
    await pumpResult(tester, withCandidates);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('후보'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Typed12345');
    await tester.pumpAndSettle();
    expect(find.text('Typed12345'), findsOneWidget);

    await tester.tap(find.text('TestI2345'));
    await tester.pumpAndSettle();
    expect(find.text('TestI2345'), findsOneWidget);
    expect(find.text('Typed12345'), findsNothing);
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
    expect(find.text('탭해서 수정'), findsNWidgets(2));
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
    expect(find.text('탭해서 수정'), findsNothing);
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

  testWidgets('OS가 원인 모를 실패를 돌려줘도 실제로 연결됐으면 연결됨으로 보여주고 기록한다', (tester) async {
    final service = FakeWifiService(const WifiConnectResult.failed(WifiConnectFailure.unknown));
    final history = await pumpResult(tester, found, service: service);

    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();

    expect(service.awaited, ['TestCafe']);
    expect(find.text('Wi-Fi에 연결되었습니다.'), findsOneWidget);
    expect(find.text('Wi-Fi에 연결하지 못했습니다.'), findsNothing);
    expect(find.text('다시 시도'), findsNothing);
    expect((await history.load()).map((e) => e.ssid), ['TestCafe']);
  });

  testWidgets('원인 모를 실패 뒤 연결도 확인되지 않으면 실패 안내', (tester) async {
    final service = FakeWifiService(
      const WifiConnectResult.failed(WifiConnectFailure.unknown),
      check: WifiConnectionCheck.unconfirmed,
    );
    final history = await pumpResult(tester, found, service: service);

    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();

    expect(service.awaited, ['TestCafe']);
    expect(find.text('Wi-Fi에 연결하지 못했습니다.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(await history.load(), isEmpty);
  });

  testWidgets('비밀번호 형식 오류는 연결될 수 없으니 확인하지 않는다', (tester) async {
    final service = FakeWifiService(const WifiConnectResult.failed(WifiConnectFailure.invalidPassword));
    await pumpResult(tester, found, service: service);

    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();

    expect(service.awaited, isEmpty);
    expect(find.text('연결할 수 없습니다.'), findsOneWidget);
  });

  group('연결할 수 없음 알림 줄이기', () {
    testWidgets('처음 연결하는 네트워크는 기존 설정 교체로 요청한다', (tester) async {
      final service = FakeWifiService(requested);
      await pumpResult(tester, found, service: service);
      await tester.tap(find.text('Wi-Fi 연결'));
      await tester.pumpAndSettle();
      expect(service.replaceFlags, [true]);
      expect(service.retryFlags, [false]);
    });

    testWidgets('기록과 비밀번호가 같으면 기존 설정을 지우지 않는다', (tester) async {
      final service = FakeWifiService(requested);
      await pumpResult(tester, found, service: service, saved: [
        SavedWifi(ssid: 'TestCafe', password: 'Test12345', savedAt: DateTime(2026, 10, 1)),
      ]);
      await tester.tap(find.text('Wi-Fi 연결'));
      await tester.pumpAndSettle();
      expect(service.replaceFlags, [false]);
    });

    testWidgets('기록과 비밀번호가 다르면 기존 설정을 교체한다', (tester) async {
      final service = FakeWifiService(requested);
      await pumpResult(tester, found, service: service, saved: [
        SavedWifi(ssid: 'TestCafe', password: 'OldPass999', savedAt: DateTime(2026, 10, 1)),
      ]);
      await tester.tap(find.text('Wi-Fi 연결'));
      await tester.pumpAndSettle();
      expect(service.replaceFlags, [true]);
    });

    testWidgets('연결을 확인하지 못한 뒤 같은 값으로 다시 시도하면 재시도로 요청한다', (tester) async {
      final service = FakeWifiService(requested, check: WifiConnectionCheck.unconfirmed);
      await pumpResult(tester, found, service: service);
      await tester.tap(find.text('Wi-Fi 연결'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(service.retryFlags, [false, true]);
      // 첫 요청에서 기록에 남았으므로 설정을 지우지 않고 그대로 다시 요청한다.
      expect(service.replaceFlags, [true, false]);
    });

    testWidgets('값을 고쳐서 다시 시도하면 재시도로 보지 않는다', (tester) async {
      final service = FakeWifiService(requested, check: WifiConnectionCheck.unconfirmed);
      await pumpResult(tester, found, service: service);
      await tester.tap(find.text('Wi-Fi 연결'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Fixed12345');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      expect(service.retryFlags, [false, false]);
    });

    testWidgets('iOS: 확인하지 못한 뒤에도 계속 지켜보다 늦게 붙으면 연결됨으로 바꾼다', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final service = FakeWifiService(
        requested,
        check: WifiConnectionCheck.unconfirmed,
        laterChecks: const [WifiConnectionCheck(connected: true)],
      );
      await pumpResult(tester, found, service: service);
      await tester.tap(find.text('Wi-Fi 연결'));
      await tester.pumpAndSettle();
      expect(service.awaited, ['TestCafe', 'TestCafe']);
      expect(find.text('Wi-Fi에 연결되었습니다.'), findsOneWidget);
      expect(find.text('다시 시도'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('iOS: 늦게도 붙지 않으면 안내와 다시 시도 버튼을 유지한다', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final service = FakeWifiService(requested, check: WifiConnectionCheck.unconfirmed);
      await pumpResult(tester, found, service: service);
      await tester.tap(find.text('Wi-Fi 연결'));
      await tester.pumpAndSettle();
      expect(find.text('아직 연결을 확인하지 못했어요.'), findsOneWidget);
      expect(find.textContaining('자동으로 연결'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Android: 확인은 한 번만 한다 (기존 동작 유지)', (tester) async {
      final service = FakeWifiService(requested, check: WifiConnectionCheck.unconfirmed);
      await pumpResult(tester, found, service: service);
      await tester.tap(find.text('Wi-Fi 연결'));
      await tester.pumpAndSettle();
      expect(service.awaited, ['TestCafe']);
    });
  });

  group('연결 실패 후 의심 글자 안내', () {
    const tricky = WifiCredential(
      ssid: 'MOMO_5G',
      password: 'coffee2O24',
      ssidConfidence: 0.95,
      passwordConfidence: 0.97,
    );

    testWidgets('연결 전과 연결 성공 뒤에는 보이지 않는다', (tester) async {
      final service = FakeWifiService(requested);
      await pumpResult(tester, tricky, service: service);
      expect(find.text('헷갈리기 쉬운 글자를 확인해 보세요'), findsNothing);
      await tester.tap(find.text('Wi-Fi 연결'));
      await tester.pumpAndSettle();
      expect(find.text('Wi-Fi에 연결되었습니다.'), findsOneWidget);
      expect(find.text('헷갈리기 쉬운 글자를 확인해 보세요'), findsNothing);
    });

    testWidgets('연결을 확인하지 못하면 바꿔 볼 글자를 설명과 함께 보여준다', (tester) async {
      final service = FakeWifiService(requested, check: WifiConnectionCheck.unconfirmed);
      await pumpResult(tester, tricky, service: service);
      await tester.tap(find.text('Wi-Fi 연결'));
      await tester.pumpAndSettle();
      expect(find.text('헷갈리기 쉬운 글자를 확인해 보세요'), findsOneWidget);
      expect(find.text('O(대문자 오) → 0(숫자 0)'), findsWidgets);
      expect(find.byKey(const ValueKey('suspect-password-7-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('suspect-ssid-1-0')), findsOneWidget);
    });

    testWidgets('후보를 누르면 그 값으로 바로 다시 연결한다', (tester) async {
      final service = FakeWifiService(requested, check: WifiConnectionCheck.unconfirmed);
      await pumpResult(tester, tricky, service: service);
      await tester.tap(find.text('Wi-Fi 연결'));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('suspect-password-7-0'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(service.calls, [('MOMO_5G', 'coffee2O24'), ('MOMO_5G', 'coffee2024')]);
      // 값이 바뀌었으므로 같은 값 재시도가 아니다.
      expect(service.retryFlags, [false, false]);
    });

    testWidgets('헷갈리는 글자가 없으면 안내를 보여주지 않는다', (tester) async {
      const plain = WifiCredential(ssid: 'cafe_mmm', password: 'abcdefgh', ssidConfidence: 0.95, passwordConfidence: 0.97);
      final service = FakeWifiService(requested, check: WifiConnectionCheck.unconfirmed);
      await pumpResult(tester, plain, service: service);
      await tester.tap(find.text('Wi-Fi 연결'));
      await tester.pumpAndSettle();
      expect(find.text('헷갈리기 쉬운 글자를 확인해 보세요'), findsNothing);
    });

    testWidgets('사용자가 거절한 경우에는 보여주지 않는다', (tester) async {
      final service = FakeWifiService(const WifiConnectResult(WifiConnectStatus.cancelled));
      await pumpResult(tester, tricky, service: service);
      await tester.tap(find.text('Wi-Fi 연결'));
      await tester.pumpAndSettle();
      expect(find.text('헷갈리기 쉬운 글자를 확인해 보세요'), findsNothing);
    });
  });

  testWidgets('값을 고치면 이전 결과 카드가 사라진다', (tester) async {
    final service = FakeWifiService(requested, check: WifiConnectionCheck.unconfirmed);
    await pumpResult(tester, found, service: service);

    await tester.tap(find.text('Wi-Fi 연결'));
    await tester.pumpAndSettle();
    expect(find.text('아직 연결을 확인하지 못했어요.'), findsOneWidget);

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
