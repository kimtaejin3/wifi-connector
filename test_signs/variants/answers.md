# 변형 안내문 정답

`index.html`을 브라우저에서 열고 ← → 키나 클릭으로 넘겨요. 왼쪽 아래 번호가 아래 표의 번호예요.
한국 카페·식당·숙소·사무실 안내문에서 흔한 변형(글꼴·자간·세로쓰기·표·아이콘·손글씨·이름표 표기·
통신사 공유기 스티커·두 대역·비밀번호 메모·특수문자·O/0·줄바꿈·다른 글귀와 섞임)을 모았어요.
모든 이름과 비밀번호는 지어낸 값이라 실제로 연결되지는 않아요. 인식 결과만 확인해요.

- 이름 칸의 "A 또는 B"는 둘 중 아무거나 맞으면 정답이에요.
- 비밀번호 칸의 `(공개)`는 "비밀번호 없음"이라고 적힌 공개 네트워크(빈 비밀번호), `(안 적힘)`은 안내문에 비밀번호가
  없어서 결과에도 비밀번호가 없어야 한다는 뜻이에요.
- 자동 검사: `test/ocr_fixture_test.dart`가 이 표와 `test/support/sign_answers.dart`가 같은지 확인해요.

## Wi-Fi 안내문 (토스트가 떠야 함)

| # | 형태 | 이름 | 비밀번호 |
|---|---|---|---|
| 1 | 얇은 글꼴 | Lumi_Cafe | lumi7788 |
| 2 | 명조체 | sodam_books | books1004 |
| 3 | 아주 굵게·좁은 자간, 이름표 위·값 아래 | HANA_COFFEE | hana0303 |
| 4 | 값의 자간이 넓음 | cozy_home | cozy2026 |
| 5 | 둥근 글꼴 기울임 | Peach_Garden | peach5959 |
| 6 | 칠판 손글씨 | chalk_cafe | chalk1234 |
| 7 | 포스트잇 마커, 살짝 기울임 | hong_studio | hong0812 |
| 8 | 한글 이름표 + 손글씨 값 | dream_house | dream2580 |
| 9 | 세로쓰기 이름표 | maru_guest | maru4949 |
| 10 | 작은 이름표 위에 아주 큰 값 | Bloom_Flower | bloom2024!! |
| 11 | 기울어지게 찍힌 안내문 | tilt_cafe | tilt5678 |
| 12 | 표: 헤더 행 + 값 행 | grid_cafe | grid1357 |
| 13 | 표: 대역별 두 이름 | duo_net 또는 duo_net_5G | duo24680 |
| 14 | 이모지 아이콘만 | Sunrise_Inn | sunrise2026 |
| 15 | 와이파이명 / 패스워드 | nabi_hostel | nabi0505 |
| 16 | 네트워크 / 암호 | SEOUL_LOFT | loft3030 |
| 17 | ID. / PW. (마침표 구분) | orange_box | orange8282 |
| 18 | ▶ 기호 구분 | star_lounge | star7979 |
| 19 | 한 줄에 모두 | one_line_cafe | oneline2468 |
| 20 | 이름표 자간이 넓음 | spaced_wifi | spaced2468 |
| 21 | KT 공유기 스티커 (관리자 암호·MAC 함께) | KT_GiGA_2G_7A3F 또는 KT_GiGA_5G_7A3F | 3f8kd02pa7 |
| 22 | SK 공유기 스티커 | SK_WiFiGIGA9B2E 또는 SK_WiFiGIGA9B2E_5G | B7DE1@4410 |
| 23 | LG U+ 공유기 스티커 (표, 웹관리 암호 함께) | U+Net9F3C 또는 U+Net9F3C_5G | 9F3CA4E8D1 |
| 24 | ipTIME 공유기 라벨 | iptime_A1C9 | 87420631 |
| 25 | 영문 공유기 라벨 | TP-Link_5E2A | 51837264 |
| 26 | 두 대역을 한 줄에 | mint_house 또는 mint_house_5G | mint9090 |
| 27 | 아래 줄 메모 "0은 숫자" | zero_cafe | c0ffee0909 |
| 28 | 같은 줄 메모 "← 0은 숫자" (영문 O도 섞임) | loop_cafe | LOOP0909 |
| 29 | 특수문자 비밀번호 | symbol_bar | m@cha#2026! |
| 30 | 마침표·밑줄 든 비밀번호, 하이픈 이름 | dot-cafe | grape.juice_77 |
| 31 | O/0, I/l/1 혼동 | HILL_TOP_10 | l1Il0Oo2026 |
| 32 | 긴 비밀번호가 다음 줄로 넘어감 | long_pw_cafe | abcdefgh12345678 |
| 33 | 작은 이름표와 큰 값의 높이가 어긋남 | BIG_SKY_CAFE | sky55555 |
| 34 | 포스터 속 와이파이 (행사·SNS·전화번호) | momo_bakery_guest | bake2026 |
| 35 | 영수증 아래 와이파이 | snack_bar_free | snack1004 |
| 36 | 숙소 안내 (현관 비밀번호 함께) | stay_ocean_view | ocean7777 |
| 37 | 네온 간판 | neon_pub | neon2580 |
| 38 | 색 알약 이름표 | pill_cafe | pill3690 |
| 39 | 비밀번호 없음 (공개 네트워크) | open_park | (공개) |
| 40 | 비밀번호는 카운터 문의 | ask_counter_cafe | (안 적힘) |
| 41 | 영문 문장 | Harbor_Guest | harbor2026 |
| 42 | 따옴표 문장 | 햇살카페 | sun1234! |
| 43 | 공백이 든 이름 | Momo Coffee Roasters | roast0101 |
| 44 | 한글 이름 + 대역 꼬리 | 모모커피_5G | momo5g5g |
| 45 | 층별 두 네트워크 | floor1_cafe 또는 floor2_cafe | floors1212 |
| 46 | 손님용 / 직원용 | guest_zone | guest3333 |
| 47 | QR 코드 옆 | qr_corner | qrcode2026 |
| 48 | 사무실 회의실 게스트 Wi-Fi | Office_Guest_3F | visit2026# |

## Wi-Fi와 관계없는 글 (토스트가 뜨면 안 됨)

| # | 형태 |
|---|---|
| 49 | 화장실 비밀번호 |
| 50 | 공동현관·도어락 비밀번호 |
| 51 | SNS 홍보 카드 |

## 장식 기호·물결표 (토스트가 떠야 함)

검은 판에 금색 Wi-Fi 아이콘과 "WIFI", 그 아래 `◆ 이름 ◆`, 금색 가로줄, 맨 아래 `~`로 끝나는 비밀번호.
정답 이름에는 장식이 없고, 비밀번호는 `~`로 끝난다(OCR이 `~`를 `-`로 읽어도 정답은 `~`).

| # | 형태 | 이름 | 비밀번호 |
|---|---|---|---|
| 52 | 검은 판 이름 앞뒤 마름모 + 끝 물결표 (굵은 고딕 1) | 모모양꼬치 | Momok123~ |
| 53 | 검은 판 이름 앞뒤 마름모 + 끝 물결표 (굵은 고딕 2) | 달빛꼬치 | Dalbit2580~ |
