import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/saved_wifi.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/wifi_history_store.dart';

class InMemoryStore implements SecureKeyValueStore {
  final map = <String, String>{};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);
}

SavedWifi entry(String ssid, {String password = 'pw12345678', int minutesAgo = 0}) => SavedWifi(
      ssid: ssid,
      password: password,
      savedAt: DateTime(2026, 9, 23, 12).subtract(Duration(minutes: minutesAgo)),
    );

void main() {
  test('저장하면 최신순으로 읽힌다', () async {
    final store = WifiHistoryStore(store: InMemoryStore());
    await store.save(entry('a', minutesAgo: 10));
    await store.save(entry('b'));
    final list = await store.load();
    expect(list.map((e) => e.ssid), ['b', 'a']);
    expect(list.first.password, 'pw12345678');
  });

  test('같은 SSID는 한 건만 남고 최신 값으로 바뀐다', () async {
    final store = WifiHistoryStore(store: InMemoryStore());
    await store.save(entry('cafe', password: 'old12345'));
    await store.save(entry('other'));
    await store.save(entry('cafe', password: 'new12345'));
    final list = await store.load();
    expect(list.map((e) => e.ssid), ['cafe', 'other']);
    expect(list.first.password, 'new12345');
  });

  test('삭제와 전체 삭제', () async {
    final memory = InMemoryStore();
    final store = WifiHistoryStore(store: memory);
    await store.save(entry('a'));
    await store.save(entry('b'));
    await store.remove('a');
    expect((await store.load()).map((e) => e.ssid), ['b']);
    await store.clear();
    expect(await store.load(), isEmpty);
    expect(memory.map, isEmpty);
  });

  test('최대 건수를 넘으면 오래된 것부터 버린다', () async {
    final store = WifiHistoryStore(store: InMemoryStore());
    for (var i = 0; i < WifiHistoryStore.maxEntries + 5; i++) {
      await store.save(entry('ssid$i', minutesAgo: 100 - i));
    }
    final list = await store.load();
    expect(list.length, WifiHistoryStore.maxEntries);
    expect(list.first.ssid, 'ssid${WifiHistoryStore.maxEntries + 4}');
  });

  test('변경되면 리스너에 알린다', () async {
    final store = WifiHistoryStore(store: InMemoryStore());
    var notified = 0;
    store.addListener(() => notified++);
    await store.save(entry('a'));
    await store.remove('a');
    await store.clear();
    expect(notified, 3);
  });

  test('저장소 내용이 깨져 있으면 빈 목록', () async {
    final memory = InMemoryStore()..map['wifi_history_v1'] = '{not json';
    final store = WifiHistoryStore(store: memory);
    expect(await store.load(), isEmpty);
  });
}
