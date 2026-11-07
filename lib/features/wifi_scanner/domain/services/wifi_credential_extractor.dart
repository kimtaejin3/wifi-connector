import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../data/models/wifi_credential.dart';
import '../../data/services/ocr_service.dart';
import 'wifi_credential_parser.dart';

/// 여러 인식기의 OCR 결과를 파서에 넘겨 하나의 [WifiCredential]로 만든다.
class WifiCredentialExtractor {
  const WifiCredentialExtractor({this.parser = const WifiCredentialParser()});

  final WifiCredentialParser parser;

  /// 한글이 보이면 한국어 인식기 결과를, 아니면 라틴 인식기 결과를 우선한다.
  /// [preferred]를 주면 이 사진의 한글 여부 대신 그 인식기를 우선한다 (실시간 인식에서
  /// 프레임마다 우선 인식기가 바뀌어 결과가 왔다 갔다 하지 않게 하려고).
  ///
  /// 좌표 기반 행 재구성 텍스트로 먼저 시도하고, 아무것도 못 찾았거나 이름·비밀번호 중
  /// 하나만 찾았으면 원문으로 다시 읽어 빠진 쪽을 채운다.
  WifiCredential fromOcrResults(List<OcrResult> results, {TextRecognitionScript? preferred}) {
    final first = preferred ?? preferredScript(results);
    final ordered = [...results]..sort((a, b) => (a.script == first ? 0 : 1).compareTo(b.script == first ? 0 : 1));
    var credential = parser.merge([for (final r in ordered) parser.parse(r.layoutText)]);
    if (!credential.hasSsid || !credential.hasPassword) {
      final raw = parser.merge([for (final r in ordered) parser.parse(r.text)]);
      credential = credential.isEmpty ? raw : fillMissing(credential, raw);
    }
    final lines = [for (final r in ordered) ...r.lines];
    final password = credential.password ?? '';
    return withSubstitutions(credential.withUncertainIndexes(
      ssid: uncertainCharIndexes(credential.ssid ?? '', lines),
      password: {
        ...uncertainCharIndexes(password, lines),
        if (_endsWithTildeLookalike(password)) password.length - 1,
      },
    ));
  }

  /// 비밀번호 끝의 `-`는 안내문의 `~`를 OCR이 잘못 읽은 것일 때가 많다 (굵은 글씨의 물결표는 가운데가
  /// 납작해져 하이픈처럼 보인다). 반대로 `-`를 `~`로 읽는 일은 드물다. 그래서 끝의 `-`는 신뢰도가 없는
  /// iOS 결과에서도 불확실한 글자로 보고 `~` 후보를 둔다. 값 자체는 바꾸지 않는다. 가운데 `-`는 건드리지 않는다.
  static bool _endsWithTildeLookalike(String password) => password.length > 1 && password.endsWith('-');

  /// 인식기가 자신 없어 한 글자 자리에 OCR이 자주 혼동하는 글자를 넣은 값을 후보로 덧붙인다
  /// (`0cat54796`의 첫 글자가 불확실하면 `@cat54796`, `Ocat54796` …).
  /// 원래 값은 그대로 두고, 해당 항목은 "확인 필요"가 뜨도록 신뢰도를 낮춘다.
  @visibleForTesting
  WifiCredential withSubstitutions(WifiCredential credential) {
    final extra = <WifiCandidate>[];
    var ssidConfidence = credential.ssidConfidence;
    var passwordConfidence = credential.passwordConfidence;
    const capped = WifiCredential.confidentThreshold - 0.05;

    void expand(String? value, Set<int> indexes, WifiCandidateType type) {
      if (value == null || indexes.isEmpty) return;
      final top = credential.candidatesOf(type).firstOrNull?.score ?? 0;
      var rank = 0;
      final sorted = indexes.toList()..sort();
      final chosen = {
        ...sorted.take(_maxSubstitutedChars),
        // 비밀번호 끝 `-`(물결표를 읽은 모양)는 앞에 불확실한 글자가 많아도 빠뜨리지 않는다.
        if (type == WifiCandidateType.password && _endsWithTildeLookalike(value) && indexes.contains(value.length - 1))
          value.length - 1,
      };
      for (final i in chosen) {
        final ch = value[i];
        final alternatives = [
          // 비밀번호 첫 글자의 0/O/o/a는 @일 때가 많다.
          if (type == WifiCandidateType.password && i == 0 && '0Ooa'.contains(ch)) '@',
          ...?_confusions[ch],
        ];
        for (final alt in alternatives.toSet()) {
          if (alt == ch) continue;
          extra.add(WifiCandidate(
            value: value.replaceRange(i, i + 1, alt),
            type: type,
            score: (top - 0.02 - 0.001 * rank++).clamp(0.0, 1.0),
          ));
        }
      }
      if (type == WifiCandidateType.ssid) {
        ssidConfidence = math.min(ssidConfidence, capped);
      } else {
        passwordConfidence = math.min(passwordConfidence, capped);
      }
    }

    expand(credential.ssid, credential.ssidUncertainIndexes, WifiCandidateType.ssid);
    expand(credential.password, credential.passwordUncertainIndexes, WifiCandidateType.password);
    if (extra.isEmpty && ssidConfidence == credential.ssidConfidence &&
        passwordConfidence == credential.passwordConfidence) {
      return credential;
    }

    final existing = {for (final c in credential.candidates) '${c.type.name}\u0000${c.value}'};
    final candidates = [
      ...credential.candidates,
      ...extra.where((c) => existing.add('${c.type.name}\u0000${c.value}')),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return credential.copyWith(
      ssidConfidence: ssidConfidence,
      passwordConfidence: passwordConfidence,
      candidates: candidates,
    );
  }

  /// 알파벳 O와 숫자 0은 안내문 글꼴에서 거의 똑같아 OCR이 확신하고도 틀린다.
  /// 선택된 이름·비밀번호의 O·0·o 자리를 서로 바꾼 값을 후보로 덧붙인다.
  /// 선택된 값과 확신도는 바꾸지 않고, 결과 화면의 "후보" 칩에만 보이게 한다.
  WifiCredential withLookalikes(WifiCredential credential) {
    final extra = <WifiCandidate>[];

    void expand(String? value, WifiCandidateType type) {
      if (value == null || value.isEmpty) return;
      final positions = [
        for (var i = 0; i < value.length; i++)
          if (_lookalikes.containsKey(value[i])) i,
      ];
      if (positions.isEmpty) return;
      final top = credential.candidatesOf(type).firstOrNull?.score ?? 0;
      var rank = 0;
      void add(String v) => extra.add(WifiCandidate(
            value: v,
            type: type,
            score: (top - 0.01 - 0.001 * rank++).clamp(0.0, 1.0),
          ));
      // 한 자리씩 바꾼 값 (앞에서부터 몇 자리만)
      for (final i in positions.take(_maxLookalikePositions)) {
        add(value.replaceRange(i, i + 1, _lookalikes[value[i]]!));
      }
      // 여러 자리면 모두 바꾼 값도 (0000 ↔ OOOO)
      if (positions.length > 1) {
        final all = StringBuffer();
        for (var i = 0; i < value.length; i++) {
          all.write(_lookalikes[value[i]] ?? value[i]);
        }
        add(all.toString());
      }
    }

    expand(credential.ssid, WifiCandidateType.ssid);
    expand(credential.password, WifiCandidateType.password);
    final tilde = _tildeSwapped(credential.password);
    if (extra.isEmpty && tilde == null) return credential;

    final existing = {for (final c in credential.candidates) '${c.type.name}\u0000${c.value}'};
    final candidates = [
      // 비밀번호 끝 `~` ↔ `-`: 어느 쪽으로 뽑혔든 다른 쪽을 바로 다음 후보로 둔다. 셔터 한 장의 불확실 글자
      // 후보로 이미 있으면 점수만 올린다 (결과 화면 칩은 세 개까지라 O·0 후보에 밀리지 않게).
      for (final c in credential.candidates)
        if (tilde != null && c.type == WifiCandidateType.password && c.value == tilde)
          _tildeCandidate(credential, tilde, c)
        else
          c,
      if (tilde != null && existing.add('${WifiCandidateType.password.name}\u0000$tilde'))
        _tildeCandidate(credential, tilde, null),
      ...extra.where((c) => existing.add('${c.type.name}\u0000${c.value}')),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return credential.copyWith(candidates: candidates);
  }

  /// 비밀번호 끝 글자만 `~` ↔ `-`로 바꾼 값. 끝이 둘 다 아니면 null. 가운데 글자는 건드리지 않는다.
  /// OCR이 굵은 글씨의 끝 물결표를 하이픈으로 자주 읽어서다 ([_endsWithTildeLookalike]).
  static String? _tildeSwapped(String? password) {
    if (password == null || password.length < 2) return null;
    final other = switch (password[password.length - 1]) {
      '-' => '~',
      '~' => '-',
      _ => null,
    };
    return other == null ? null : password.replaceRange(password.length - 1, null, other);
  }

  static WifiCandidate _tildeCandidate(WifiCredential credential, String value, WifiCandidate? existing) {
    final top = credential.candidatesOf(WifiCandidateType.password).firstOrNull?.score ?? 0;
    final score = (top - 0.005).clamp(0.0, 1.0);
    return WifiCandidate(
      value: value,
      type: WifiCandidateType.password,
      score: existing == null ? score : math.max(existing.score, score),
    );
  }

  static const _maxLookalikePositions = 4;

  /// 대문자 O ↔ 숫자 0, 소문자 o → 숫자 0.
  static const _lookalikes = {'O': '0', '0': 'O', 'o': '0'};

  /// 불확실한 글자가 많으면 조합이 폭발하므로 앞에서부터 이만큼만 후보를 만든다.
  static const _maxSubstitutedChars = 2;

  /// OCR이 서로 바꿔 읽기 쉬운 글자. 앞에 있을수록 흔한 경우.
  static const _confusions = <String, List<String>>{
    '0': ['@', 'O', 'o'],
    'O': ['0', '@', 'Q'],
    'o': ['0', 'a', 'O'],
    'a': ['@', 'o', 'e'],
    '1': ['l', 'I', '!', '|'],
    'l': ['1', 'I', '!', '|'],
    'I': ['l', '1', '!', '|'],
    '|': ['l', '1', '!', 'I'],
    '!': ['1', 'l', 'I', '|'],
    '5': ['S', '\$'],
    'S': ['5', '\$'],
    '\$': ['S', '5'],
    '8': ['B', '&'],
    'B': ['8', '&'],
    '&': ['8', 'B'],
    '2': ['Z', '?'],
    'Z': ['2', '7'],
    '6': ['b', 'G'],
    'b': ['6', 'h'],
    'G': ['6', 'C'],
    '9': ['g', 'q'],
    'g': ['9', 'q'],
    'q': ['9', 'g'],
    'C': ['G', 'c'],
    'c': ['e', 'C'],
    'e': ['c', 'a'],
    'H': ['#'],
    '#': ['H'],
    '*': ['x'],
    'x': ['*', 'X'],
    '~': ['-'],
    '-': ['~', '_'],
    '_': ['-'],
    '.': [','],
    ',': ['.'],
  };

  /// [base]에서 못 찾은 항목만 [other]의 후보로 채운다. 이미 찾은 항목은 건드리지 않는다.
  /// 가이드 밖(전체 사진)의 인식 결과가 안에서 찾은 값을 뒤집거나 잡음을 섞지 않게 하기 위해서다.
  /// [minScore]보다 낮은 후보(이름표 없이 모양만 보고 추측한 값)는 쓰지 않을 수 있다.
  WifiCredential fillMissing(WifiCredential base, WifiCredential other, {double minScore = 0}) {
    final extra = other.candidates
        .where((c) => c.type == WifiCandidateType.ssid ? !base.hasSsid : !base.hasPassword)
        .where((c) => c.score >= minScore)
        .toList();
    if (extra.isEmpty) return base;
    final merged = parser.merge([
      base,
      WifiCredential(
        ssid: base.hasSsid ? null : other.ssid,
        password: base.hasPassword ? null : other.password,
        ssidConfidence: base.hasSsid ? 0 : other.ssidConfidence,
        passwordConfidence: base.hasPassword ? 0 : other.passwordConfidence,
        candidates: extra,
      ),
    ]);
    return merged.withUncertainIndexes(
      ssid: base.hasSsid ? base.ssidUncertainIndexes : other.ssidUncertainIndexes,
      password: base.hasPassword ? base.passwordUncertainIndexes : other.passwordUncertainIndexes,
    );
  }

  /// 이 사진 한 장만 보고 정한 우선 인식기. 한글이 보이면 한국어, 아니면 라틴.
  static TextRecognitionScript preferredScript(List<OcrResult> results) =>
      results.any((r) => r.hasHangul) ? TextRecognitionScript.korean : TextRecognitionScript.latin;
}

/// 실시간 인식에서 우선할 인식기를 최근 여러 프레임을 보고 정한다.
///
/// 두 인식기가 같은 점수로 다른 글자를 읽으면 우선 인식기의 값이 뽑힌다. 프레임마다 한글이
/// 한 글자라도 보였는지로 정하면 "비밀번호" 이름표가 읽힌 프레임과 안 읽힌 프레임에서 서로 다른
/// 인식기의 값이 번갈아 뽑혀 다수결이 갈린다. 그래서 최근 프레임의 다수로 정하고 쉽게 바꾸지 않는다.
class ScriptPreference {
  ScriptPreference({this.window = 8});

  final int window;
  final List<bool> _hangul = [];
  TextRecognitionScript? _current;

  TextRecognitionScript update(List<OcrResult> results) {
    final sawHangul = results.any((r) => r.hasHangul);
    _hangul.add(sawHangul);
    while (_hangul.length > window) {
      _hangul.removeAt(0);
    }
    final ratio = _hangul.where((h) => h).length / _hangul.length;
    final current = _current;
    if (current == null) {
      _current = sawHangul ? TextRecognitionScript.korean : TextRecognitionScript.latin;
    } else if (current == TextRecognitionScript.latin && ratio >= 0.6) {
      _current = TextRecognitionScript.korean;
    } else if (current == TextRecognitionScript.korean && ratio <= 0.3) {
      _current = TextRecognitionScript.latin;
    }
    return _current!;
  }

  void clear() {
    _hangul.clear();
    _current = null;
  }
}
