import 'dart:convert';
import 'dart:math' as math;

import '../../../../core/utils/text_normalizer.dart';
import '../../data/models/wifi_credential.dart';

/// OCR 텍스트에서 Wi-Fi SSID / Password를 찾아내는 rule-based 파서.
///
/// 입력은 줄(`\n`) 단위 텍스트다. 같은 줄 안에서 서로 떨어진 영역은 탭(`\t`)으로
/// 구분될 수 있다 (OcrService가 좌표로 행을 재구성할 때 셀 사이에 탭을 넣는다).
///
/// 동작 순서:
/// 1. 각 셀을 라벨(`SSID`, `PW`, `와이파이` ...) 기준으로 segment로 나눈다.
/// 2. 라벨 뒤의 값 → 같은 행의 다음 셀 → 다음 행 순서로 값을 찾아 후보를 만든다.
/// 3. 라벨 없이 SSID/비밀번호처럼 생긴 값은 낮은 점수의 후보로 추가한다.
/// 4. 타입별로 가장 점수가 높은 후보를 선택한다.
///
/// 값의 대소문자와 특수문자는 절대 바꾸지 않는다. 앞뒤 공백, 라벨,
/// 공백 뒤에 붙은 괄호 설명(`12345678 (숫자 8자리)`)만 제거한다.
class WifiCredentialParser {
  const WifiCredentialParser();

  /// 이 점수 미만의 후보는 자동 선택하지 않는다.
  static const minSelectableScore = 0.4;

  WifiCredential parse(String rawText) {
    final rows = _tokenize(rawText);
    final found = <WifiCandidate>[];

    void add(_LabelMatch label, String value, double base, {required bool isolated}) {
      final cleaned = _cleanValue(value);
      if (cleaned.isEmpty) return;
      // "비밀번호 : 없음" → 공개 네트워크. 빈 비밀번호 후보로 기록한다.
      if (label.type == WifiCandidateType.password && _openKeywords.hasMatch(cleaned)) {
        found.add(WifiCandidate(value: '', type: label.type, score: (base * 0.95).clamp(0.0, 1.0)));
        return;
      }
      // "KT WIFI 5G F3D6" — 공유기 이름의 밑줄을 OCR이 공백으로 읽은 경우.
      // 밑줄로 이은 값을 1순위로 두되, 추측이므로 확신도는 낮추고 원래 값도 후보로 남긴다.
      if (label.type == WifiCandidateType.ssid && cleaned.contains(_whitespace) && _machineLikeSsid(cleaned)) {
        final joined = cleaned.replaceAll(_whitespace, '_');
        found.add(WifiCandidate(
          value: joined,
          type: label.type,
          score: (base * _ssidFactor(joined, isolated: true) * 0.9).clamp(0.0, 1.0),
        ));
        found.add(WifiCandidate(value: cleaned, type: label.type, score: (base * 0.7).clamp(0.0, 1.0)));
        return;
      }
      final factor = label.type == WifiCandidateType.ssid
          ? _ssidFactor(cleaned, isolated: isolated)
          : _passwordFactor(cleaned, isolated: isolated);
      found.add(WifiCandidate(
        value: cleaned,
        type: label.type,
        score: (base * factor).clamp(0.0, 1.0),
      ));
    }

    for (var r = 0; r < rows.length; r++) {
      final segs = rows[r];
      var i = 0;
      while (i < segs.length) {
        final seg = segs[i];
        if (!seg.isLabel || seg.consumed) {
          i++;
          continue;
        }

        // "SSID: cafe" — 라벨 뒤에 값이 바로 있는 경우
        if (seg.value.isNotEmpty) {
          add(seg.label!, seg.value, _inlineBase(seg.label!), isolated: seg.label!.hasSeparator);
          i++;
          continue;
        }

        // 값이 없는 라벨이 연속된 구간 (예: "ID / PW", "SSID\tPASSWORD")
        var j = i;
        while (j < segs.length && segs[j].isLabelOnly) {
          j++;
        }
        final run = segs.sublist(i, j);

        // "ID/PW : momo / 1234" — 라벨 여러 개가 값 하나를 나눠 쓰는 경우
        if (j < segs.length && segs[j].isLabel && _isSharedGroup([...run, segs[j]])) {
          final shared = segs[j];
          final group = [...run, shared];
          final parts = _splitInto(shared.value, group.length);
          if (parts != null) {
            for (var k = 0; k < group.length; k++) {
              add(group[k].label!, parts[k], 0.85, isolated: true);
            }
            shared.consumed = true;
            i = j + 1;
            continue;
          }
        }

        // "Wi-Fi\tcafe_momo" — 같은 행의 다음 셀에 값
        if (j < segs.length && !segs[j].isLabel && !segs[j].consumed) {
          final values = segs.sublist(j).takeWhile((s) => !s.isLabel && !s.consumed).toList();
          _assignValues(run, values, add, sameRow: true);
          i = j;
          continue;
        }

        // "WIFI\nmomo_cafe" — 다음 행에 값
        if (r + 1 < rows.length) {
          _assignFromNextRow(run, i, segs, rows[r + 1], add);
        }
        i = j;
      }
    }

    _addUnlabeledFallbacks(rows, found);
    _addSeparatorVariants(found);
    return _select(found);
  }

  /// OCR은 밑줄(`_`)과 하이픈(`-`)을 자주 놓치고 그 자리를 공백으로 읽거나, 기호 앞뒤에서
  /// 단어를 나눠 없던 공백을 만든다 (`cafe_5G` → `cafe 5G`, `Coffee!123` → `Coffee! 123`).
  /// 공백이 든 값마다 `_`, `-`, 공백 제거 후보를 함께 만들어 사용자가 고를 수 있게 한다.
  ///
  /// - SSID: 공백이 실제일 수 있으므로 원래 값을 유지한다. 단 `5G`, `2.4GHz` 같은 대역 표기
  ///   앞의 공백은 실제로 밑줄인 경우가 대부분이라 밑줄 쪽을 우선한다.
  /// - 비밀번호: 공백이 든 비밀번호는 드물지만 원래 값을 유지하고 후보만 덧붙인다.
  void _addSeparatorVariants(List<WifiCandidate> found) {
    for (final c in found.toList()) {
      if (!c.value.contains(' ') || _contactLike.hasMatch(c.value)) continue;
      final isSsid = c.type == WifiCandidateType.ssid;
      final variants = <String, double>{
        c.value.replaceAll(_spaces, '_'): isSsid && _bandSuffix.hasMatch(c.value) ? 0.01 : -0.02,
        c.value.replaceAll(_spaces, '-'): -0.03,
        if (!isSsid) c.value.replaceAll(_spaces, ''): -0.01,
      };
      for (final entry in variants.entries) {
        if (entry.key == c.value) continue;
        found.add(WifiCandidate(
          value: entry.key,
          type: c.type,
          score: (c.score + entry.value).clamp(0.0, 1.0),
        ));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 값 배정

  void _assignValues(
    List<_Segment> run,
    List<_Segment> values,
    _AddCandidate add, {
    required bool sameRow,
  }) {
    if (values.isEmpty) return;
    if (run.length == 1) {
      _addDetached(run.first, values.first, add, sameRow: sameRow);
      return;
    }
    if (values.length >= run.length) {
      for (var k = 0; k < run.length; k++) {
        _addDetached(run[k], values[k], add, sameRow: sameRow);
      }
      return;
    }
    final parts = _splitInto(values.first.value, run.length);
    if (parts == null) return;
    for (var k = 0; k < run.length; k++) {
      add(run[k].label!, parts[k], _detachedBase(run[k], sameRow: sameRow) - 0.05,
          isolated: true);
    }
    values.first.consumed = true;
  }

  /// 라벨과 떨어진 곳(다음 셀/다음 행)의 값을 후보로 추가한다.
  void _addDetached(
    _Segment label,
    _Segment value,
    _AddCandidate add, {
    required bool sameRow,
  }) {
    // "FREE WIFI" 같은 제목 다음에 오는 문장은 값으로 보지 않는다.
    if (label.header && value.value.contains(_whitespace)) return;
    add(label.label!, value.value, _detachedBase(label, sameRow: sameRow), isolated: true);
    value.consumed = true;
  }

  void _assignFromNextRow(
    List<_Segment> run,
    int runStart,
    List<_Segment> row,
    List<_Segment> next,
    _AddCandidate add,
  ) {
    // 표 형태: 헤더 행과 값 행의 셀 개수가 같으면 같은 열끼리 매칭
    if (row.length > 1 && next.length == row.length) {
      for (var k = 0; k < run.length; k++) {
        final target = next[runStart + k];
        if (target.isLabel || target.consumed) continue;
        _addDetached(run[k], target, add, sameRow: false);
      }
      return;
    }
    final leading = next.takeWhile((s) => !s.isLabel && !s.consumed).toList();
    _assignValues(run, leading, add, sameRow: false);
  }

  bool _isSharedGroup(List<_Segment> group) {
    final cell = group.first.cellIndex;
    return group.every((s) => s.cellIndex == cell) &&
        group.any((s) => s.label!.type == WifiCandidateType.ssid) &&
        group.any((s) => s.label!.type == WifiCandidateType.password);
  }

  /// `momo / 1234`, `momo|1234`, `momo 1234` 처럼 값 여러 개가 한 덩어리로 인식된 경우 분리.
  List<String>? _splitInto(String value, int count) {
    if (count < 2) return null;
    for (final sep in _valueSplitters) {
      final parts = value.split(sep).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
      if (parts.length == count) return parts;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 점수

  double _inlineBase(_LabelMatch l) {
    final strong = l.strength == _Strength.strong;
    if (l.type == WifiCandidateType.ssid) {
      return l.hasSeparator ? 0.95 : (strong ? 0.93 : 0.85);
    }
    return l.hasSeparator ? 0.97 : (strong ? 0.95 : 0.85);
  }

  double _detachedBase(_Segment seg, {required bool sameRow}) {
    final l = seg.label!;
    var base = l.type == WifiCandidateType.ssid ? 0.9 : 0.92;
    if (!sameRow) base -= 0.02;
    if (l.strength == _Strength.weak) base -= 0.1;
    // "FREE WI-FI" 같은 제목 다음 줄은 장식이나 다른 문구인 경우가 많다.
    if (seg.header) base -= 0.25;
    return base;
  }

  /// 사람이 지은 가게 이름("Lemon House")이 아니라 공유기가 만든 이름처럼 보이는지.
  /// 이미 밑줄이 섞여 있거나, 통신사·공유기 이름으로 시작하거나, 세 단어 이상에 숫자 섞인 토큰이 있다.
  bool _machineLikeSsid(String v) {
    if (v.contains('_')) return true;
    if (_ispPrefix.hasMatch(v)) return true;
    final words = v.split(_whitespace);
    return words.length >= 3 && words.where((w) => _hasDigit.hasMatch(w)).length >= 2;
  }

  double _ssidFactor(String v, {required bool isolated}) {
    var f = 1.0;
    if (utf8.encode(v).length > 32) f *= 0.3; // SSID는 최대 32바이트
    final words = v.split(_whitespace).length;
    if (words == 2) {
      f *= isolated ? 0.9 : 0.7;
    } else if (words == 3) {
      f *= isolated ? 0.7 : 0.5;
    } else if (words >= 4) {
      f *= 0.4;
    }
    if (_contactLike.hasMatch(v)) f *= 0.3;
    if (_isNoise(v)) f *= 0.2;
    return f;
  }

  double _passwordFactor(String v, {required bool isolated}) {
    var f = 1.0;
    // WPA 비밀번호는 8~63자의 ASCII 문자
    if (!_printableAscii.hasMatch(v)) f *= 0.3;
    if (v.length < 4) {
      f *= 0.3;
    } else if (v.length < 8) {
      f *= 0.7;
    }
    if (v.length > 63) f *= 0.3;
    if (v.contains(_whitespace)) f *= isolated ? 0.8 : 0.4;
    return f;
  }

  // ---------------------------------------------------------------------------
  // 라벨 없는 값

  void _addUnlabeledFallbacks(List<List<_Segment>> rows, List<WifiCandidate> found) {
    // 이름표 없이 "MomoCafe" 다음 줄에 "coffee2024!"가 오면 앞줄을 네트워크 이름으로 본다.
    // 모양만 보고 추측한 값이라 점수를 낮게 둬서 사용자가 확인하게 한다.
    for (var r = 0; r + 1 < rows.length; r++) {
      final name = _loneValue(rows[r]);
      final next = _loneValue(rows[r + 1]);
      if (name == null || next == null || _looksLikeSsid(name)) continue;
      if (_fallbackPasswordScore(next) == null || !_plausibleBareSsid(name)) continue;
      found.add(WifiCandidate(value: name, type: WifiCandidateType.ssid, score: 0.45));
    }

    for (final row in rows) {
      for (final seg in row) {
        if (seg.isLabel || seg.consumed) continue;
        final v = seg.value.trim();
        if (v.isEmpty || v.contains(_whitespace)) continue;
        if (_looksLikeSsid(v)) {
          found.add(WifiCandidate(value: v, type: WifiCandidateType.ssid, score: 0.5));
          continue;
        }
        final score = _fallbackPasswordScore(v);
        if (score != null) {
          found.add(WifiCandidate(value: v, type: WifiCandidateType.password, score: score));
        }
      }
    }
  }

  /// 행에 라벨 없는 값 하나만 있고 공백이 없으면 그 값.
  String? _loneValue(List<_Segment> row) {
    if (row.length != 1) return null;
    final seg = row.single;
    if (seg.isLabel || seg.consumed) return null;
    final v = seg.value.trim();
    return v.isEmpty || v.contains(_whitespace) ? null : v;
  }

  bool _plausibleBareSsid(String v) =>
      utf8.encode(v).length <= 32 &&
      v.length >= 2 &&
      !_digitsOnly.hasMatch(v) &&
      !_contactLike.hasMatch(v) &&
      !_noiseWords.contains(v.toLowerCase().replaceAll(_noisePunctuation, '')) &&
      !_greetingWords.contains(v.toLowerCase().replaceAll(_noisePunctuation, ''));

  bool _looksLikeSsid(String v) =>
      utf8.encode(v).length <= 32 &&
      _ssidShape.hasMatch(v) &&
      !_digitsOnly.hasMatch(v) &&
      !_contactLike.hasMatch(v);

  double? _fallbackPasswordScore(String v) {
    if (v.length < 8 || v.length > 63 || !_printableAscii.hasMatch(v)) return null;
    if (_contactLike.hasMatch(v)) return null;
    if (_digitsOnly.hasMatch(v)) return 0.4;
    if (_hasDigit.hasMatch(v) && (_hasLetter.hasMatch(v) || _hasSymbol.hasMatch(v))) return 0.5;
    return null;
  }

  // ---------------------------------------------------------------------------
  // 선택

  WifiCredential _select(List<WifiCandidate> found) {
    final best = <String, WifiCandidate>{};
    for (final c in found) {
      final key = '${c.type.name}\u0000${c.value}';
      final prev = best[key];
      if (prev == null || c.score > prev.score) best[key] = c;
    }
    final candidates = best.values.where((c) => c.score >= minSelectableScore).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final ssids = candidates.where((c) => c.type == WifiCandidateType.ssid).toList();
    final passwords = candidates.where((c) => c.type == WifiCandidateType.password).toList();
    var ssid = ssids.firstOrNull;
    var password = passwords.firstOrNull;

    // 같은 값이 SSID와 비밀번호 양쪽으로 뽑히지 않게 한다.
    if (ssid != null && password != null && ssid.value == password.value) {
      if (ssid.score >= password.score) {
        final taken = ssid.value;
        password = passwords.where((c) => c.value != taken).firstOrNull;
      } else {
        final taken = password.value;
        ssid = ssids.where((c) => c.value != taken).firstOrNull;
      }
    }

    // 공백/밑줄/하이픈 중 어느 쪽이 맞는지는 알 수 없으므로 사용자 확인을 요청한다.
    double confidence(WifiCandidate? c) {
      if (c == null) return 0;
      final stripped = c.value.replaceAll(_separators, '');
      final ambiguous = c.value.contains(' ') ||
          candidates.any((o) =>
              o.type == c.type && o.value != c.value && o.value.replaceAll(_separators, '') == stripped);
      return ambiguous ? math.min(c.score, WifiCredential.confidentThreshold - 0.05) : c.score;
    }

    return WifiCredential(
      ssid: ssid?.value,
      password: password?.value,
      ssidConfidence: confidence(ssid),
      passwordConfidence: confidence(password),
      candidates: candidates,
    );
  }

  // ---------------------------------------------------------------------------
  // 여러 인식 결과 병합

  /// 서로 다른 OCR 인식기(예: 한국어 모델과 라틴 모델)가 같은 이미지에서 낸
  /// 결과를 합친다. [sources]는 우선순위 순서로 넘긴다.
  ///
  /// - 후보는 모두 합치고 같은 값은 높은 점수를 쓴다. 다른 인식기의 값은
  ///   결과 화면에서 "다른 후보"로 고를 수 있다.
  /// - 두 인식기가 각각 확신(>= [WifiCredential.confidentThreshold])하는 값이
  ///   서로 다르면, 어느 쪽이 맞는지 알 수 없으므로 선택된 값의 신뢰도를
  ///   기준값 아래로 낮춰 사용자가 확인하도록 한다.
  WifiCredential merge(List<WifiCredential> sources) {
    if (sources.isEmpty) return WifiCredential.empty;
    if (sources.length == 1) return sources.first;

    // 앞선 source가 동점일 때 이기도록 아주 작은 가산점을 준다.
    final found = <WifiCandidate>[
      for (var i = 0; i < sources.length; i++)
        for (final c in sources[i].candidates)
          WifiCandidate(
            value: c.value,
            type: c.type,
            score: (c.score + (sources.length - 1 - i) * 1e-6).clamp(0.0, 1.0),
          ),
    ];
    final merged = _select(found);

    bool disputed(WifiCandidateType type) {
      final confident = <String>{};
      for (final s in sources) {
        final value = type == WifiCandidateType.ssid ? s.ssid : s.password;
        final score = type == WifiCandidateType.ssid ? s.ssidConfidence : s.passwordConfidence;
        if (value != null && score >= WifiCredential.confidentThreshold) confident.add(value);
      }
      return confident.length > 1;
    }

    const capped = WifiCredential.confidentThreshold - 0.05;
    return WifiCredential(
      ssid: merged.ssid,
      password: merged.password,
      ssidConfidence: disputed(WifiCandidateType.ssid)
          ? merged.ssidConfidence.clamp(0.0, capped)
          : merged.ssidConfidence,
      passwordConfidence: disputed(WifiCandidateType.password)
          ? merged.passwordConfidence.clamp(0.0, capped)
          : merged.passwordConfidence,
      candidates: merged.candidates,
    );
  }

  // ---------------------------------------------------------------------------
  // 토큰화

  List<List<_Segment>> _tokenize(String text) {
    final rows = <List<_Segment>>[];
    for (final line in text.split(_newline)) {
      final segs = <_Segment>[];
      final cells = normalizeOcrText(line).split('\t');
      for (var c = 0; c < cells.length; c++) {
        // "• Password: ..." 같은 글머리 기호는 라벨 인식을 막으므로 떼어낸다.
        final cell = cells[c].trim().replaceFirst(_bullet, '').trim().replaceFirst(_iconPrefix, '');
        // Wi-Fi·자물쇠 아이콘을 OCR이 "令", "?", "🔒" 같은 한두 글자로 읽은 셀은 버린다.
        if (cell.isEmpty || _iconOnly.hasMatch(cell)) continue;
        segs.addAll(_segmentCell(cell, c));
      }
      if (segs.isNotEmpty) rows.add(segs);
    }
    return rows;
  }

  List<_Segment> _segmentCell(String cell, int cellIndex) {
    final matches = <_LabelMatch>[];
    var pos = 0;
    while (pos < cell.length) {
      if (pos == 0 || _delimiter.hasMatch(cell[pos - 1])) {
        final m = _matchLabel(cell, pos);
        // 셀 중간의 라벨은 오탐을 줄이기 위해 강한 비밀번호 라벨이거나 구분자(:, =)가 있을 때만 인정
        if (m != null && (pos == 0 || m.hasSeparator || m.isStrongPassword)) {
          matches.add(m);
          pos = m.valueStart;
          continue;
        }
      }
      pos++;
    }

    if (matches.isEmpty) return [_Segment(null, cell, cellIndex)];

    final segs = <_Segment>[];
    // "KT_GIGA_A1B2 :: PW= ..." — 라벨 앞 값 뒤에 붙은 구분자도 뗀다.
    final prefix = cell.substring(0, matches.first.start).replaceFirst(_prefixTrailing, '');
    if (prefix.trim().isNotEmpty) segs.add(_Segment(null, prefix.trim(), cellIndex));

    for (var k = 0; k < matches.length; k++) {
      final m = matches[k];
      final end = k + 1 < matches.length ? matches[k + 1].start : cell.length;
      var value = cell.substring(m.valueStart, end).trim();
      if (k + 1 < matches.length) value = value.replaceFirst(_trailingDelimiters, '');
      // 따옴표로 감싼 값은 여러 단어여도 의도된 값이다 ('Connect to "Momo Guest"').
      final quoted = _wrappingQuotes.hasMatch(value);
      // "cafe_momo 이고" 같은 문장 종결을 먼저 떼어내야 아래 여러 단어 판정에 걸리지 않는다.
      value = _cleanValue(value);

      var header = m.header;
      if (_isNoise(value)) {
        // "FREE WIFI ZONE", "WIFI 비밀번호 안내" 같은 제목
        value = '';
        header = true;
      }
      // 약한 라벨("ID", "Network", "Key"...) 뒤에 구분자 없이 여러 단어가 오면 라벨로 보지 않는다.
      if (value.contains(_whitespace) && !m.hasSeparator && m.strength != _Strength.strong && !quoted) {
        segs.add(_Segment(null, cell.substring(m.start, end).trim(), cellIndex));
        continue;
      }
      segs.add(_Segment(m, value, cellIndex, header: header));
    }
    return segs;
  }

  _LabelMatch? _matchLabel(String cell, int pos) =>
      _tryLabel(_passwordLabel, WifiCandidateType.password, cell, pos) ??
      _tryLabel(_ssidLabel, WifiCandidateType.ssid, cell, pos);

  _LabelMatch? _tryLabel(RegExp re, WifiCandidateType type, String cell, int pos) {
    // RegExp.matchAsPrefix는 항상 RegExpMatch를 돌려준다.
    final m = re.matchAsPrefix(cell, pos) as RegExpMatch?;
    if (m == null) return null;
    final strength = m.namedGroup('strong') != null
        ? _Strength.strong
        : (m.namedGroup('weak') != null ? _Strength.weak : _Strength.medium);

    var end = m.end;
    // "Wi-Fi (5G) :", "비밀번호 (Password) :", "WIFI 1 :"
    end = _labelNote.matchAsPrefix(cell, end)?.end ?? end;
    end = _bandQualifier.matchAsPrefix(cell, end)?.end ?? end;
    // "Wi-Fi / 와이파이 :"
    final slash = _slash.matchAsPrefix(cell, end);
    if (slash != null) {
      final second = re.matchAsPrefix(cell, slash.end);
      if (second != null) end = second.end;
    }

    final sep = _separator.matchAsPrefix(cell, end);
    return _LabelMatch(
      type: type,
      strength: strength,
      header: _freePrefix.hasMatch(m[0]!),
      start: pos,
      valueStart: sep?.end ?? end,
      hasSeparator: sep != null,
    );
  }

  /// 앞뒤 공백, 괄호 설명, "비밀번호는 abc12345 입니다" 같은 문장 종결만 떼어낸다.
  /// 값 자체의 대소문자와 특수문자는 건드리지 않는다.
  String _cleanValue(String value) {
    var v = value.trim().replaceFirst(_trailingNote, '').trim();
    final stripped = v.replaceFirst(_sentenceEnding, '').trim();
    if (stripped.isNotEmpty) v = stripped;
    // 'Connect to "Momo Guest"' — 양쪽을 모두 감싼 따옴표만 벗긴다.
    final quoted = _wrappingQuotes.firstMatch(v);
    if (quoted != null) v = quoted.group(1)!;
    return v;
  }

  bool _isNoise(String value) {
    if (value.isEmpty) return false;
    return value
        .toLowerCase()
        .split(_whitespace)
        .map((w) => w.replaceAll(_noisePunctuation, ''))
        .every(_noiseWords.contains);
  }
}

typedef _AddCandidate = void Function(
  _LabelMatch label,
  String value,
  double base, {
  required bool isolated,
});

enum _Strength { strong, medium, weak }

class _LabelMatch {
  const _LabelMatch({
    required this.type,
    required this.strength,
    required this.header,
    required this.start,
    required this.valueStart,
    required this.hasSeparator,
  });

  final WifiCandidateType type;
  final _Strength strength;

  /// "FREE WIFI" 처럼 제목에 가까운 라벨.
  final bool header;
  final int start;
  final int valueStart;
  final bool hasSeparator;

  bool get isStrongPassword => type == WifiCandidateType.password && strength == _Strength.strong;
}

class _Segment {
  _Segment(this.label, this.value, this.cellIndex, {bool header = false})
      : header = header || (label?.header ?? false);

  final _LabelMatch? label;
  final String value;
  final int cellIndex;
  final bool header;

  /// 다른 라벨의 값으로 이미 사용됨.
  bool consumed = false;

  bool get isLabel => label != null;
  bool get isLabelOnly => label != null && value.isEmpty;
}

// -----------------------------------------------------------------------------
// 패턴

/// "Wi-Fi", "WIFI", "Wl-Fi" 외에 OCR이 얇은 i를 빠뜨린 "W-Fi", "Wi-F"도 허용한다.
const _wifi = r'w(?:[i1l][\s\-‐‑_.·]?|[\-‐‑_.·])f[i1l]?';
const _wifiWord = '(?:$_wifi|wlan|와이\\s?파이|무선\\s*(?:인터넷|랜)|인터넷|internet)';
const _network = '(?:network|네트\\s?워크)';
const _free = r'(?:(?:free|무료)\s*)?';

/// "비밀번호는 abc" 처럼 한글 라벨 뒤에 붙는 조사.
const _particle = r'(?:(?:는|은|이|가|를|을)(?=\s|[:=：;|]|$)|\s+is(?=\s|[:=：;|]|$))?';

/// 라벨 바로 뒤에 글자/숫자/밑줄이 붙으면 라벨이 아니다 ("WIFI_MOMO", "Keyboard").
const _boundary = r'(?![\p{L}\p{N}_]|-[\p{L}\p{N}])';

final _passwordLabel = RegExp(
  '$_free(?:(?:$_wifiWord|$_network)\\s*)?'
  '(?:(?<strong>pass\\s?w[o0]r?d|p\\s?a\\s?s\\s?s\\s?w\\s?[o0]\\s?r\\s?d|passward|passwd|passcode|pwd|p\\s?/\\s?w|p\\.w\\.?|p\\s{0,2}(?:w|vv)'
  '|비밀\\s?번호|비번|암호|패스\\s?워드)|(?<weak>pass|key))'
  '$_particle$_boundary',
  caseSensitive: false,
  unicode: true,
);

final _ssidLabel = RegExp(
  '$_free(?:'
  '(?<strong>s\\s?[s5]\\s?[i1l]\\s?d|network\\s*name|user\\s?name|네트\\s?워크\\s*(?:이름|명)'
  '|$_wifiWord\\s*(?:name|[il1]d|ssid|이름|명))'
  '|(?<medium>$_wifiWord|connect\\s+to|join|아이디)'
  '|(?<weak>$_network|[il1|][\\s.]{0,2}d|[il|]\\.?[0o]|name|이름)'
  ')$_particle$_boundary',
  caseSensitive: false,
  unicode: true,
);

final _freePrefix = RegExp(r'^(?:free|무료)', caseSensitive: false);
// OCR은 ':'를 ';'로, 표의 세로선을 '|'로 읽기도 한다.
final _separator = RegExp(r'\s*(?:[:=：;|]{1,3}>?|(?:[-–—>→➜➔⇒]|=>)(?=\s))\s*');
final _bullet = RegExp(r'^(?:[•·▪▶►☞→■□●○◆◇✔✓※★☆*]+|-(?=\s))\s*');
final _sentenceEnding = RegExp(
  r'\s*(?:입니다|이에요|예요|에요|이며|이고|이구요|이라고|이에용|입니당|임다|이야|이에요)[.!。]?$',
);
final _openKeywords = RegExp(
  r'^(?:없음|없어요|없습니다|없다|없슴|없음\.|x|-|none|no|no password|open|free|n/?a)$',
  caseSensitive: false,
);
final _labelNote = RegExp(r'\s*[(\[（][^)\]）]{0,24}[)\]）](?=\s*(?:[:=：]|$))');
final _bandQualifier = RegExp(r'\s*(?:\d(?:\.\d)?\s*g(?:hz)?|\d)(?=\s*[:=：])', caseSensitive: false);
final _slash = RegExp(r'\s*/\s*');
final _delimiter = RegExp(r'[\s/|,;·]');
final _trailingDelimiters = RegExp(r'[\s/|,;·]+$');
final _prefixTrailing = RegExp(r'[\s/|,;·:=：\-–—→]+$');
/// 'Connect to "Momo Guest"' 처럼 값 전체를 감싼 따옴표.
final _wrappingQuotes = RegExp('^["“”\'‘’「『]\\s*(.+?)\\s*["“”\'‘’」』]\$');
final _trailingNote = RegExp(r'\s+[(\[（【][^)\]）】]*[)\]）】]$');
final _valueSplitters = [RegExp(r'\s+/\s+'), RegExp(r'\s*\|\s*'), RegExp(r'\s*/\s*'), RegExp(r'\s+')];
final _whitespace = RegExp(r'\s+');
final _spaces = RegExp(r' +');
final _separators = RegExp(r'[ _-]');
final _bandSuffix = RegExp(r' \d(?:\.\d)?\s?g(?:hz)?$', caseSensitive: false);
final _newline = RegExp(r'\r?\n');
final _printableAscii = RegExp(r'^[\x20-\x7E]+$');
final _digitsOnly = RegExp(r'^\d+$');
final _hasDigit = RegExp(r'\d');
final _hasLetter = RegExp(r'[A-Za-z]');
final _hasSymbol = RegExp(r'[^A-Za-z0-9\s]');
final _ispPrefix = RegExp(r'^(?:kt|skt?|lgu?|u\+|olleh|iptime|giga|anygate|netis|tp-?link)(?=[\s_]|net|wifi|giga|$)', caseSensitive: false);
final _contactLike = RegExp(r'https?://|www\.|@\S+\.|\.(?:com|net|kr|co)\b', caseSensitive: false);
final _ssidShape = RegExp(
  r'_|^(?:iptime|kt_|sk_|u\+|olleh|lgu|giga)|[_\-]?(?:2\.4g|5g|2g)(?:hz)?$',
  caseSensitive: false,
);
final _noisePunctuation = RegExp(r'[!.,~]');

/// 줄 앞의 아이콘 자리: 영문·숫자·한글로 시작하지 않는 한두 글자 + 공백 ("令 cafe", "🔒 pw1234").
final _iconPrefix = RegExp(r'^(?![A-Za-z0-9가-힣ㄱ-ㅎ])\S{1,2}\s+(?=\S)', unicode: true);
final _iconOnly = RegExp(r'^(?![A-Za-z0-9가-힣ㄱ-ㅎ])\S{1,2}$', unicode: true);

/// 안내문 제목·인사말로 자주 쓰이는 한 단어. 이름표 없는 네트워크 이름으로 보지 않는다.
const _greetingWords = {
  'welcome', 'thanks', 'thank', 'enjoy', 'hello', 'wifi', 'wi-fi', 'password', 'cafe', 'coffee', 'menu',
  '환영합니다', '감사합니다', '안녕하세요', '어서오세요', '카페',
};
const _noiseWords = {
  'zone', 'free', 'available', 'spot', 'hotspot', 'area', 'here', 'service', 'info',
  'information', 'guide', '존', '무료', '가능', '사용가능', '이용가능', '제공', '서비스', '안내', '정보',
  // "와이파이 이용방법", "와이파이 접속 안내" 같은 제목
  '방법', '이용', '사용', '접속', '연결', '이용방법', '사용방법', '접속방법', '연결방법',
  '이용안내', '사용안내', '접속안내', '연결안내', '안내문', '운영', '운영중', '구역',
};
