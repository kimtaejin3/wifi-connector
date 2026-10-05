import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/confusable_chars.dart';

void main() {
  test('O와 0을 서로 바꾼 후보', () {
    final v = confusableVariants('coffee2O24');
    expect(v.map((e) => e.value), contains('coffee2024'));
    final swap = v.firstWhere((e) => e.value == 'coffee2024');
    expect(swap.index, 7);
    expect(swap.description, 'O(대문자 오) → 0(숫자 0)');
  });

  test('l·I·1은 서로 두 가지씩', () {
    final values = confusableVariants('WIFl').map((e) => e.value).toList();
    expect(values, containsAll(['WlFl', 'W1Fl', 'WIFI', 'WIF1']));
  });

  test('l·I·1과 O·0을 다른 글자보다 먼저 보여준다', () {
    final v = confusableVariants('S5B8Z2_l', limit: 3);
    expect(v.map((e) => e.from).toList(), ['l', 'l', 'S']);
  });

  test('개수 제한', () {
    expect(confusableVariants('1111111111', limit: 6).length, 6);
  });

  test('헷갈리는 글자가 없으면 빈 목록', () {
    expect(confusableVariants('cafe_mmm'), isEmpty);
    expect(confusableVariants(''), isEmpty);
  });

  test('값 전체에서 한 글자만 바뀐다', () {
    for (final e in confusableVariants('KT_GIGA_5G_O1l')) {
      expect(e.value.length, 'KT_GIGA_5G_O1l'.length);
      var diff = 0;
      for (var i = 0; i < e.value.length; i++) {
        if (e.value[i] != 'KT_GIGA_5G_O1l'[i]) diff++;
      }
      expect(diff, 1);
    }
  });
}
