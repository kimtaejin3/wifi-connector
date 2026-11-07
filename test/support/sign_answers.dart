// test_signs 안내문의 정답표. 값은 아래 answers.md를 그대로 옮겼다 (모두 지어낸 값).
//   test_signs/variety/answers.md   → varietyAnswers
//   test_signs/variants/answers.md  → variantAnswers
//   test_signs/answers.md           → singleSignAnswers, photoAnswers
// test/ocr_fixture_test.dart가 이 표와 answers.md가 같은지 확인한다.

/// 안내문 하나의 정답.
class SignAnswer {
  const SignAnswer.wifi(this.name, this.form, {required this.ssids, required this.password}) : isWifi = true;

  const SignAnswer.notWifi(this.name, this.form)
      : isWifi = false,
        ssids = const [],
        password = null;

  /// fixture 이름 (`test/fixtures/ocr/<name>.json`).
  final String name;

  /// 안내문 형태 (answers.md의 "형태" 칸).
  final String form;

  /// Wi-Fi 안내문인지. 아니면 이름도 비밀번호도 내면 안 된다.
  final bool isWifi;

  /// 맞는 이름. 여러 개면 아무거나 맞으면 된다 ("A 또는 B").
  final List<String> ssids;

  /// 맞는 비밀번호. `''`는 공개 네트워크(`(공개)`), null은 안내문에 비밀번호가 없어서 결과에도 없어야 함(`(안 적힘)`).
  final String? password;

  /// 같은 안내문을 다른 방식으로 저장한 사진(EXIF 회전 사진)의 정답.
  SignAnswer asPhoto(String photoName, String photoForm) => isWifi
      ? SignAnswer.wifi(photoName, photoForm, ssids: ssids, password: password)
      : SignAnswer.notWifi(photoName, photoForm);
}

const varietyAnswers = <SignAnswer>[
  SignAnswer.wifi('variety-01', '기본 콜론', ssids: ['cafe_momo'], password: 'momo12345'),
  SignAnswer.wifi('variety-02', '자간 넓은 "비 번"', ssids: ['GiGA5G4021'], password: '3kd82mz550'),
  SignAnswer.wifi('variety-03', '콜론 없음', ssids: ['cafe_luna'], password: 'luna2025'),
  SignAnswer.wifi('variety-04', '한글 이름표', ssids: ['모모카페'], password: 'momo2024!'),
  SignAnswer.wifi('variety-05', 'SSID / PASSWORD', ssids: ['Bakery_Guest'], password: 'bread0909'),
  SignAnswer.wifi('variety-06', 'ID / PW 표', ssids: ['Study_Room'], password: 'study4321'),
  SignAnswer.wifi('variety-07', '이름표 없는 두 줄', ssids: ['lunahouse7'], password: 'b83kd02jq1'),
  SignAnswer.wifi('variety-08', '공유기 라벨 (U+)', ssids: ['U+NetA7C2', 'U+NetA7C2_5G'], password: 'F3AC118842'),
  SignAnswer.wifi('variety-09', '통신사 공유기 이름', ssids: ['KT_GiGA_5G_Wave2_4F1A'], password: 'k9x2m4p8q1'),
  SignAnswer.wifi('variety-10', '문장형', ssids: ['Sunny_Cafe'], password: 'sunny2024'),
  SignAnswer.wifi('variety-11', '아이콘만 (글자 이름표 없음)', ssids: ['Momo_Guest'], password: 'guest4321'),
  SignAnswer.wifi('variety-12', '제목·영업시간·전화번호 섞임', ssids: ['bread_house'], password: 'bread0909'),
  SignAnswer.wifi('variety-13', '2.4G / 5G 두 이름', ssids: ['home_net', 'home_net_5G'], password: 'homenet77'),
  SignAnswer.wifi('variety-14', '손글씨체', ssids: ['dalgona'], password: 'dal12345'),
  SignAnswer.wifi('variety-15', '특수문자 비밀번호', ssids: ['tea_time'], password: 'Tea@2024!'),
  SignAnswer.wifi('variety-16', 'O와 0이 섞임', ssids: ['OCEAN_0O'], password: 'O0o0Ocean'),
  SignAnswer.notWifi('variety-17', '메뉴판'),
  SignAnswer.notWifi('variety-18', '영수증'),
  SignAnswer.notWifi('variety-19', '명함'),
  SignAnswer.notWifi('variety-20', '영업 안내'),
  SignAnswer.notWifi('variety-21', '영어 할인 포스터'),
  SignAnswer.notWifi('variety-22', '제품 라벨'),
  SignAnswer.notWifi('variety-23', '예약 안내 (영문+숫자 두 줄)'),
  SignAnswer.notWifi('variety-24', '주문 번호'),
];

const variantAnswers = <SignAnswer>[
  SignAnswer.wifi('variants-01', '얇은 글꼴', ssids: ['Lumi_Cafe'], password: 'lumi7788'),
  SignAnswer.wifi('variants-02', '명조체', ssids: ['sodam_books'], password: 'books1004'),
  SignAnswer.wifi('variants-03', '아주 굵게·좁은 자간, 이름표 위·값 아래', ssids: ['HANA_COFFEE'], password: 'hana0303'),
  SignAnswer.wifi('variants-04', '값의 자간이 넓음', ssids: ['cozy_home'], password: 'cozy2026'),
  SignAnswer.wifi('variants-05', '둥근 글꼴 기울임', ssids: ['Peach_Garden'], password: 'peach5959'),
  SignAnswer.wifi('variants-06', '칠판 손글씨', ssids: ['chalk_cafe'], password: 'chalk1234'),
  SignAnswer.wifi('variants-07', '포스트잇 마커, 살짝 기울임', ssids: ['hong_studio'], password: 'hong0812'),
  SignAnswer.wifi('variants-08', '한글 이름표 + 손글씨 값', ssids: ['dream_house'], password: 'dream2580'),
  SignAnswer.wifi('variants-09', '세로쓰기 이름표', ssids: ['maru_guest'], password: 'maru4949'),
  SignAnswer.wifi('variants-10', '작은 이름표 위에 아주 큰 값', ssids: ['Bloom_Flower'], password: 'bloom2024!!'),
  SignAnswer.wifi('variants-11', '기울어지게 찍힌 안내문', ssids: ['tilt_cafe'], password: 'tilt5678'),
  SignAnswer.wifi('variants-12', '표: 헤더 행 + 값 행', ssids: ['grid_cafe'], password: 'grid1357'),
  SignAnswer.wifi('variants-13', '표: 대역별 두 이름', ssids: ['duo_net', 'duo_net_5G'], password: 'duo24680'),
  SignAnswer.wifi('variants-14', '이모지 아이콘만', ssids: ['Sunrise_Inn'], password: 'sunrise2026'),
  SignAnswer.wifi('variants-15', '와이파이명 / 패스워드', ssids: ['nabi_hostel'], password: 'nabi0505'),
  SignAnswer.wifi('variants-16', '네트워크 / 암호', ssids: ['SEOUL_LOFT'], password: 'loft3030'),
  SignAnswer.wifi('variants-17', 'ID. / PW. (마침표 구분)', ssids: ['orange_box'], password: 'orange8282'),
  SignAnswer.wifi('variants-18', '▶ 기호 구분', ssids: ['star_lounge'], password: 'star7979'),
  SignAnswer.wifi('variants-19', '한 줄에 모두', ssids: ['one_line_cafe'], password: 'oneline2468'),
  SignAnswer.wifi('variants-20', '이름표 자간이 넓음', ssids: ['spaced_wifi'], password: 'spaced2468'),
  SignAnswer.wifi('variants-21', 'KT 공유기 스티커 (관리자 암호·MAC 함께)',
      ssids: ['KT_GiGA_2G_7A3F', 'KT_GiGA_5G_7A3F'], password: '3f8kd02pa7'),
  SignAnswer.wifi('variants-22', 'SK 공유기 스티커',
      ssids: ['SK_WiFiGIGA9B2E', 'SK_WiFiGIGA9B2E_5G'], password: 'B7DE1@4410'),
  SignAnswer.wifi('variants-23', 'LG U+ 공유기 스티커 (표, 웹관리 암호 함께)',
      ssids: ['U+Net9F3C', 'U+Net9F3C_5G'], password: '9F3CA4E8D1'),
  SignAnswer.wifi('variants-24', 'ipTIME 공유기 라벨', ssids: ['iptime_A1C9'], password: '87420631'),
  SignAnswer.wifi('variants-25', '영문 공유기 라벨', ssids: ['TP-Link_5E2A'], password: '51837264'),
  SignAnswer.wifi('variants-26', '두 대역을 한 줄에', ssids: ['mint_house', 'mint_house_5G'], password: 'mint9090'),
  SignAnswer.wifi('variants-27', '아래 줄 메모 "0은 숫자"', ssids: ['zero_cafe'], password: 'c0ffee0909'),
  SignAnswer.wifi('variants-28', '같은 줄 메모 "← 0은 숫자" (영문 O도 섞임)', ssids: ['loop_cafe'], password: 'LOOP0909'),
  SignAnswer.wifi('variants-29', '특수문자 비밀번호', ssids: ['symbol_bar'], password: 'm@cha#2026!'),
  SignAnswer.wifi('variants-30', '마침표·밑줄 든 비밀번호, 하이픈 이름', ssids: ['dot-cafe'], password: 'grape.juice_77'),
  SignAnswer.wifi('variants-31', 'O/0, I/l/1 혼동', ssids: ['HILL_TOP_10'], password: 'l1Il0Oo2026'),
  SignAnswer.wifi('variants-32', '긴 비밀번호가 다음 줄로 넘어감', ssids: ['long_pw_cafe'], password: 'abcdefgh12345678'),
  SignAnswer.wifi('variants-33', '작은 이름표와 큰 값의 높이가 어긋남', ssids: ['BIG_SKY_CAFE'], password: 'sky55555'),
  SignAnswer.wifi('variants-34', '포스터 속 와이파이 (행사·SNS·전화번호)', ssids: ['momo_bakery_guest'], password: 'bake2026'),
  SignAnswer.wifi('variants-35', '영수증 아래 와이파이', ssids: ['snack_bar_free'], password: 'snack1004'),
  SignAnswer.wifi('variants-36', '숙소 안내 (현관 비밀번호 함께)', ssids: ['stay_ocean_view'], password: 'ocean7777'),
  SignAnswer.wifi('variants-37', '네온 간판', ssids: ['neon_pub'], password: 'neon2580'),
  SignAnswer.wifi('variants-38', '색 알약 이름표', ssids: ['pill_cafe'], password: 'pill3690'),
  SignAnswer.wifi('variants-39', '비밀번호 없음 (공개 네트워크)', ssids: ['open_park'], password: ''),
  SignAnswer.wifi('variants-40', '비밀번호는 카운터 문의', ssids: ['ask_counter_cafe'], password: null),
  SignAnswer.wifi('variants-41', '영문 문장', ssids: ['Harbor_Guest'], password: 'harbor2026'),
  SignAnswer.wifi('variants-42', '따옴표 문장', ssids: ['햇살카페'], password: 'sun1234!'),
  SignAnswer.wifi('variants-43', '공백이 든 이름', ssids: ['Momo Coffee Roasters'], password: 'roast0101'),
  SignAnswer.wifi('variants-44', '한글 이름 + 대역 꼬리', ssids: ['모모커피_5G'], password: 'momo5g5g'),
  SignAnswer.wifi('variants-45', '층별 두 네트워크', ssids: ['floor1_cafe', 'floor2_cafe'], password: 'floors1212'),
  SignAnswer.wifi('variants-46', '손님용 / 직원용', ssids: ['guest_zone'], password: 'guest3333'),
  SignAnswer.wifi('variants-47', 'QR 코드 옆', ssids: ['qr_corner'], password: 'qrcode2026'),
  SignAnswer.wifi('variants-48', '사무실 회의실 게스트 Wi-Fi', ssids: ['Office_Guest_3F'], password: 'visit2026#'),
  SignAnswer.notWifi('variants-49', '화장실 비밀번호'),
  SignAnswer.notWifi('variants-50', '공동현관·도어락 비밀번호'),
  SignAnswer.notWifi('variants-51', 'SNS 홍보 카드'),
  SignAnswer.wifi('variants-52', '검은 판 이름 앞뒤 마름모 + 끝 물결표 (굵은 고딕 1)',
      ssids: ['모모양꼬치'], password: 'Momok123~'),
  SignAnswer.wifi('variants-53', '검은 판 이름 앞뒤 마름모 + 끝 물결표 (굵은 고딕 2)',
      ssids: ['달빛꼬치'], password: 'Dalbit2580~'),
];

const singleSignAnswers = <SignAnswer>[
  SignAnswer.wifi('sign1', '어두운 바탕, FREE WI-FI 제목, SSID / Password', ssids: ['TestCafe'], password: 'Test12345'),
  SignAnswer.wifi('sign2', '한글 제목·한글 이름표·한글 이름', ssids: ['카페모모'], password: 'Coffee!2024'),
  SignAnswer.wifi('sign3', 'WIFI 제목 아래 ID / PW 두 열', ssids: ['momo_guest'], password: 'hello1234'),
  SignAnswer.wifi('sign4', '이름표 위·값 아래 (WIFI / PASSWORD)', ssids: ['MOMO_GUEST'], password: 'Coffee#2024'),
  SignAnswer.wifi('sign-hotspot', 'FREE Wi-Fi 제목, Wi-Fi / PW', ssids: ['WifiLens_Test'], password: 'lens2026!'),
  SignAnswer.wifi('sign-sk-band', 'SK 대역 전용 표기 + 무선랜암호',
      ssids: ['SK_WiFiGIGA7C0D_5G', 'SK_WiFiGIGA7C0D_2.4G'], password: 'ABEF6@2497'),
];

/// EXIF 회전 사진: (사진 이름, 원본 이름, EXIF Orientation).
const photoSources = <(String, String, int)>[
  ('photo-sign1-exif6', 'sign1', 6),
  ('photo-variety-05-exif6', 'variety-05', 6),
  ('photo-variety-12-exif6', 'variety-12', 6),
  ('photo-variants-21-exif6', 'variants-21', 6),
  ('photo-variety-03-exif8', 'variety-03', 8),
  ('photo-variety-04-exif3', 'variety-04', 3),
  ('photo-sign4-exif6', 'sign4', 6),
  ('photo-sign4-exif8', 'sign4', 8),
  ('photo-variety-06-exif6', 'variety-06', 6),
  ('photo-variants-12-exif6', 'variants-12', 6),
];

final photoAnswers = <SignAnswer>[
  for (final (photo, source, orientation) in photoSources)
    [...varietyAnswers, ...variantAnswers, ...singleSignAnswers]
        .firstWhere((a) => a.name == source)
        .asPhoto(photo, 'EXIF 회전 $orientation ($source)'),
];

final allSignAnswers = <SignAnswer>[...varietyAnswers, ...variantAnswers, ...singleSignAnswers, ...photoAnswers];
