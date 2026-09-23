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
  /// 좌표 기반 행 재구성 텍스트로 먼저 시도하고, 아무것도 못 찾으면 원문으로 다시 시도한다.
  WifiCredential fromOcrResults(List<OcrResult> results) {
    final ordered = [...results]..sort((a, b) => _priority(a, results).compareTo(_priority(b, results)));
    var credential = parser.merge([for (final r in ordered) parser.parse(r.layoutText)]);
    if (credential.isEmpty) {
      credential = parser.merge([for (final r in ordered) parser.parse(r.text)]);
    }
    final lines = [for (final r in ordered) ...r.lines];
    return withSubstitutions(credential.withUncertainIndexes(
      ssid: uncertainCharIndexes(credential.ssid ?? '', lines),
      password: uncertainCharIndexes(credential.password ?? '', lines),
    ));
  }

  /// 인식기가 자신 없어 한 글자 자리에 OCR이 자주 혼동하는 글자를 넣은 값을 후보로 덧붙인다
  /// (`0kim54796`의 첫 글자가 불확실하면 `@kim54796`, `Okim54796` …).
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
      for (final i in (indexes.toList()..sort()).take(_maxSubstitutedChars)) {
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
  WifiCredential fillMissing(WifiCredential base, WifiCredential other) {
    final extra = other.candidates
        .where((c) => c.type == WifiCandidateType.ssid ? !base.hasSsid : !base.hasPassword)
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

  static int _priority(OcrResult r, List<OcrResult> all) {
    final anyHangul = all.any((o) => o.hasHangul);
    final preferred = anyHangul ? TextRecognitionScript.korean : TextRecognitionScript.latin;
    return r.script == preferred ? 0 : 1;
  }
}
