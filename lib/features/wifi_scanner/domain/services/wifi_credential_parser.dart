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
    // 일부러 남긴 장식 붙은 원래 값. 아래 장식 떼기 단계가 이 후보를 다시 떼지 않게 한다.
    final keptOriginals = Set<WifiCandidate>.identity();

    void add(_LabelMatch label, String value, double base, {required bool isolated}) {
      if (label.place) return;
      var cleaned = _cleanValue(value, label.type);
      if (cleaned.isEmpty) return;
      // 이름 앞뒤 장식을 뗐으면(F7) 뗀 값을 고르되, 장식이 진짜 이름 글자일 수도 있으니 원래 값을 낮은 후보로 남긴다.
      if (label.type == WifiCandidateType.ssid) {
        final decorated = _cleanValue(value, label.type, true);
        if (decorated != cleaned && decorated.isNotEmpty) {
          final original = WifiCandidate(
            value: decorated,
            type: label.type,
            // 뗀 값 점수의 ×0.8. 장식 기호 자체로 다시 감점하지 않는다(같은 줄 이름표 경로와 같은 점수).
            score: (base * _ssidFactor(cleaned, isolated: isolated) * _decoratedFactor).clamp(0.0, 1.0),
          );
          found.add(original);
          keptOriginals.add(original);
        }
      }
      // "d9ki88ec01 <=숫자 0" — 비밀번호 뒤에 붙은 메모는 떼고, 메모가 알려 주는 글자는 반영한다.
      if (label.type == WifiCandidateType.password) {
        // "비밀번호. 46114124M#" — 콜론을 마침표로 읽은 경우
        cleaned = cleaned.replaceFirst(_leadingDot, '');
        final note = _passwordNote.firstMatch(cleaned);
        if (note != null) {
          cleaned = note.group(1)!;
          final hinted = _applyNoteHint(cleaned, note.group(2)!);
          if (hinted != cleaned) {
            final factor = _passwordFactor(hinted, isolated: isolated);
            found.add(WifiCandidate(value: hinted, type: label.type, score: (base * factor).clamp(0.0, 1.0)));
            found.add(WifiCandidate(value: cleaned, type: label.type, score: (base * factor * 0.9).clamp(0.0, 1.0)));
            return;
          }
        }
      }
      // "비밀번호 : 없음" → 공개 네트워크. 빈 비밀번호 후보로 기록한다.
      if (label.type == WifiCandidateType.password && _openKeywords.hasMatch(cleaned)) {
        found.add(WifiCandidate(value: '', type: label.type, score: (base * 0.95).clamp(0.0, 1.0)));
        return;
      }
      // "KT WIFI 5G F3D6" — 공유기 이름의 밑줄을 OCR이 공백으로 읽은 경우.
      // 밑줄로 이은 값을 1순위로 두되, 추측이므로 확신도는 낮추고 원래 값도 후보로 남긴다.
      if (label.type == WifiCandidateType.ssid && cleaned.contains(_whitespace) && _machineLikeSsid(cleaned)) {
        final joined = cleaned.replaceAll(_whitespace, '_');
        final joinedScore = (base * _ssidFactor(joined, isolated: true) * 0.9).clamp(0.0, 1.0);
        // "SK WiFiGIGA 3A2B" — 실제 SK 이름은 접두어 바로 뒤에 16진수가 붙는다 (`SK_WiFiGIGA3A2B`).
        // 접두어 뒤 공백은 밑줄이 아니라 OCR이 넣은 틈이므로 지운 값을 1순위로 둔다.
        final tight = _skSpacedTail.firstMatch(cleaned);
        if (tight != null) {
          found.add(WifiCandidate(
            value: 'SK_WiFiGIGA${tight.namedGroup('hex')}${(tight.namedGroup('band') ?? '').replaceAll(_whitespace, '_')}',
            type: label.type,
            score: (joinedScore + 0.02).clamp(0.0, 1.0),
          ));
        }
        found.add(WifiCandidate(value: joined, type: label.type, score: joinedScore));
        found.add(WifiCandidate(value: cleaned, type: label.type, score: (base * 0.7).clamp(0.0, 1.0)));
        return;
      }
      // "a 123456789" — 안내문 비밀번호에 띄어쓰기는 거의 없다. 스티커나 넓은 자간 때문에 OCR이
      // 공백을 넣은 것으로 보이면 붙인 값을 1순위로 두고, 공백이 든 값은 후보로 남긴다.
      if (label.type == WifiCandidateType.password && _ocrGapSpaces(cleaned)) {
        final joined = cleaned.replaceAll(_whitespace, '');
        final score = (base * _passwordFactor(joined, isolated: isolated)).clamp(0.0, 1.0);
        found.add(WifiCandidate(value: joined, type: label.type, score: score));
        found.add(WifiCandidate(value: cleaned, type: label.type, score: (score - 0.05).clamp(0.0, 1.0)));
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

    // 행마다 그 행의 이름표 처리로 found에 들어간 후보 범위. 비밀번호 아래 줄의 메모(P2-4)가 쓴다.
    final rowSpans = <(int, int)>[];
    for (var r = 0; r < rows.length; r++) {
      final segs = rows[r];
      final spanStart = found.length;
      var i = 0;
      while (i < segs.length) {
        final seg = segs[i];
        if (!seg.isLabel || seg.consumed) {
          i++;
          continue;
        }

        // "SSID: cafe" — 라벨 뒤에 값이 바로 있는 경우
        if (seg.value.isNotEmpty) {
          // "PW : a ⇥ 123456789" — 비밀번호 앞부분만 이름표 칸에 붙고 나머지가 옆 칸으로 쪼개진 경우
          final rest = seg.label!.type == WifiCandidateType.password && seg.value.trim().length < 8
              ? segs
                  .sublist(i + 1)
                  .takeWhile((s) => !s.isLabel && !s.consumed && _printableAscii.hasMatch(s.value) && !s.value.contains(_whitespace))
                  .toList()
              : const <_Segment>[];
          final joined = [seg.value.trim(), ...rest.map((s) => s.value.trim())].join();
          if (rest.isNotEmpty && _printableAscii.hasMatch(seg.value) && joined.length >= 8 && joined.length <= 63) {
            add(seg.label!, [seg.value.trim(), ...rest.map((s) => s.value.trim())].join(' '), _inlineBase(seg.label!),
                isolated: seg.label!.hasSeparator);
            for (final s in rest) {
              s.consumed = true;
            }
            i += 1 + rest.length;
            continue;
          }
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

        // 비밀번호 이름표 옆이나 아래의 한글 글귀("물 마신 후")는 비밀번호일 수 없다. 옆 포스터 글자가
        // 같은 행으로 묶인 경우라 값으로 쓰지 않고, 아래 행에서 진짜 값을 찾는다.
        final passwordOnly = run.length == 1 && run.single.label!.type == WifiCandidateType.password;
        final sameRowImpossible =
            passwordOnly && j < segs.length && !segs[j].isLabel && _impossiblePassword(segs[j].value);

        // "Wi-Fi\tcafe_momo" — 같은 행의 다음 셀에 값
        if (j < segs.length && !segs[j].isLabel && !segs[j].consumed && !sameRowImpossible) {
          final values = segs.sublist(j).takeWhile((s) => !s.isLabel && !s.consumed).toList();
          // "PW : ⇥ a ⇥ 123456789" — 스티커로 덧붙인 글자처럼 비밀번호가 여러 칸으로 쪼개져 읽힌 경우.
          // 첫 칸만으로는 비밀번호가 되기에 너무 짧으면 이어지는 영문·숫자 칸을 붙인다.
          if (passwordOnly && values.length >= 2 && values.first.value.trim().length < 8) {
            final parts = values.takeWhile((s) => _printableAscii.hasMatch(s.value) && !s.value.contains(_whitespace)).toList();
            final joined = parts.map((s) => s.value.trim()).join();
            if (parts.length >= 2 && joined.length >= 8 && joined.length <= 63) {
              add(run.single.label!, parts.map((s) => s.value.trim()).join(' '), _detachedBase(run.single, sameRow: true),
                  isolated: true);
              for (final s in parts) {
                s.consumed = true;
              }
              i = j;
              continue;
            }
          }
          _assignValues(run, values, add, sameRow: true);
          i = j;
          continue;
        }

        // "WIFI\nmomo_cafe" — 다음 행에 값. 비밀번호는 한글 글귀만 있는 행을 몇 줄까지 건너뛴다.
        var next = r + 1;
        while (passwordOnly && next < rows.length && next <= r + 3 && _strayHangulRow(rows[next])) {
          next++;
        }
        if (next < rows.length) {
          _assignFromNextRow(run, i, segs, rows[next], add);
        }
        i = j;
      }
      rowSpans.add((spanStart, found.length));
    }

    _applyNoteBelow(rows, rowSpans, found);
    final wifiContext = _wifiContext.hasMatch(normalizeOcrText(rawText).replaceAll(_otherPlacePassword, ' '));
    _addUnlabeledFallbacks(rows, found, wifiContext: wifiContext);
    // 이름표 없이 고른 이름도 앞뒤 장식을 뗀다 (이름표로 고른 이름은 _cleanValue가 이미 뗐다).
    for (var k = 0, n = found.length; k < n; k++) {
      final c = found[k];
      if (c.type != WifiCandidateType.ssid || keptOriginals.contains(c)) continue;
      final plain = _withoutDecoration(c.value);
      if (plain == c.value) continue;
      found[k] = WifiCandidate(value: plain, type: c.type, score: c.score);
      // 원래 값은 뗀 값보다 낮게, 그래도 후보 목록(최소 점수 이상)에는 남게.
      final kept = math.max(c.score * _decoratedFactor, math.min(c.score - 0.01, minSelectableScore));
      found.add(WifiCandidate(value: c.value, type: c.type, score: kept));
    }
    // 이름표 바로 뒤 이름은 셀을 나눌 때 이미 장식을 뗐다. 그 값이 후보면 떼기 전 값도 ×0.8 후보로 남긴다.
    final decoratedOf = {
      for (final row in rows)
        for (final seg in row)
          if (seg.decorated != null) seg.value: seg.decorated!,
    };
    for (var k = 0, n = found.length; k < n; k++) {
      final c = found[k];
      final original = c.type == WifiCandidateType.ssid ? decoratedOf[c.value] : null;
      if (original == null) continue;
      final kept = math.max(c.score * _decoratedFactor, math.min(c.score - 0.01, minSelectableScore));
      found.add(WifiCandidate(value: original, type: c.type, score: kept));
    }
    _addSeparatorVariants(found);
    _addKtNormalized(found);
    _addSkPrefixFixes(found);
    _addKtGigaVariants(found);
    _addIspHexVariants(found);
    final result = _select(found);

    // Wi-Fi와 관계없는 글(메뉴판, 영수증, 명함, 포스터 ...)에서 엉뚱한 값을 고르지 않게 한다.
    // "Wi-Fi", "비밀번호" 같은 말도 공유기 이름도 없으면, 이름과 비밀번호 두 줄만 적힌
    // 작은 카드처럼 보일 때만 결과를 내고 나머지는 후보까지 모두 버린다.
    if (result.isEmpty || wifiContext || (result.ssid != null && _routerName.hasMatch(result.ssid!))) {
      return result;
    }
    return _cardLike(rows, result) ? result : WifiCredential.empty;
  }

  /// 이름표 없이 이름과 비밀번호만 적힌 짧은 카드 ("lunahouse7" / "b83kd02jq1").
  bool _cardLike(List<List<_Segment>> rows, WifiCredential c) {
    final ssid = c.ssid;
    final password = c.password;
    if (ssid == null || password == null || password.isEmpty) return false;
    final lines = rows.where((r) => r.any((s) => s.value.trim().isNotEmpty || s.isLabel)).length;
    if (lines > 3) return false;
    // SNS 계정("@cafe_momo")은 Wi-Fi 이름이 아니다.
    if (ssid.startsWith('@')) return false;
    // 예약·주문·쿠폰·회원·영수증 안내의 두 줄은 이름표 없는 Wi-Fi 카드가 아니다.
    // 이름·비밀번호로 고른 줄 자신은 제목으로 보지 않는다 ("code_cafe7").
    final titled = rows.any((r) {
      final first = r.first.value.trim();
      return first != ssid && first != password && _notCardTitle.hasMatch(first);
    });
    if (titled) return false;
    // 영어 단어 하나("ORANGE", "Alice")나 한글 낱말은 이름으로 보지 않는다.
    // 숫자·밑줄·하이픈이 섞였거나 "MomoCafe"처럼 단어를 붙여 쓴 이름만 받는다.
    final ssidOk = (_hasDigit.hasMatch(ssid) || ssid.contains(RegExp(r'[_\-]')) || _camelCase.hasMatch(ssid)) &&
        !_dateOrTime.hasMatch(ssid) &&
        !_licensePlate.hasMatch(ssid);
    final passwordOk = password.length >= 8 &&
        _hasDigit.hasMatch(password) &&
        (_hasLetter.hasMatch(password) || _hasSymbol.hasMatch(password)) &&
        !_dateOrTime.hasMatch(password) &&
        !_phoneLike.hasMatch(password);
    return ssidOk && passwordOk;
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

  /// 비밀번호 아래 줄의 메모 ("PW : coffee0909" / "※ 0은 모두 숫자"). 이름표 없는 한글 줄이 숫자 0·영문 O를
  /// 알려 주면 바로 위 한두 행의 비밀번호 후보에만 같은 힌트를 적용한 값을 후보로 더한다(+0.001).
  /// 메모가 비밀번호보다 위에 있거나 세 행 이상 떨어져 있으면 아무것도 하지 않는다.
  void _applyNoteBelow(List<List<_Segment>> rows, List<(int, int)> spans, List<WifiCandidate> found) {
    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty || row.any((s) => s.isLabel)) continue;
      final note = row.map((s) => s.value).join(' ');
      if (!_hangulSyllable.hasMatch(note)) continue;
      final compact = note.replaceAll(_whitespace, '').toLowerCase();
      if (!_digitZeroNote.hasMatch(compact) && !_letterONote.hasMatch(compact)) continue;
      final added = <WifiCandidate>[];
      for (var k = math.max(0, r - 2); k < r; k++) {
        final (start, end) = spans[k];
        for (var n = start; n < end; n++) {
          final c = found[n];
          if (c.type != WifiCandidateType.password || c.value.isEmpty) continue;
          final hinted = _applyNoteHint(c.value, note);
          if (hinted == c.value) continue;
          added.add(WifiCandidate(value: hinted, type: c.type, score: (c.score + 0.001).clamp(0.0, 1.0)));
        }
      }
      found.addAll(added);
    }
  }

  /// 메모가 "숫자 0"이라고 알려 주면 O·o를 0으로, "영문 O"라고 알려 주면 0을 O로 바꾼다.
  /// 안내문을 쓴 사람이 직접 적은 정보라 OCR보다 믿을 만하다.
  String _applyNoteHint(String value, String note) {
    final compact = note.replaceAll(_whitespace, '').toLowerCase();
    if (_digitZeroNote.hasMatch(compact)) return value.replaceAll(RegExp('[Oo]'), '0');
    if (_letterONote.hasMatch(compact)) return value.replaceAll('0', 'O');
    return value;
  }

  /// 비밀번호 안의 공백이 실제 띄어쓰기가 아니라 OCR이 넣은 틈으로 보이는지.
  /// 조각에 숫자가 있거나 한 글자짜리 조각이 있으면 틈으로 본다 ("a 123456789", "Coffee! 123").
  /// 글자로만 된 단어가 이어지면 실제 문구일 수 있어 그대로 둔다 ("my secret pass").
  bool _ocrGapSpaces(String value) {
    if (!value.contains(_whitespace) || !_printableAscii.hasMatch(value)) return false;
    final parts = value.split(_whitespace);
    final joined = parts.join();
    if (joined.length < 8 || joined.length > 63) return false;
    return parts.any((p) => p.length == 1 || _hasDigit.hasMatch(p));
  }

  /// 이름표 자리가 "wifi"·"와이파이"와 글자 한두 개 차이로 비슷한 낱말 (wii, wifl, 와이파, 와이).
  bool _wifiLikeLabel(String label) {
    final l = label.toLowerCase();
    return _editDistance(l, 'wifi') <= 2 || _editDistance(l, '와이파이') <= 2;
  }

  int _editDistance(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final cur = <int>[i];
      for (var j = 1; j <= b.length; j++) {
        cur.add(math.min(math.min(cur[j - 1], prev[j]) + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)));
      }
      prev = cur;
    }
    return prev.last;
  }

  /// 비밀번호가 아니라 안내 문장으로 보이는 값: 세 단어 이상이거나, `'`가 든 여러 단어.
  bool _sentenceLike(String v) {
    final words = v.trim().split(_whitespace).length;
    return words >= 3 || (words >= 2 && v.contains("'"));
  }

  /// 비밀번호로 쓸 수 없는 값. WPA 비밀번호는 ASCII라 한글이 들어가면 안내문의 다른 글귀다.
  /// "없음"처럼 공개 네트워크를 뜻하는 말은 예외.
  bool _impossiblePassword(String value) =>
      _hangulSyllable.hasMatch(value) && !_openKeywords.hasMatch(_cleanValue(value));

  /// 이름표 없이 한글 글귀로 시작하는 행 (옆 포스터의 "물컵은", "휴지통에" 같은 줄).
  bool _strayHangulRow(List<_Segment> row) =>
      row.isNotEmpty && !row.first.isLabel && _impossiblePassword(row.first.value);

  /// KT 공유기 이름은 항상 `GiGA`(가운데 i만 소문자)다 (`KT_GiGA_5G_1234`, `GiGA5G7888`).
  /// 둥근 글꼴에서는 소문자 i가 대문자 I처럼 보여 OCR이 `GIGA`(또는 `GlGA`, `G1GA`)로 읽기 쉽다. Wi-Fi 이름은
  /// 대소문자를 구분하므로 `GiGA`로 고친 값을 1순위로 두고, 읽은 그대로의 값도 후보로 남긴다.
  /// SK의 `SK_WiFiGIGA`는 원래 대문자라 건드리지 않는다.
  void _addKtGigaVariants(List<WifiCandidate> found) {
    for (final c in found.toList()) {
      if (c.type != WifiCandidateType.ssid) continue;
      final fixed = c.value.replaceAllMapped(_ktGiga, (_) => 'GiGA');
      if (fixed == c.value) continue;
      found.add(WifiCandidate(value: fixed, type: c.type, score: (c.score + 0.01).clamp(0.0, 1.0)));
    }
  }

  /// KT 공유기 이름의 실제 형식은 `KT_GiGA_<대역>_<Wave2_><16진수 네 글자>`다. OCR이 `GIGA` 뒤 밑줄을 빠뜨리거나
  /// 꼬리 1을 I로 읽은 값(`KT_GiGA5G_Wave2_4FIA`)을 실제 형식으로 고친 값을 1순위로 두고, 읽은 값도 후보로 남긴다.
  void _addKtNormalized(List<WifiCandidate> found) {
    for (final c in found.toList()) {
      if (c.type != WifiCandidateType.ssid) continue;
      final m = _ktRead.firstMatch(c.value);
      if (m == null) continue;
      final hex = m.namedGroup('hex')!.replaceAll(RegExp('[Oo]'), '0').replaceAll(RegExp('[IiLl]'), '1');
      final wave = m.namedGroup('wave') == null ? '' : 'Wave2_';
      final fixed = 'KT_GiGA_${m.namedGroup('band')!.toUpperCase()}_$wave$hex';
      if (fixed == c.value) continue;
      found.add(WifiCandidate(value: fixed, type: c.type, score: (c.score + 0.02).clamp(0.0, 1.0)));
    }
  }

  /// SK 공유기 이름의 실제 형식은 `SK_WiFiGIGA` + 16진수 네 글자(밑줄 없음) + 선택적 `_5G`/`_2.4G`다.
  /// OCR이 `WiFi`를 `WIF1`·`WlFl`로 읽거나 접두어 밑줄을 빠뜨린 값은 접두어만 `SK_WiFiGIGA`로 고친 값을
  /// 1순위로 두고, 읽은 값은 후보로 남긴다. 뒤는 읽은 그대로 두며, 16진수 꼬리는 이어지는
  /// [_addIspHexVariants]가 바로잡는다.
  void _addSkPrefixFixes(List<WifiCandidate> found) {
    final before = found.toList();
    var fixedAny = false;
    for (final c in before) {
      if (c.type != WifiCandidateType.ssid) continue;
      final m = _skRead.firstMatch(c.value);
      if (m == null) continue;
      final rest = c.value.substring(m.end);
      final fixed = 'SK_WiFiGIGA$rest';
      if (fixed == c.value) continue;
      fixedAny = true;
      // 접두어를 고친 이름은 접두어와 16진수 사이 밑줄도 지운 실제 형식(`SK_WiFiGIGA3A2B`)을 1순위로,
      // 밑줄을 읽은 그대로 둔 값은 그 아래 후보로 남긴다.
      final tight = _skUnderscoreTail.firstMatch(rest);
      final real = tight == null ? fixed : 'SK_WiFiGIGA${tight.namedGroup('hex')}${tight.namedGroup('band') ?? ''}';
      found.add(WifiCandidate(value: real, type: c.type, score: (c.score + 0.02).clamp(0.0, 1.0)));
      if (real != fixed) {
        found.add(WifiCandidate(value: fixed, type: c.type, score: (c.score + 0.01).clamp(0.0, 1.0)));
      }
    }
    // 같은 안내문에 이미 맞게 읽은 SK 이름이 있으면 같은 가산점을 줘서, 접두어를 고친 이름이 그것을 넘지 않게 한다.
    if (!fixedAny) return;
    for (final c in before) {
      if (c.type == WifiCandidateType.ssid && c.value.startsWith('SK_WiFiGIGA')) {
        found.add(WifiCandidate(value: c.value, type: c.type, score: (c.score + 0.02).clamp(0.0, 1.0)));
      }
    }
  }

  /// 통신사 공유기 이름의 꼬리 네 글자는 16진수다 (`SK_WiFiGIGA1A2B`, `KT_GiGA_5G_F3D6`, `U+NetD05C`).
  /// 16진수에는 O와 I가 없으므로 OCR이 그 자리에서 읽은 O·o는 0, I·l은 1이다. 고친 값을 1순위로
  /// 두고 읽은 그대로의 값도 후보로 남긴다.
  void _addIspHexVariants(List<WifiCandidate> found) {
    for (final c in found.toList()) {
      if (c.type != WifiCandidateType.ssid) continue;
      final m = _ispHexName.firstMatch(c.value);
      if (m == null) continue;
      final hex = m.namedGroup('hex')!;
      final fixed = hex.replaceAll(RegExp('[Oo]'), '0').replaceAll(RegExp('[Il]'), '1');
      if (fixed == hex) continue;
      final start = m.namedGroup('prefix')!.length;
      found.add(WifiCandidate(
        value: c.value.replaceRange(start, start + hex.length, fixed),
        type: c.type,
        score: (c.score + 0.01).clamp(0.0, 1.0),
      ));
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
    bool fragmentRow = false,
  }) {
    // "FREE WIFI" 같은 제목 다음에 오는 문장은 값으로 보지 않는다.
    if (label.header && value.value.contains(_whitespace)) return;
    // 값 칸에 붙어 읽힌 구분자 (":spaced_wifi")는 값이 아니다.
    final text = value.value.replaceFirst(_leadingSeparator, '');
    if (text.isEmpty) return;
    // 이름표 아래·옆 칸에 있던 안내 문장 ("Ask our staff if it doesn't work")은 비밀번호가 아니다.
    // 이름표 바로 뒤의 값은 이 함수를 지나지 않으므로 띄어쓰기 든 비밀번호 문구는 그대로다.
    if (label.label!.type == WifiCandidateType.password && _sentenceLike(text)) return;
    // 세로쓰기 이름표 조각("파")이 표 열 맞추기로 이름이 되는 것을 막는다. 값 행의 칸이 모두 한 글자
    // 조각일 때만 감점하고, 이름표가 바로 앞 칸·바로 위 행에 있는 한 글자 값("SSID\nA")은 깎지 않는다.
    final fragment = fragmentRow && label.label!.type == WifiCandidateType.ssid && text.runes.length < 2;
    add(label.label!, text, _detachedBase(label, sameRow: sameRow) * (fragment ? 0.2 : 1), isolated: true);
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
        _addDetached(run[k], target, add, sameRow: false, fragmentRow: next.every((s) => s.value.trim().runes.length < 2));
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

  void _addUnlabeledFallbacks(List<List<_Segment>> rows, List<WifiCandidate> found, {required bool wifiContext}) {
    // 이름표 없이 윗줄에 이름, 아랫줄에 비밀번호만 적힌 안내문 ("lunahouse7" / "b83kd02jq1").
    // 윗줄도 영문+숫자라 비밀번호처럼 보일 수 있으므로, 이름으로 본 값은 비밀번호 후보에서 뺀다.
    // 모양만 보고 추측한 값이라 점수를 낮게 둬서 사용자가 확인하게 한다.
    // 이름표로 이미 이름을 찾았으면 남은 줄은 이름이 아니라 비밀번호 후보로 남겨 둔다.
    final hasLabeledSsid =
        found.any((c) => c.type == WifiCandidateType.ssid && c.score >= minSelectableScore);
    final claimedAsName = <String>{};
    for (var r = 0; !hasLabeledSsid && r + 1 < rows.length; r++) {
      final name = _loneValue(rows[r]);
      final next = _loneValue(rows[r + 1]);
      if (name == null || next == null) continue;
      if (_fallbackPasswordScore(next) == null || !_plausibleBareSsid(name)) continue;
      claimedAsName.add(name);
      if (!_looksLikeSsid(name)) {
        found.add(WifiCandidate(value: name, type: WifiCandidateType.ssid, score: 0.45));
      }
      r++; // 아랫줄은 비밀번호이므로 다시 이름 후보로 보지 않는다.
    }

    // 비밀번호는 이름표로 확실히 찾았는데 이름은 못 찾았을 때, 깨진 Wi-Fi 이름표 줄("wii - hong_studio")의
    // 값을 이름 후보로 둔다. 짧은 영문·한글 낱말 + 구분자(또는 공백) + 이름 모양 값 한 칸짜리 행만 본다.
    final hasLabeledPassword =
        found.any((c) => c.type == WifiCandidateType.password && c.value.isNotEmpty && c.score >= 0.9);

    for (final row in rows) {
      for (final seg in row) {
        if (seg.isLabel || seg.consumed) continue;
        final v = seg.value.trim();
        if (v.isEmpty) continue;
        if (!hasLabeledSsid && hasLabeledPassword && row.length == 1) {
          final m = _brokenWifiLabelRow.firstMatch(v);
          final label = m?.namedGroup('label') ?? '';
          if (m != null &&
              _wifiLikeLabel(label) &&
              !_contactLabel.hasMatch(label) &&
              _looksLikeSsid(m.namedGroup('value')!)) {
            // 이름 후보만 더한다. 줄 전체를 이름으로 보는 아래 기존 추측은 그대로 이어서 돈다.
            found.add(WifiCandidate(value: m.namedGroup('value')!, type: WifiCandidateType.ssid, score: 0.55));
          }
        }
        // 이름표가 깨지거나 띄어 읽혀 알아보지 못한 줄: "비 번 : 7ba19kx719", "H| H 7ba19kx719".
        // 이름을 이미 찾았고 앞부분이 짧은 글자뿐이면 오른쪽 값을 비밀번호 후보로 둔다.
        if (hasLabeledSsid && wifiContext) {
          final m = _brokenLabelRow.firstMatch(v);
          if (m != null) {
            final label = m.namedGroup('label')!.replaceAll(_whitespace, '');
            final value = m.namedGroup('value')!;
            final score = _fallbackPasswordScore(value);
            if (score != null &&
                label.length <= 6 &&
                !_hasDigit.hasMatch(label) &&
                !_contactLabel.hasMatch(label) &&
                !found.any((c) => c.type == WifiCandidateType.ssid && c.value == value)) {
              found.add(WifiCandidate(value: value, type: WifiCandidateType.password, score: score + 0.05));
              continue;
            }
          }
        }
        if (v.contains(_whitespace)) {
          // OCR이 두 줄을 한 줄로 붙여 읽은 경우: "lunahouse7 b83kd02jq1"
          final parts = v.split(_whitespace);
          if (row.length == 1 &&
              parts.length == 2 &&
              (_hasDigit.hasMatch(parts[0]) || _looksLikeSsid(parts[0])) &&
              _plausibleBareSsid(parts[0]) &&
              _fallbackPasswordScore(parts[1]) != null) {
            found.add(WifiCandidate(value: parts[0], type: WifiCandidateType.ssid, score: 0.42));
            found.add(WifiCandidate(value: parts[1], type: WifiCandidateType.password, score: 0.42));
          }
          continue;
        }
        if (_looksLikeSsid(v)) {
          found.add(WifiCandidate(value: v, type: WifiCandidateType.ssid, score: 0.5));
          continue;
        }
        if (claimedAsName.contains(v)) continue;
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
      !_bandOnly.hasMatch(v) &&
      v.length >= 2 &&
      !_digitsOnly.hasMatch(v) &&
      !_contactLike.hasMatch(v) &&
      !_phoneLike.hasMatch(v) &&
      !_dateOrTime.hasMatch(v) &&
      !_noiseWords.contains(v.toLowerCase().replaceAll(_noisePunctuation, '')) &&
      !_greetingWords.contains(v.toLowerCase().replaceAll(_noisePunctuation, ''));

  bool _looksLikeSsid(String v) =>
      !v.startsWith('@') &&
      utf8.encode(v).length <= 32 &&
      !_bandOnly.hasMatch(v) &&
      _ssidShape.hasMatch(v) &&
      !_digitsOnly.hasMatch(v) &&
      !_contactLike.hasMatch(v);

  double? _fallbackPasswordScore(String v) {
    if (v.length < 8 || v.length > 63 || !_printableAscii.hasMatch(v)) return null;
    if (_contactLike.hasMatch(v) || _phoneLike.hasMatch(v) || _dateOrTime.hasMatch(v)) return null;
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
        var cell = cells[c].trim().replaceFirst(_bullet, '').trim().replaceFirst(_iconPrefix, '');
        // Wi-Fi·자물쇠 아이콘을 OCR이 "令", "?", "🔒" 같은 한두 글자로 읽은 셀은 버린다.
        if (cell.isEmpty || _iconOnly.hasMatch(cell)) continue;
        cell = _unbracketLabel(cell);
        // 작은 글씨의 "아이디"를 한국어 인식기가 영문처럼 깨뜨려 읽은 셀은 원래 이름표로 되돌린다.
        // 그대로 두면 위의 "WIFI" 제목이 이 글자를 Wi-Fi 이름으로 가져간다.
        if (_garbledIdLabel.hasMatch(cell)) {
          segs.addAll(_segmentCell('아이디', c));
          continue;
        }
        segs.addAll(_withoutBands(_segmentCell(cell, c)));
      }
      if (segs.isNotEmpty) rows.add(segs);
    }
    return rows;
  }

  /// "5G", "2.4G" 같은 대역 표시는 Wi-Fi 이름이 아니다 ("와이파이 이름 5G U+Net4661_5G",
  /// "무선랜 2.4G" 다음 줄에 "U+NetD05C"). 이름 앞의 대역 표시는 떼고, 대역 표시만 있는 칸은 버리고,
  /// 한 줄에 두 대역이 이어지면 ("5G U+Net4661_5G 2.4G U+Net4661") 칸을 나눈다.
  List<_Segment> _withoutBands(List<_Segment> segs) {
    final out = <_Segment>[];
    for (final seg in segs) {
      if (seg.isLabel && seg.label!.type != WifiCandidateType.ssid) {
        out.add(seg);
        continue;
      }
      final parts = _splitBands(seg.value.replaceFirst(_leadingBand, ''))
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty && !_bandOnly.hasMatch(v))
          .toList();
      if (parts.length == 1 && parts.single == seg.value) {
        out.add(seg);
        continue;
      }
      if (seg.isLabel) {
        out.add(_Segment(seg.label, parts.isEmpty ? '' : parts.first, seg.cellIndex, header: seg.header));
        out.addAll([for (final v in parts.skip(1)) _Segment(null, v, seg.cellIndex)]);
      } else {
        out.addAll([for (final v in parts) _Segment(null, v, seg.cellIndex)]);
      }
    }
    return out;
  }

  /// "U+Net1A2B_5G 2.4G U+Net1A2B"처럼 두 이름 사이에 대역 표시가 끼면 나눈다. 밑줄을 공백으로 읽은
  /// 공유기 이름("KT WIFI 5G F3D6", "iptime 5G 2F")은 나누면 안 되므로, 양쪽이 모두 완성된 이름처럼
  /// 보일 때만 나눈다 (앞쪽에 숫자가 있고, 뒤쪽이 5자 이상에 영문과 숫자가 섞임).
  List<String> _splitBands(String value) {
    final m = _innerBand.firstMatch(value);
    if (m == null) return [value];
    final left = value.substring(0, m.start);
    final right = value.substring(m.end);
    final rightName = right.split(_whitespace).first;
    if (!_hasDigit.hasMatch(left) ||
        rightName.length < 5 ||
        !_hasDigit.hasMatch(rightName) ||
        !_hasLetter.hasMatch(rightName)) {
      return [value];
    }
    return [left, ..._splitBands(right)];
  }

  /// 칸 맨 앞의 괄호 이름표 `[WIFI] x`, `【PW】 x`, `<ID> x`를 `WIFI : x`로 바꾼다.
  /// 괄호 안이 통째로 이름표일 때만 바꾼다 (`[영수증] x`는 그대로).
  String _unbracketLabel(String cell) {
    final m = _bracketLabel.firstMatch(cell);
    if (m == null) return cell;
    final inner = m.group(1)!.trim();
    if (inner.isEmpty || _matchLabel(inner, 0)?.valueStart != inner.length) return cell;
    final rest = m.group(2)!.replaceFirst(_leadingSeparator, '').trim();
    return '$inner : $rest'.trim();
  }

  List<_Segment> _segmentCell(String cell, int cellIndex) {
    final matches = <_LabelMatch>[];
    var pos = 0;
    while (pos < cell.length) {
      if (pos == 0 || _delimiter.hasMatch(cell[pos - 1])) {
        // "현관 비밀번호 :" 같은 장소 비밀번호도 이름표로 인식해 앞 값과의 경계를 만든다. 값은 버린다.
        final m = _placeLabel(cell, pos) ?? _matchLabel(cell, pos);
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
      final decorated = m.type == WifiCandidateType.ssid ? _cleanValue(value, m.type, true) : null;
      value = _cleanValue(value, m.type);

      var header = m.header;
      if (_isNoise(value)) {
        // "FREE WIFI ZONE", "WIFI 비밀번호 안내" 같은 제목
        value = '';
        header = true;
      }
      // 약한 라벨("ID", "Network", "Key"...) 뒤에 구분자 없이 여러 단어가 오면 라벨로 보지 않는다.
      // 대역 표시("무선랜 2.4G U+NetD05C")는 단어로 세지 않는다.
      final words = m.type == WifiCandidateType.ssid ? value.replaceFirst(_leadingBand, '') : value;
      if (words.contains(_whitespace) && !m.hasSeparator && m.strength != _Strength.strong && !quoted) {
        segs.add(_Segment(null, cell.substring(m.start, end).trim(), cellIndex));
        continue;
      }
      segs.add(_Segment(m, value, cellIndex, header: header,
          decorated: decorated != null && decorated != value && value.isNotEmpty ? decorated : null));
    }
    return segs;
  }

  /// 화장실·현관 등 Wi-Fi가 아닌 곳의 비밀번호 이름표. 토큰 경계에서 장소 낱말 바로 뒤에
  /// 비밀번호 이름표가 올 때만 인정한다 (다른 이름표의 값 안쪽 "화장실비밀번호연구소"는 해당 없음).
  _LabelMatch? _placeLabel(String cell, int pos) {
    // 장소 낱말이 칸 맨 앞이거나 구분자(/, |) 바로 뒤일 때만 본다. 다른 이름표의 값 안에서 만난
    // 장소 낱말("SSID: Lobby 현관 PW: x"의 현관)은 그 값의 일부다.
    if (!_placeTrigger.hasMatch(cell.substring(0, pos))) return null;
    final door = _otherPlaceWord.matchAsPrefix(cell, pos);
    if (door == null) return null;
    final at = _whitespace.matchAsPrefix(cell, door.end)?.end ?? door.end;
    final label = _passwordLabel.matchAsPrefix(cell, at) as RegExpMatch?;
    // "현관 와이파이 비밀번호"는 와이파이 비밀번호 이름표다.
    if (label == null || label.namedGroup('wifi') != null) return null;
    final inner = _tryLabel(_passwordLabel, WifiCandidateType.password, cell, at);
    if (inner == null) return null;
    return _LabelMatch(
      type: WifiCandidateType.password,
      strength: _Strength.strong,
      header: false,
      start: pos,
      valueStart: inner.valueStart,
      hasSeparator: inner.hasSeparator,
      place: true,
    );
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
      if (second != null) {
        end = second.end;
      } else {
        // "Password/PIN:" — 뒤에 구분자가 오는 짧은 낱말이 다른 이름표가 아니면 이름표의 일부다.
        // "ID/PW : a / b"의 PW처럼 다른 이름표면 따로 둬서 값을 나눠 쓰게 한다.
        final word = _slashWord.matchAsPrefix(cell, slash.end);
        if (word != null && _matchLabel(cell, slash.end) == null) end = word.end;
      }
    }

    var sep = _separator.matchAsPrefix(cell, end);
    if (sep == null) {
      final dot = _dotSeparator.matchAsPrefix(cell, end);
      if (dot != null) {
        if (_cellStart.hasMatch(cell.substring(0, pos))) {
          // 칸 맨 앞의 "ID. x", "PW. x"는 "ID : x"와 똑같이 다룬다.
          sep = dot;
        } else if (_whitespace.hasMatch(cell.substring(dot.end).split(_valueEnd).first.trim())) {
          // 문장 가운데의 "Please ask for password. Next sentence"는 이름표가 아니다.
          return null;
        }
      }
    }
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
  ///
  /// OcrService가 단어 간격이 좁은 자리에 넣은 표시 글자([gapMarker])는 여기서 없앤다:
  /// 표시 글자는 먼저 공백과 같은 부류로 보고 밑줄 옆 공백 정리와 한 규칙으로 처리한다
  /// ("Study<표시>_Room"의 표시 글자는 옆의 밑줄에 흡수된다). 정리 뒤에 남은 표시 글자만
  /// 이름이면 밑줄(OCR이 놓친 밑줄 자리), 비밀번호면 빈 문자(공백이 있을 수 없다), 종류를 모르면 공백이 된다.
  /// 앞당긴 정리는 표시 글자가 낀 매치에만 적용한다: 표시 글자가 없으면 뒤 괄호 메모 떼기가 먼저 돌아야 하므로
  /// 밑줄 옆 공백 정리는 아래 원래 자리에서 한다(`cafe_ (2층)`). 안내문에 실제로 있는 `__`도 건드리지 않는다.
  String _cleanValue(String value, [WifiCandidateType? type, bool keepDecoration = false]) {
    final gap = switch (type) { WifiCandidateType.ssid => '_', WifiCandidateType.password => '', null => ' ' };
    var v = value
        .replaceAllMapped(_spaceAroundUnderscore, (m) => m[0]!.contains(gapMarker) ? '_' : m[0]!)
        .replaceAll(gapMarker, gap).trim().replaceFirst(_trailingNote, '').trim();
    final stripped = v.replaceFirst(_sentenceEnding, '').trim();
    if (stripped.isNotEmpty) v = stripped;
    // 'Connect to "Momo Guest"' — 양쪽을 모두 감싼 따옴표만 벗긴다.
    final quoted = _wrappingQuotes.firstMatch(v);
    if (quoted != null) v = quoted.group(1)!;
    if (type == WifiCandidateType.ssid && !keepDecoration) v = _withoutDecoration(v);
    // OCR은 밑줄 옆에 없던 공백을 넣기도 한다 ("Study _Room", "one_ line_cafe"). 하이픈은 건드리지 않는다.
    return v.replaceAll(_spaceAroundUnderscore, '_');
  }

  /// 이름(SSID) 앞뒤의 장식 기호를 뗀다 ("◆ 모모양꼬치 ◆", "★cafe_momo★"). 이름에만 쓴다:
  /// 비밀번호 끝의 `~` `*` `!` `#`는 흔한 진짜 글자다. 뗀 경우에도 원래 값은 낮은 후보로 남는다(`add`).
  ///
  /// - 장식 글자([_decorationChars], 이름에 쓰지 않는 기호)는 한쪽만 있어도 뗀다. 앞쪽은 셀을 나눌 때
  ///   글머리표 규칙([_bullet])이 이미 뗐을 수 있어서 뒤쪽만 남은 "모모양꼬치•"도 장식이다.
  /// - OCR은 작은 마름모를 `.` `,`로도 읽는다. 이름 앞뒤에 `.` `,`가 하나씩 붙었으면(`.달빛꼬치,`) 둘 다 떼고,
  ///   그 밖에는 한글 바로 뒤(띄어 써도)의 뒤쪽 `.` `,`만 뗀다(`모모양꼬치.`, `모모양꼬치 .`). 한글 이름은 문장부호로
  ///   끝나지 않는다. 영문 이름 끝 `.`은 반대쪽에 다른 기호가 있어도 그대로다(`-Momo.`).
  /// - `-` `+` `*`는 이름에 진짜로 쓰인다(`모모+`, `5G-`, `-Momo-`). 양쪽에 같은 기호가 하나씩, 이름과 띄어
  ///   있을 때만 장식으로 본다(`- 모모 -`, `* 모모 *`).
  /// - 떼고 나서 아무것도 안 남으면 원래 값을 둔다.
  String _withoutDecoration(String value) {
    final strongLead = _decorationStart.firstMatch(value);
    final strongTrail = _decorationEnd.firstMatch(value);
    final lead = strongLead ?? _lookalikeStart.firstMatch(value);
    final trail = strongTrail ?? _lookalikeEnd.firstMatch(value);
    var start = 0;
    var end = value.length;
    if (lead != null && trail != null && lead.end <= trail.start) {
      final leadChar = lead[0]!.trim();
      final trailChar = trail[0]!.trim();
      final leadSpaced = lead[0]!.length > leadChar.length;
      final trailSpaced = trail[0]!.length > trailChar.length;
      bool soft(String c) => _softDecoration.contains(c);
      // 대칭은 같은 기호끼리만 본다. `.` `,`는 작은 마름모를 읽은 같은 부류로 친다(`.달빛꼬치,`).
      // `-Momo.`처럼 서로 다른 기호는 대칭이 아니다.
      final sameSoft = soft(leadChar) && soft(trailChar);
      final sameHard = leadChar == trailChar && leadSpaced && trailSpaced; // `- 모모 -`, `* 모모 *`
      if (strongLead != null || sameSoft || sameHard) start = lead.end;
      final before = value.substring(0, trail.start).trimRight();
      final afterHangul = before.isNotEmpty && _hangulSyllable.hasMatch(before[before.length - 1]);
      if (strongTrail != null || sameSoft || sameHard || (soft(trailChar) && afterHangul)) end = trail.start;
    } else if (lead != null) {
      if (strongLead != null) start = lead.end;
    } else if (trail != null) {
      final trailChar = trail[0]!.trim();
      final before = value.substring(0, trail.start).trimRight();
      final afterHangul = before.isNotEmpty && _hangulSyllable.hasMatch(before[before.length - 1]);
      if (strongTrail != null || (_softDecoration.contains(trailChar) && afterHangul)) end = trail.start;
    }
    if (start >= end) return value;
    final stripped = value.substring(start, end).trim();
    return stripped.isEmpty ? value : stripped;
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
    this.place = false,
  });

  final WifiCandidateType type;
  final _Strength strength;

  /// "FREE WIFI" 처럼 제목에 가까운 라벨.
  final bool header;
  final int start;
  final int valueStart;
  final bool hasSeparator;

  /// 화장실·현관 등 Wi-Fi가 아닌 곳의 비밀번호 이름표. 경계만 만들고 후보는 내지 않는다.
  final bool place;

  bool get isStrongPassword => type == WifiCandidateType.password && strength == _Strength.strong;
}

class _Segment {
  _Segment(this.label, this.value, this.cellIndex, {bool header = false, this.decorated})
      : header = header || (label?.header ?? false);

  final _LabelMatch? label;
  final String value;

  /// 이름표 바로 뒤 이름에서 앞뒤 장식을 뗐으면(F7) 떼기 전 값. 원래 값을 낮은 후보로 남기는 데 쓴다.
  final String? decorated;
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
const _wifiWord = '(?:$_wifi|wlan|와\\s*이\\s*파\\s*이|무선\\s*(?:인터넷|랜)|인터넷|internet)';
const _network = '(?:network|네트\\s?워크)';
const _free = r'(?:(?:free|무료)\s*)?';

/// "비밀번호는 abc" 처럼 한글 라벨 뒤에 붙는 조사.
const _particle = r'(?:(?:는|은|이|가|를|을)(?=\s|[:=：;|]|$)|\s+is(?=\s|[:=：;|]|$))?';

/// 라벨 바로 뒤에 글자/숫자/밑줄이 붙으면 라벨이 아니다 ("WIFI_MOMO", "Keyboard").
const _boundary = r'(?![\p{L}\p{N}_]|-[\p{L}\p{N}])';

final _passwordLabel = RegExp(
  '$_free(?:(?<wifi>$_wifiWord|$_network)\\s*)?'
  '(?:(?<strong>pass\\s?w[o0]r?d|p\\s?a\\s?s\\s?s\\s?w\\s?[o0]\\s?r\\s?d|passward|passwd|passcode|pwd|p\\s?/\\s?w|p\\.w\\.?|p\\s{0,2}(?:w|vv)'
  '|비[\\s|Il1]*밀[\\s|Il1]*번[\\s|Il1]*호|비\\s*번|암\\s*호(?:\\s*키)?|보\\s*안\\s*키|네트\\s?워크\\s*키|패\\s*스\\s*워\\s*드)|(?<weak>pass|key))'
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
// "WiFi ► x"의 화살표 글자도 구분자로 본다. "ID. x"의 마침표는 칸 맨 앞 이름표일 때만(_dotSeparator).
final _separator = RegExp(r'\s*(?:[:=：;|]{1,3}>?|(?:[-–—>→➜➔⇒▶►▷▸➤➢☞»›]|=>)(?=\s))\s*');
final _bracketLabel = RegExp(r'^[\[【〔<(]([^\]】〕>)]{1,24})[\]】〕>)]\s*(.*)$');
/// 칸 맨 앞 이름표 뒤 "ID. x"의 마침표. 이름표가 칸의 맨 앞(또는 번호 뒤)에 있을 때만 구분자로 쓴다.
final _dotSeparator = RegExp(r'\s*\.(?=\s)\s*');
final _cellStart = RegExp(r'^\s*(?:\d{1,2}[.)]\s*)?$');
final _valueEnd = RegExp(r'\s+/\s+|\s*\|\s*');
final _leadingSeparator = RegExp(r'^[:=：;|]+\s*');
/// 이름 앞뒤의 장식 기호 (마름모·점·네모·화살촉·별·하트·꽃·당구장 표시). 띄어 쓴 것도 함께 잡는다.
const _decorationChars = '◆◇◈❖♦♢•·∙⋅・･●◎◉■□▪▫▶◀▷◁►◄▸◂★☆✦✧✩✪✫✬✭✮✯✰♥♡❤✿❀❁✾❋※';
final _decorationStart = RegExp('^[$_decorationChars](?:\\s*[$_decorationChars])*\\s*');
final _decorationEnd = RegExp('\\s*[$_decorationChars](?:\\s*[$_decorationChars])*\$');
/// 장식을 뗀 이름이 있을 때 원래 값(장식 포함) 후보의 점수 배율.
const _decoratedFactor = 0.8;
/// OCR이 작은 마름모를 읽은 모양 중 이름 끝에 진짜로 쓰일 일이 드문 것.
const _softDecoration = {'.', ','};
/// OCR이 작은 장식을 바꿔 읽은 모양. 이름에 진짜로 있을 수도 있어 조건이 맞을 때만 뗀다.
final _lookalikeStart = RegExp(r'^[.,\-+*]\s*');
final _lookalikeEnd = RegExp(r'\s*[.,\-+*]$');
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
final _slashWord = RegExp(r'[A-Za-z가-힣]{1,8}(?=\s*[:=：;|])');
final _delimiter = RegExp(r'[\s/|,;·]');
final _trailingDelimiters = RegExp(r'[\s/|,;·]+$');
final _prefixTrailing = RegExp(r'[\s/|,;·:=：\-–—→]+$');
/// 'Connect to "Momo Guest"' 처럼 값 전체를 감싼 따옴표.
final _wrappingQuotes = RegExp('^["“”\'‘’「『]\\s*(.+?)\\s*["“”\'‘’」』]\$');
final _trailingNote = RegExp(r'\s+[(\[（【][^)\]）】]*[)\]）】]$');
final _valueSplitters = [RegExp(r'\s+/\s+'), RegExp(r'\s*\|\s*'), RegExp(r'\s*/\s*'), RegExp(r'\s+')];
final _whitespace = RegExp(r'\s+');
final _spaces = RegExp(r' +');
/// 밑줄 옆의 공백과 단어 간격 표시 글자([gapMarker])를 함께 잡는다.
final _spaceAroundUnderscore = RegExp('[\\s$gapMarker]*_[\\s$gapMarker]*');
final _separators = RegExp(r'[ _-]');
/// 대역 표시만 있는 값, 값 앞의 대역 표시, 값 가운데의 다음 대역 표시.
/// 값 앞의 대역 표시에는 "5G 전용 :", "2.4G전용 :"처럼 짧은 한글 말과 구분자가 붙기도 하고,
/// 작은 글씨의 "전용"을 OCR이 "8" 같은 숫자로 깨뜨려 읽기도 한다 ("5G 8 : SK_WiFi...").
final _bandOnly = RegExp(r'^(?:2\.4|2|5|6)\s?g(?:hz)?$', caseSensitive: false);
final _leadingBand = RegExp(
  r'^(?:2\.4|2|5|6)\s?g(?:hz)?(?:\s*(?:[가-힣]{1,4}|\d{1,2}))?\s*[:：=]?\s+(?=\S)',
  caseSensitive: false,
);
final _innerBand = RegExp(r'\s+(?:2\.4|2|5|6)\s?g(?:hz)?\s*[:：]?\s+(?=\S)', caseSensitive: false);
/// 비밀번호 앞에 붙은 마침표·쉼표 (뒤에 8자 이상이 있을 때만).
final _leadingDot = RegExp(r'^[.,·]\s*(?=\S{8})');
final _bandSuffix = RegExp(r' \d(?:\.\d)?\s?g(?:hz)?$', caseSensitive: false);
final _newline = RegExp(r'\r?\n');
final _printableAscii = RegExp(r'^[\x20-\x7E]+$');
final _digitsOnly = RegExp(r'^\d+$');
final _hasDigit = RegExp(r'\d');
final _hasLetter = RegExp(r'[A-Za-z]');
final _hasSymbol = RegExp(r'[^A-Za-z0-9\s]');
/// 02-1234-5678, 010.1234.5678, +82-10-1234-5678 같은 전화번호 모양.
final _phoneLike = RegExp(r'^\+?\d[\d().]*[-.)][\d\-.()]*\d$');
final _ispPrefix = RegExp(r'^(?:kt|skt?|lgu?|u\+|olleh|iptime|giga|anygate|netis|tp-?link)(?=[\s_]|net|wifi|giga|$)', caseSensitive: false);
/// Wi-Fi가 아닌 곳의 비밀번호 앞말: 화장실, 현관, 도어락, 출입문, 대문, 주차장, 사물함, 보관함, 택배함, 금고(+문).
const _otherPlace = r'(?:화장실|현관|도어락|출입문|대문|주차장|사물함|보관함|택배함|금고)(?:\s*문)?';
/// 장소 비밀번호 이름표가 올 수 있는 자리: 칸 맨 앞, 또는 `/`·`|`·`,` 바로 뒤.
final _placeTrigger = RegExp(r'(?:^|[/|,])\s*$');
const _otherPlaceStart = r'(?<![\p{L}\p{N}_])(?:공동\s?)?';
final _otherPlaceWord = RegExp('$_otherPlaceStart$_otherPlace', unicode: true);
/// Wi-Fi 단서를 셀 때 뺄 장소 비밀번호 이름표 (토큰 경계에서만: "SSID: 화장실비밀번호연구소"는 해당 없음).
final _otherPlacePassword = RegExp(
  r'(?<=^|\t|[/|,]\s*)(?:공동\s?)?'
  '$_otherPlace\\s*(?:비[\\s|Il1]*밀[\\s|Il1]*번[\\s|Il1]*호|비\\s*번|암\\s*호|패\\s*스\\s*워\\s*드|pass\\s?w[o0]r?d|passcode|pwd|pw)(?![\\p{L}\\p{N}_])',
  caseSensitive: false,
  unicode: true,
  multiLine: true,
);
/// 글 어딘가에 Wi-Fi 안내문이라는 단서가 있는지. "ID", "Name", "Key" 같은 일반 이름표는 단서로 치지 않는다.
final _wifiContext = RegExp(
  '(?<![a-z])(?:$_wifi|wlan|s\\s?[s5]\\s?[i1l]\\s?d)'
  '|와\\s*이\\s*파\\s*이|무선\\s*(?:인터넷|랜)|네트\\s?워크\\s*(?:이름|명)|network\\s*name'
  '|(?<![a-z])(?:pass\\s?w[o0]r?d|passward|passwd|passcode|pwd|p\\s{0,2}/?\\s{0,2}(?:w|vv))(?![a-z])'
  '|비\\s*밀\\s*번\\s*호|비\\s*번|암\\s*호|보\\s*안\\s*키|네트\\s?워크\\s*키|패\\s*스\\s*워\\s*드',
  caseSensitive: false,
  unicode: true,
);
/// 통신사·공유기가 붙인 이름 ("iptime_5G", "KT_GiGA_2G_1234", "U+Net1A2B").
final _routerName = RegExp(
  r'^(?:kt|skt?|lgu?|u\+|olleh|iptime|giga|anygate|netis|tp-?link)(?=[\s_\-]|net|wifi|giga|$)|[_\-](?:2\.4|2|5)g(?:hz)?$',
  caseSensitive: false,
);
/// KT 공유기 이름의 `GiGA` 자리. 맨 앞이나 `_`, `KT`, `olleh` 뒤에 오고 뒤에는 구분자·숫자·끝이 온다.
final _ktGiga = RegExp(r'(?<=^|[_\s\-]|kt|olleh)g[il1|]ga(?=[_\s\-]|\d|wifi|$)', caseSensitive: false);
/// OCR이 읽은 KT 공유기 이름: `KT_GiGA_<대역>_<Wave2_><16진수>`에서 밑줄·글자가 틀어진 모양.
final _ktRead = RegExp(
  r'^KT_?G[il1|]GA_?(?<band>2G|5G)_?(?<wave>Wave2_?)?(?<hex>[0-9A-FOIL]{4})$',
  caseSensitive: false,
);
/// OCR이 읽은 SK 공유기 이름의 접두어 (`SK_WIF1GIGA`, `SKWiFiGIGA`, `SK_WlFlGlGA`).
final _skRead = RegExp(r'^SK_?W[il1|]F[il1|]G[il1|]GA', caseSensitive: false);
/// 접두어 뒤의 `_` + 16진수 네 글자 + 선택적 대역 꼬리.
final _skUnderscoreTail = RegExp(r'^_(?<hex>[0-9A-FOoIl]{4})(?<band>_(?:2\.4|2|5)G)?$', caseSensitive: false);
/// 접두어와 16진수 사이를 공백으로 읽은 SK 이름 ("SK WiFiGIGA 3A2B", "SK WIF1GIGA 3A2B 5G").
final _skSpacedTail = RegExp(
  r'^SK[_\s]?W[il1|]F[il1|]G[il1|]GA\s+(?<hex>[0-9A-FOoIl]{4})(?<band>\s+(?:2\.4|2|5)G)?$',
  caseSensitive: false,
);
/// 통신사 공유기 이름: 접두어 + 16진수 네 글자(OCR 혼동 글자 O·o·I·l 포함) + 선택적 대역 꼬리.
final _ispHexName = RegExp(
  r'^(?<prefix>sk_wifigiga|kt_g[il1|]ga_(?:(?:2\.4|2|5)g_)?(?:wave2_)?|u\+net)(?<hex>[0-9A-FOoIl]{4})(?:_(?:2\.4|2|5)g)?$',
  caseSensitive: false,
);
final _hangulSyllable = RegExp(r'[가-힣]');
/// 비밀번호 뒤의 메모. 공백 뒤 화살표로 시작하거나(`<=숫자 0`, `← zero`), 한글 설명이 오는 경우
/// (`숫자 0`). 비밀번호에는 한글이 들어갈 수 없고, 공백 뒤 화살표가 비밀번호일 일도 없다.
final _passwordNote = RegExp(r'^([^\s가-힣]+)\s+((?:<=|<-+|←|⇐|⟸|=>|->)\s*.*|[^\s]*[가-힣].*)$');
/// "숫자0", "숫자 영", "zero", "<=0(숫자)".
final _digitZeroNote = RegExp(r'숫자(?:0|영|제로)|(?:0|영)(?:은|는)?(?:모두|전부|다)?숫자|zero|number0|digit0');
/// "영문 O", "알파벳 O", "대문자 O".
final _letterONote = RegExp(r'(?:영문|알파벳|대문자|영어)(?:o|오)|(?:o|오)(?:은|는)?(?:영문|알파벳|대문자)');
/// 작은 글씨의 "아이디"를 한국어 인식기가 깨뜨려 읽은 모양. 실기기에서 OFOII, OFOITI, OFOICA,
/// OFOICI, OF0IC, OHOI, OFO1TA 등으로 읽혔다 (ㅇ→O, ㅏ→F/H, 이→OI, 디→C/T/I/A).
/// 셀 전체가 이 모양일 때만 쓴다. "OFFICE" 같은 실제 이름은 셋째 글자가 O가 아니라 해당하지 않는다.
final _garbledIdLabel = RegExp(r'^[O0][FHE][O0][Il1|][CTIAl1|]{0,2}$');
/// 날짜·시각 (20261007, 2026-10-07, 10:00, 09:00~22:00).
final _dateOrTime = RegExp(
  r'^(?:(?:19|20)\d{2}[-./]?\d{2}[-./]?\d{2}|\d{1,2}:\d{2}(?:\s*[~\-–]\s*\d{1,2}:\d{2})?)$',
);
/// 이름표 없는 카드 위나 아래에 이 낱말로 시작하는 줄이 있으면 Wi-Fi 안내가 아닌 글이다.
final _notCardTitle = RegExp(
  r'^(?:reservation|예약|order|주문|coupon|쿠폰|code|member(?:ship)?|회원|follow(?:\s+us)?|팔로우|ticket|티켓|receipt|영수증)',
  caseSensitive: false,
);
/// 단어를 붙여 쓴 이름 (MomoCafe, iPhone).
final _camelCase = RegExp(r'[a-z][A-Z]');
/// 자동차 번호판 (123가4567).
final _licensePlate = RegExp(r'^\d{2,3}\s?[가-힣]\s?\d{4}$');
/// 알아보지 못한 짧은 이름표 + (구분자 또는 공백) + 값 하나.
final _brokenLabelRow = RegExp(r'^(?<label>[^\s:=：;|][^:=：;|]{0,11}?)\s*(?:[:=：;|]{1,3}|\s)\s*(?<value>\S+)$');
/// 알아보지 못한 Wi-Fi 이름표 줄: 짧은 영문·한글 낱말(2~6자) + 구분자 또는 공백 + 값 하나 ("wii - hong_studio").
/// 구분자 앞뒤에 공백이 있어야 한다: 공백 없는 `TP-Link_5E2A`, `momo.cafe_5G`는 줄 전체가 이름이다.
final _brokenWifiLabelRow = RegExp(r'^(?<label>[A-Za-z가-힣]{2,6})\s+[:=：;|.\-–—]{1,3}\s+(?<value>\S+)$');
/// 연락처·영업 정보 줄의 이름표. 이 뒤의 값은 비밀번호로 보지 않는다.
final _contactLabel = RegExp(
  r'tel|phone|call|fax|mobile|hp|open|close|전화|문의|연락|주소|영업|시간|휴무|예약|계좌|사업자',
  caseSensitive: false,
);
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
