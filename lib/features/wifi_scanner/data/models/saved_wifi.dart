/// 인식 기록 한 건. 비밀번호가 들어 있으므로 OS Keychain/Keystore에만 저장한다.
class SavedWifi {
  const SavedWifi({required this.ssid, required this.password, required this.savedAt});

  factory SavedWifi.fromJson(Map<String, Object?> json) => SavedWifi(
        ssid: json['ssid'] as String? ?? '',
        password: json['password'] as String? ?? '',
        savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  final String ssid;
  final String password;
  final DateTime savedAt;

  bool get isOpen => password.isEmpty;

  Map<String, Object?> toJson() => {
        'ssid': ssid,
        'password': password,
        'savedAt': savedAt.toIso8601String(),
      };

  // 비밀번호가 로그에 찍히지 않도록 한다.
  @override
  String toString() => 'SavedWifi($ssid, ${isOpen ? 'open' : '********'}, $savedAt)';
}
