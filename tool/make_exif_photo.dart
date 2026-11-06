// 똑바로 선 안내문 이미지를, 휴대폰 카메라가 저장하듯 "픽셀은 돌아간 채 + EXIF 회전 표시"인 JPEG로 만든다.
//
//   dart run tool/make_exif_photo.dart <입력.png> <출력.jpg> [EXIF Orientation: 6|8|3, 기본 6]
//
// - 6: 휴대폰을 세로로 들고 찍은 사진. 픽셀은 반시계로 90° 누워 있고, 보는 쪽이 시계 방향으로 돌려 보여 준다.
// - 8: 반대쪽으로 세로로 든 사진. 3: 거꾸로 든 사진.
// 사진 뷰어·UIImage는 EXIF를 적용해 똑바로 보여 주므로 눈으로는 원본과 같다. ML Kit 좌표가 어느 쪽
// 기준으로 나오는지(그리고 layoutRows가 행을 제대로 묶는지)를 재현하는 fixture를 만들 때 쓴다.
// tool/render_signs.sh가 부른다. 입력은 지어낸 안내문 이미지만 쓴다.
import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  if (args.length < 2 || args.length > 3) {
    stderr.writeln('사용법: dart run tool/make_exif_photo.dart <입력.png> <출력.jpg> [6|8|3]');
    exit(64);
  }
  final orientation = args.length == 3 ? int.tryParse(args[2]) : 6;
  // 보여 줄 때 돌리는 방향의 반대로 픽셀을 돌려 저장한다 (copyRotate는 시계 방향).
  const storedRotation = {6: 270, 8: 90, 3: 180};
  final rotation = storedRotation[orientation];
  if (rotation == null) {
    stderr.writeln('EXIF Orientation은 6, 8, 3 중 하나여야 해요: ${args[2]}');
    exit(64);
  }

  final upright = img.decodeImage(File(args[0]).readAsBytesSync());
  if (upright == null) {
    stderr.writeln('이미지를 읽지 못했어요: ${args[0]}');
    exit(65);
  }
  final stored = img.copyRotate(upright, angle: rotation);
  stored.exif.imageIfd.orientation = orientation;
  final bytes = img.encodeJpg(stored, quality: 92);

  // 되읽어서 확인한다: 파일의 EXIF 회전 값이 그대로 있고, EXIF를 적용해 읽으면(decodeJpg는 회전을
  // 적용해서 돌려준다) 원본 크기로 돌아와야 한다.
  final readOrientation = img.decodeJpgExif(bytes)?.imageIfd.orientation;
  final shown = img.decodeJpg(bytes);
  if (readOrientation != orientation ||
      shown == null ||
      shown.width != upright.width ||
      shown.height != upright.height) {
    stderr.writeln('EXIF 회전 사진을 만들지 못했어요: ${args[1]}');
    exit(70);
  }
  File(args[1]).writeAsBytesSync(bytes);
  stdout.writeln('${args[1]}: 저장 픽셀 ${stored.width}x${stored.height}, EXIF Orientation $orientation '
      '(보이는 크기 ${upright.width}x${upright.height})');
}
