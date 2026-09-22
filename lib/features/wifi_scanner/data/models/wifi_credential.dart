import '../../../../core/utils/secret_mask.dart';

enum WifiCandidateType { ssid, password }

/// 파서가 OCR 텍스트에서 뽑아낸 SSID / Password 후보 하나.
class WifiCandidate {
  const WifiCandidate({
    required this.value,
    required this.type,
    required this.score,
  });

  final String value;
  final WifiCandidateType type;

  /// 0.0 ~ 1.0. 라벨 위치와 값의 형태로 계산한 신뢰도.
  final double score;

  @override
  String toString() {
    final shown = type == WifiCandidateType.password ? maskSecret(value) : value;
    return 'WifiCandidate(${type.name}: $shown, ${score.toStringAsFixed(2)})';
  }
}

/// 파싱 결과. 각 필드는 가장 점수가 높은 후보로 채워진다.
class WifiCredential {
  const WifiCredential({
    this.ssid,
    this.password,
    this.ssidConfidence = 0,
    this.passwordConfidence = 0,
    this.candidates = const [],
  });

  static const empty = WifiCredential();

  /// 이 값 이상이면 사용자가 확인 없이 연결해도 될 만큼 신뢰할 수 있다고 본다.
  /// V2에서 이보다 낮으면 AI Parser fallback을 붙일 자리.
  static const confidentThreshold = 0.8;

  final String? ssid;
  final String? password;
  final double ssidConfidence;
  final double passwordConfidence;

  /// 점수 내림차순 정렬된 전체 후보.
  final List<WifiCandidate> candidates;

  bool get hasSsid => ssid != null;
  bool get hasPassword => password != null;
  bool get isEmpty => !hasSsid && !hasPassword;

  /// 안내문에 "비밀번호 없음"처럼 적혀 있어 공개 네트워크로 인식한 경우.
  bool get isOpenNetwork => password == '';

  List<WifiCandidate> candidatesOf(WifiCandidateType type) =>
      candidates.where((c) => c.type == type).toList();

  // 비밀번호가 로그/크래시 리포트에 그대로 찍히지 않도록 마스킹한다.
  @override
  String toString() =>
      'WifiCredential(ssid: $ssid (${ssidConfidence.toStringAsFixed(2)}), '
      'password: ${maskSecret(password)} (${passwordConfidence.toStringAsFixed(2)}))';
}
