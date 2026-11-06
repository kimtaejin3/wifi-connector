# 낱장 안내문 정답

`test_signs/` 바로 아래의 낱장 안내문과, `tool/render_signs.sh`가 만드는 EXIF 회전 사진의 정답이에요.
슬라이드 묶음의 정답은 `variety/answers.md`, `variants/answers.md`에 있어요.
모든 이름과 비밀번호는 지어낸 값이라 실제로 연결되지는 않아요.

- 이름 칸의 "A 또는 B"는 둘 중 아무거나 맞으면 정답이에요.
- 자동 검사: `test/ocr_fixture_test.dart`가 이 표와 `test/support/sign_answers.dart`가 같은지 확인해요.

## 낱장 안내문

| 파일 | 형태 | 이름 | 비밀번호 |
|---|---|---|---|
| sign1 | 어두운 바탕, FREE WI-FI 제목, SSID / Password | TestCafe | Test12345 |
| sign2 | 한글 제목·한글 이름표·한글 이름 | 카페모모 | Coffee!2024 |
| sign3 | WIFI 제목 아래 ID / PW 두 열 | momo_guest | hello1234 |
| sign4 | 이름표 위·값 아래 (WIFI / PASSWORD) | MOMO_GUEST | Coffee#2024 |
| sign-hotspot | FREE Wi-Fi 제목, Wi-Fi / PW | WifiLens_Test | lens2026! |
| sign-sk-band | SK 대역 전용 표기 + 무선랜암호 | SK_WiFiGIGA7C0D_5G 또는 SK_WiFiGIGA7C0D_2.4G | ABEF6@2497 |

## EXIF 회전 사진

휴대폰 카메라가 저장하듯 픽셀은 돌아간 채로 두고 EXIF Orientation으로 "돌려서 보라"고 표시한 JPEG예요.
사진 앱에서는 원본과 똑같이 보이고, 정답도 원본과 같아요. (6: 세로로 들고 찍음, 8: 반대쪽 세로, 3: 거꾸로)

| 파일 | 원본 | EXIF Orientation |
|---|---|---|
| photo-sign1-exif6 | sign1 | 6 |
| photo-variety-05-exif6 | variety-05 | 6 |
| photo-variety-12-exif6 | variety-12 | 6 |
| photo-variants-21-exif6 | variants-21 | 6 |
| photo-variety-03-exif8 | variety-03 | 8 |
| photo-variety-04-exif3 | variety-04 | 3 |
| photo-sign4-exif6 | sign4 | 6 |
| photo-sign4-exif8 | sign4 | 8 |
| photo-variety-06-exif6 | variety-06 | 6 |
| photo-variants-12-exif6 | variants-12 | 6 |
