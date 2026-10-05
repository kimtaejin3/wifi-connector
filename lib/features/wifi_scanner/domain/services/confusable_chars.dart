/// 연결에 실패했을 때 사용자에게 "이 글자가 맞는지" 확인을 권할 후보.
///
/// OCR 인식 로직과는 별개다. 이미 정해진 값에서 눈으로 구분하기 어려운 글자를
/// 한 자리씩 바꾼 값을 만든다 (l·I·1, O·0, S·5, B·8, Z·2).
class ConfusableVariant {
  const ConfusableVariant({required this.value, required this.index, required this.from, required this.to});

  /// 한 글자를 바꾼 전체 값.
  final String value;

  /// 바뀐 글자의 위치.
  final int index;
  final String from;
  final String to;

  /// "l(소문자 엘) → I(대문자 아이)"
  String get description => '${describeChar(from)} → ${describeChar(to)}';
}

/// 서로 헷갈리는 글자. 앞에 있을수록 흔한 경우.
const _confusables = <String, List<String>>{
  'l': ['I', '1'],
  'I': ['l', '1'],
  '1': ['l', 'I'],
  'O': ['0'],
  '0': ['O'],
  'o': ['0'],
  'S': ['5'],
  '5': ['S'],
  'B': ['8'],
  '8': ['B'],
  'Z': ['2'],
  '2': ['Z'],
};

/// 가장 자주 틀리는 묶음. 후보 수가 넘치면 이쪽을 먼저 보여준다.
const _primary = {'l', 'I', '1', 'O', '0', 'o'};

const _names = <String, String>{
  'l': '소문자 엘',
  'I': '대문자 아이',
  '1': '숫자 1',
  'O': '대문자 오',
  'o': '소문자 오',
  '0': '숫자 0',
  'S': '대문자 에스',
  '5': '숫자 5',
  'B': '대문자 비',
  '8': '숫자 8',
  'Z': '대문자 제트',
  '2': '숫자 2',
};

String describeChar(String ch) => _names.containsKey(ch) ? '$ch(${_names[ch]})' : ch;

/// [value]에서 헷갈리는 글자를 한 자리씩 바꾼 후보. l·I·1과 O·0을 먼저, 그다음 나머지를
/// 앞자리부터 최대 [limit]개.
List<ConfusableVariant> confusableVariants(String value, {int limit = 6}) {
  final primary = <ConfusableVariant>[];
  final secondary = <ConfusableVariant>[];
  for (var i = 0; i < value.length; i++) {
    final ch = value[i];
    final alternatives = _confusables[ch];
    if (alternatives == null) continue;
    for (final alt in alternatives) {
      (_primary.contains(ch) ? primary : secondary).add(ConfusableVariant(
        value: value.replaceRange(i, i + 1, alt),
        index: i,
        from: ch,
        to: alt,
      ));
    }
  }
  return [...primary, ...secondary].take(limit).toList();
}
