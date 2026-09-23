import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/saved_wifi.dart';

/// 키-값 보안 저장소. 실제 구현은 Android Keystore / iOS Keychain을 쓰는
/// [FlutterSecureStorage]이고, 테스트에서는 메모리 구현으로 바꾼다.
abstract class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class KeychainKeyValueStore implements SecureKeyValueStore {
  const KeychainKeyValueStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// 인식해서 연결한 Wi-Fi 목록. 최신순, SSID당 한 건, 최대 [maxEntries]건.
///
/// 목록 전체를 JSON 한 덩어리로 Keychain/Keystore에 넣는다. 평문 파일이나
/// SharedPreferences에는 절대 쓰지 않는다.
class WifiHistoryStore extends ChangeNotifier {
  WifiHistoryStore({SecureKeyValueStore? store}) : _store = store ?? const KeychainKeyValueStore();

  static const maxEntries = 50;
  static const _key = 'wifi_history_v1';

  final SecureKeyValueStore _store;

  Future<List<SavedWifi>> load() async {
    try {
      final raw = await _store.read(_key);
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List<dynamic>;
      return [for (final e in list) SavedWifi.fromJson((e as Map).cast<String, Object?>())];
    } on Exception {
      // 저장소를 못 읽으면(기기 잠금 등) 빈 목록으로 다룬다.
      return const [];
    }
  }

  Future<void> save(SavedWifi entry) async {
    final current = await load();
    final updated = [entry, ...current.where((e) => e.ssid != entry.ssid)].take(maxEntries).toList();
    await _write(updated);
  }

  Future<void> remove(String ssid) async {
    final current = await load();
    await _write(current.where((e) => e.ssid != ssid).toList());
  }

  Future<void> clear() async {
    try {
      await _store.delete(_key);
    } on Exception {
      // 이미 없음
    }
    notifyListeners();
  }

  Future<void> _write(List<SavedWifi> entries) async {
    try {
      await _store.write(_key, jsonEncode([for (final e in entries) e.toJson()]));
    } on Exception {
      // 저장 실패는 조용히 넘긴다. 기록은 편의 기능이지 연결에 필요하지 않다.
    }
    notifyListeners();
  }
}

/// 앱 전체에서 공유하는 기록 저장소.
final wifiHistoryStore = WifiHistoryStore();
