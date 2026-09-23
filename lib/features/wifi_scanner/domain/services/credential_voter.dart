import 'dart:math' as math;

import '../../data/models/wifi_credential.dart';

/// 한 항목(SSID 또는 비밀번호)의 투표 결과.
class VotedField {
  const VotedField({
    required this.value,
    required this.support,
    required this.agreement,
    required this.uncertainIndexes,
  });

  final String value;

  /// 이 값의 길이로 읽힌 판독의 가중치 합 (몇 장이 기여했는지).
  final int support;

  /// 글자 위치별 다수결 비율 중 최솟값. 1.0이면 모든 판독이 완전히 일치.
  final double agreement;

  /// 다수결 비율이 낮은 글자 위치.
  final Set<int> uncertainIndexes;

  bool get isStable => support >= CredentialVoter.minSupport && agreement >= CredentialVoter.minAgreement;
}

class VoteResult {
  const VoteResult({this.ssid, this.password});

  final VotedField? ssid;
  final VotedField? password;

  /// 셔터 없이 결과를 보여줘도 될 만큼 두 항목 모두 여러 프레임에서 일치함.
  bool get isStable => (ssid?.isStable ?? false) && (password?.isStable ?? false);
}

/// 연속된 프레임의 인식 결과를 모아 글자 단위 다수결로 값을 정한다.
///
/// 한 장의 OCR은 `@`를 `0`으로 읽는 식으로 프레임마다 흔들리지만, 같은 안내문을 여러 번
/// 읽으면 틀린 글자는 프레임마다 달라지고 맞는 글자는 반복된다. 길이가 같은 판독끼리
/// 위치별로 가장 많이 나온 글자를 고르면 한 프레임짜리 오류가 대부분 사라진다.
class CredentialVoter {
  CredentialVoter({this.window = 8});

  /// 최근 몇 개의 판독만 기억할지.
  final int window;

  /// 안정으로 보기 위한 최소 기여 프레임 수와 위치별 최소 일치 비율.
  static const minSupport = 3;
  static const minAgreement = 0.6;

  /// 이 비율 미만으로 일치한 글자는 결과 화면에서 강조한다.
  static const uncertainBelow = 0.75;

  final List<_Reading> _readings = [];

  int get count => _readings.length;

  void add(WifiCredential credential, {int weight = 1}) {
    if (credential.isEmpty) return;
    _readings.add(_Reading(credential, weight));
    while (_readings.length > window) {
      _readings.removeAt(0);
    }
  }

  void clear() => _readings.clear();

  VoteResult vote() => _vote(_readings);

  /// 셔터로 찍은 사진의 결과([still])를 그동안의 실시간 판독과 합친다.
  /// 사진은 해상도가 높고 가이드 영역만 잘라 인식하므로 두 표를 준다.
  WifiCredential combine(WifiCredential still, {int stillWeight = 2}) {
    if (_readings.isEmpty) return still;
    final result = _vote([..._readings, _Reading(still, stillWeight)]);
    return toCredential(result, sources: [for (final r in _readings) r.credential, still], base: still);
  }

  /// 투표 결과를 결과 화면에 넘길 [WifiCredential]로 만든다.
  /// 후보 목록은 [sources]의 후보를 합치고, 뽑힌 값은 맨 위에 둔다.
  WifiCredential toCredential(VoteResult result, {required List<WifiCredential> sources, WifiCredential? base}) {
    final best = <String, WifiCandidate>{};
    for (final s in sources) {
      for (final c in s.candidates) {
        final key = '${c.type.name}\u0000${c.value}';
        if ((best[key]?.score ?? -1) < c.score) best[key] = c;
      }
    }

    String? value(VotedField? field, String? fallback) => field?.value ?? fallback;
    final ssid = value(result.ssid, base?.ssid);
    final password = value(result.password, base?.password);

    void promote(String? v, WifiCandidateType type, VotedField? field) {
      if (v == null) return;
      final key = '${type.name}\u0000$v';
      final score = field == null ? (best[key]?.score ?? 0.9) : (field.agreement >= uncertainBelow ? 0.98 : 0.9);
      best[key] = WifiCandidate(value: v, type: type, score: math.max(score, best[key]?.score ?? 0));
    }

    promote(ssid, WifiCandidateType.ssid, result.ssid);
    promote(password, WifiCandidateType.password, result.password);
    final candidates = best.values.toList()..sort((a, b) => b.score.compareTo(a.score));

    double confidence(VotedField? field, double fallback) {
      if (field == null) return fallback;
      return field.agreement >= uncertainBelow ? math.max(fallback, 0.95) : math.min(fallback, WifiCredential.confidentThreshold - 0.05);
    }

    Set<int> uncertain(VotedField? field, String? baseValue, Set<int> baseIndexes) {
      if (field == null) return baseIndexes;
      return field.value == baseValue ? {...baseIndexes, ...field.uncertainIndexes} : field.uncertainIndexes;
    }

    return WifiCredential(
      ssid: ssid,
      password: password,
      ssidConfidence: confidence(result.ssid, base?.ssidConfidence ?? 0),
      passwordConfidence: confidence(result.password, base?.passwordConfidence ?? 0),
      candidates: candidates,
      ssidUncertainIndexes: uncertain(result.ssid, base?.ssid, base?.ssidUncertainIndexes ?? const {}),
      passwordUncertainIndexes:
          uncertain(result.password, base?.password, base?.passwordUncertainIndexes ?? const {}),
    );
  }

  static VoteResult _vote(List<_Reading> readings) => VoteResult(
        ssid: voteValues([
          for (final r in readings)
            if (r.credential.ssid != null) (r.credential.ssid!, r.weight),
        ]),
        password: voteValues([
          for (final r in readings)
            if (r.credential.password != null) (r.credential.password!, r.weight),
        ]),
      );

  /// 가장 흔한 길이의 판독끼리 글자 위치별 다수결.
  static VotedField? voteValues(List<(String, int)> readings) {
    if (readings.isEmpty) return null;

    final weightByLength = <int, int>{};
    for (final (value, weight) in readings) {
      weightByLength.update(value.length, (w) => w + weight, ifAbsent: () => weight);
    }
    final length = weightByLength.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    final group = readings.where((r) => r.$1.length == length).toList();
    final support = weightByLength[length]!;

    final buffer = StringBuffer();
    var agreement = 1.0;
    final uncertain = <int>{};
    for (var i = 0; i < length; i++) {
      final weights = <String, int>{};
      for (final (value, weight) in group) {
        weights.update(value[i], (w) => w + weight, ifAbsent: () => weight);
      }
      final top = weights.entries.reduce((a, b) => b.value > a.value ? b : a);
      buffer.write(top.key);
      final ratio = top.value / support;
      agreement = math.min(agreement, ratio);
      if (ratio < uncertainBelow) uncertain.add(i);
    }

    return VotedField(
      value: buffer.toString(),
      support: support,
      agreement: agreement,
      uncertainIndexes: uncertain,
    );
  }
}

class _Reading {
  const _Reading(this.credential, this.weight);

  final WifiCredential credential;
  final int weight;
}
