# 안내문 인식 감사 (OCR → 규칙 파서)

> 이 문서의 모든 Wi-Fi 이름·비밀번호는 테스트용으로 지어낸 값이다. 실제 가게·실제 공유기의 값은 하나도 없다.

## 0. 요약

- **진단 틀**: `test_signs`의 안내문을 headless Chrome으로 PNG로 찍고(`tool/render_signs.sh`), iOS 시뮬레이터의
  ML Kit(앱과 같은 `OcrService`, 한국어 인식기)로 원문 OCR을 뽑아 fixture로 저장하고(`tool/ocr_dump.sh`),
  `flutter test`가 그 fixture를 앱의 사진 인식 경로(`WifiCredentialExtractor.fromOcrResults` → 파서)에 넣어
  정답과 비교한다(`test/ocr_fixture_test.dart`). 폰 없이, 같은 결과가 매번 나온다.
- **fixture 91개**: 기존 variety 24장 + 이번에 늘린 변형 51장(`test_signs/variants/`) + 낱장 6장(`sign1~4`,
  `sign-hotspot`, `sign-sk-band`) + EXIF 회전 사진 10장. 이 중 Wi-Fi가 아닌 글이 11장(variety 17~24, 변형 49~51).
- **지금 결과**: 통과 53 · 알려진 실패 38 (`skip` + 사유, 4장 표). 실패 원인은 바로 고칠 수 있는 파서 규칙 22건
  (P1·P2), 설계가 더 필요한 파서 규칙 5건(P3), 파서로는 못 고치는 OCR 단계 11건(P4).
- **개선 항목 19개** (5장). 파서·`OcrService`에 임시 시제품을 넣어 재 보니 P1 다섯 항목만으로 통과가 53 → 65,
  시제품을 만든 P1·P2 항목 11개를 다 합치면 53 → 74(21개 고침)다. 기존 테스트는 P2-3에서 운영자 결정으로 기대를
  바꾸기로 한 1개(`SK_WIFiGIGA7COD_2.4G` 경우) 말고는 하나도 깨지지 않았다(7장). 시제품은 모두 되돌렸고 `lib/`는
  바뀌지 않았다.
- **상위 3개**: P1-1 구분자·이름표 모양 넓히기(5개 고침), P1-2 밑줄 옆 공백 지우기(2개, EXIF 보정과 함께 3개),
  P1-3 화장실·현관 비밀번호 거르기(Wi-Fi 아닌 글 2개).
- **원칙 (운영자)**: 정답(기대값)은 **무조건 정상 인식**, 즉 안내문에 실제로 적힌 값이다. OCR이 잘못 읽은 모양은
  정답이 될 수 없고, 남기더라도 결과 화면의 "다른 후보"로만 남긴다. 오인식 모양을 정답으로 고정한 기존 테스트는
  정상 인식 값으로 고친다(6장 목록).
- **결정 (2026-11-06, 운영자)**: `SK_WIF1GIGA`·`SK_WIFiGIGA`처럼 읽힌 SK 공유기 이름은 오인식으로 보고 실제 형식
  `SK_WiFiGIGA`로 고친다(P2-3). 기존 테스트 하나의 기대를 이에 맞춰 바꾼다.
- **variety 8번**: `variety/answers.md`에 적혀 있던 "이름을 `2.4G`/`5G`로 잘못 고르는 문제"는 이 fixture에서는 재현되지
  않는다(`variety-08` 통과, 이름 `U+NetA7C2_5G`). 그 메모보다 뒤인 2026-10-12 커밋 `110e36f`(대역 표시를 이름에서 제외)에서
  고쳐진 것으로 보이지만, 실기기 카메라에서도 그런지는 다시 확인해야 한다(1.8). 메모는 이 내용으로 고쳐 두었다.

## 1. 방법 — 진단 틀 쓰는 법

### 1.1 구성

| 파일 | 하는 일 |
|---|---|
| `test_signs/variety/index.html`, `answers.md` | 기존 안내문 24장과 정답 (1~16 Wi-Fi, 17~24 Wi-Fi 아님) |
| `test_signs/variants/index.html`, `answers.md` | 이번에 늘린 변형 51장과 정답 (1~48 Wi-Fi, 49~51 Wi-Fi 아님) |
| `test_signs/answers.md` | 낱장 안내문(`sign1~4`, `sign-hotspot`, `sign-sk-band`)과 EXIF 회전 사진 10장의 정답 |
| `test_signs/slides.js` | 슬라이드 넘기기. `?slide=N`으로 열면 N번째 장만 보이고 번호·안내 글자를 지운다 |
| `tool/render_signs.sh` | 안내문을 `build/test_signs/`에 이미지로 모은다 (슬라이드는 장별 PNG, 낱장 HTML은 PNG, HTML 없는 PNG는 복사, EXIF 사진 생성) |
| `tool/make_exif_photo.dart` | 똑바른 이미지를 "픽셀은 돌아간 채 + EXIF Orientation" JPEG로 만든다 (휴대폰 세로 사진 재현) |
| `integration_test/ocr_dump_test.dart` | 시뮬레이터에서 앱의 `OcrService`로 이미지마다 원문 OCR을 읽어 fixture JSON을 쓴다. `--dart-define`으로 경로를 줄 때만 동작 |
| `tool/ocr_dump.sh` | 시뮬레이터 부팅 → 위 테스트 실행 → fixture 개수 확인 (스크립트가 켠 시뮬레이터는 끝나고 끈다) |
| `test/fixtures/ocr/<이름>.json` | 원문 OCR fixture 91개 (커밋됨) |
| `test/support/ocr_fixture.dart` | fixture를 앱의 `OcrResult`로 되살린다 |
| `test/support/sign_answers.dart` | `answers.md`를 그대로 옮긴 정답표 |
| `test/ocr_fixture_test.dart` | fixture → 추출기 → 정답 비교, 알려진 실패 `skip`, 목록 검사 4개 |

앱 코드(`lib/`)에는 아무것도 더하지 않았다. 덤프 진입점은 `integration_test/` 아래 테스트이고 `--dart-define`이
없으면 건너뛴다. 릴리스 빌드와 일반 동작에는 들어가지 않는다.

### 1.2 다시 뽑기

```sh
tool/render_signs.sh          # build/test_signs/에 이미지 91개 (1~2분, Google Chrome headless, 임시 프로필)
tool/ocr_dump.sh              # iPhone 16 시뮬레이터(6186BDC9-…)로 test/fixtures/ocr/*.json 91개 (첫 빌드 1~2분 + 인식 45초)
OCR_DUMP_ONLY=variants-52 tool/ocr_dump.sh   # 몇 장만 다시 뽑기
flutter test test/ocr_fixture_test.dart       # fixture 검사 (flutter test 전체에도 들어 있다)
```

- 같은 이미지를 다시 뽑으면 fixture가 바이트 단위로 똑같이 나온다(커밋한 91개를 임시 폴더로 다시 뽑아 비교, 차이 0).
  `tool/ocr_dump.sh build/test_signs <임시 폴더>`로 두 번째 인자에 다른 폴더를 주면 커밋된 fixture를 건드리지 않고 비교할 수 있다.
- ML Kit iOS pod에 arm64 시뮬레이터 조각이 없어 시뮬레이터 앱은 x86_64(Rosetta)로 빌드된다. pod install 직후 첫
  `flutter test -d`에서 `Framework 'Pods_Runner' not found`가 한 번 났고, `flutter build ios --simulator --debug`를 한 번
  돌린 뒤에는 나지 않았다.
- 인식한 글자(비밀번호 포함)는 fixture 파일에만 쓴다. 두 스크립트의 출력에는 이미지 이름과 줄 수만 나온다.

### 1.3 fixture 형식

```json
{
  "name": "variety-01", "source": "variety-01.png",
  "recognizer": "ML Kit TextRecognizer(korean) via OcrService · ios Version 18.4 (Build 22E238)",
  "image": {"width": 1600, "height": 1200, "exifOrientation": null},
  "text": "<ML Kit 원문>", "layoutText": "<덤프 당시 layoutRows 결과, 기록용>",
  "lines": [ {"text": "…", "box": [left, top, right, bottom], "elements": [{"text": "…", "box": […]}, …]}, … ]
}
```

- `image`는 **저장된 픽셀** 크기와 EXIF 회전 값이다. `box`는 ML Kit가 준 그대로다.
- 테스트는 `layoutText`를 쓰지 않고 `lines`로 지금 코드의 `layoutRows`를 다시 돌린다. 그래서 행 재구성을 고치면
  fixture를 다시 뽑지 않아도 결과에 반영된다.
- `elements`(단어 상자)는 `OcrService`가 밖으로 내주지 않아서, 덤프 도구가 같은 설정의 인식기를 한 번 더 돌려 얻고
  줄 글자가 `OcrService` 결과와 똑같을 때만 붙인다(91개 모두 붙음). 밑줄·자간 분석(P2-2, P3-3, P3-5)을 폰 없이 시험하는 데 쓴다.
- iOS는 글자 신뢰도가 없어(A3) `chars`/`conf`는 비어 있다. Android에서 뽑으면 채워진다.

### 1.4 판정

- 기준: 정답은 언제나 **정상 인식** — 안내문에 실제로 적힌 값이다. 정답표 91개(`answers.md`, `sign_answers.dart`)는
  모두 이 기준으로 적었고, OCR이 잘못 읽은 모양은 4장의 "실제"와 보고서의 후보 목록에만 나온다. fixture를 다시 뽑아
  OCR 결과가 달라져도 정답은 바꾸지 않는다.
- 경로: 갤러리에서 사진을 고른 경우와 같다 — `WifiCredentialExtractor().fromOcrResults([fixture.toOcrResult()])`.
  (`layoutText` 파싱 → 빠진 쪽만 원문 파싱으로 채움 → 불확실 글자 후보, K1~K2)
- Wi-Fi 안내문: 1순위 이름이 정답 중 하나이고 1순위 비밀번호가 정답과 같아야 통과. `(공개)`는 빈 비밀번호,
  `(안 적힘)`은 비밀번호가 없어야 통과. 신뢰도("확인 필요")는 보지 않고 보고서에만 적는다.
- Wi-Fi가 아닌 글: 이름도 비밀번호도 내지 않아야 통과.
- 목록 검사 4개: ① `test_signs`의 모든 안내문(슬라이드 장 수, 낱장 HTML·PNG, EXIF 사진)에 fixture와 정답이 하나씩
  있다 ② 정답표가 `answers.md` 표와 같다 ③ 알려진 실패 목록이 실제 결과와 같다(고쳐진 것도, 새로 깨진 것도 잡는다)
  ④ 알려진 실패 목록이 이 문서 4장 표와 같다.

### 1.5 보고서

```sh
OCR_FIXTURE_REPORT=build/ocr_fixture_report.md flutter test test/ocr_fixture_test.dart
```

안내문마다 기대·실제(신뢰도)·정답이 후보 몇 번째에 있는지·행 재구성만/원문만 파싱한 결과를 표로, 틀린 안내문은
원문과 행 재구성 텍스트까지 쓴다. (지어낸) 비밀번호가 들어 있으니 `build/` 아래에 둔다.

### 1.6 고친 뒤 할 일

1. `flutter test` — 기존 테스트와 fixture 검사가 함께 돈다.
2. 알려진 실패가 맞게 되면 "알려진 실패 목록이 실제 결과와 같다"가 빨개지며 고쳐진 이름을 알려 준다.
   `test/ocr_fixture_test.dart`의 `knownFailures`와 이 문서 4장 표에서 그 줄을 지운다.
3. 맞던 안내문이 틀리면 그 안내문 테스트와 같은 검사가 빨개진다 — 회귀다.
4. `OcrService`(단어 간격·EXIF 좌표처럼 OCR 결과 자체)를 바꾸면 fixture 로더(`OcrFixture.toOcrResult`)도 같은 lib
   함수를 부르게 바꾼다. 원문 글자가 달라지는 변경이면 `tool/ocr_dump.sh`로 다시 뽑는다.

### 1.7 새 안내문 넣기

1. `test_signs/variants/index.html`에 `<section class="slide">`를 하나 더하고(값은 지어낸 것만), `answers.md` 표에
   같은 번호로 정답을 적고, `test/support/sign_answers.dart`의 `variantAnswers`에도 같은 값을 넣는다.
2. `tool/render_signs.sh && OCR_DUMP_ONLY=variants-52 tool/ocr_dump.sh`
3. `flutter test test/ocr_fixture_test.dart` — 틀리면 `knownFailures`와 4장 표에 사유와 함께 넣는다.
   EXIF 사진은 `tool/render_signs.sh`의 `EXIF_PHOTOS`와 `test_signs/answers.md`·`photoSources`에 넣는다.

### 1.8 한계

- fixture는 화면에 그린 깨끗한 이미지를 읽은 것이다. 실기기 카메라(흐림·기울기·반사·저해상도·가이드 크롭·여러 프레임
  투표)는 다르다. 실기기에서 틀리는데 여기서 맞는 안내문이 있을 수 있다(variety 8번처럼).
- 셔터 경로(가이드 크롭 → 빠진 값은 전체 사진으로 채움)와 실시간 투표(L1~L3)는 다루지 않는다.
- iOS 시뮬레이터 ML Kit만 썼다. Android ML Kit는 글자 신뢰도를 주고 결과가 조금 다를 수 있다.

### 1.9 이번에 확인한 OCR 사실

- **EXIF 회전 사진**: ML Kit는 글자는 똑바로 읽지만 상자는 **저장된 픽셀(옆으로 누운) 기준**으로 준다(방향 3·6·8 모두).
  그래서 방향 6·8 사진은 모든 줄 상자가 세로로 길어지고 `layoutRows`가 모든 줄을 탭으로 이은 한 행으로 만든다.
  방향 6은 탭으로 이은 칸 순서가 원래의 위→아래와 같아 이름표 다음 칸에 값이 오는 안내문은 대개 그대로 맞지만
  (`photo-sign4-exif6` 통과, 원문 보완 K1 덕분이기도 하다), 방향 8은 순서가 뒤집혀
  `photo-sign4-exif8`이 이름 `WELCOME`·비밀번호 `MOMO_GUEST`를 신뢰도 0.90/0.92로 낸다. 방향 3은 행과 칸 순서가 모두
  뒤집힌다. 아래 변환으로 원본 상자와 1~2px 안으로 맞는다(저장 크기 `W×H`):
  - 6: `(l, t, r, b) → (H−b, l, H−t, r)` · 8: `→ (t, W−r, b, W−l)` · 3: `→ (W−r, H−b, W−l, H−t)`
- **밑줄을 놓친 공백은 단어 상자가 거의 붙어 있다**: 줄 높이에 대한 단어 상자 사이 간격 비율이
  밑줄 자리(OCR이 밑줄을 공백으로 읽음) `Lumi|Cafe` 0.04, `sodam|books` 0.03, `HANA|COFFEE` 0.05, `OficeGuest|3F` 0.05,
  OCR이 없는 공백을 넣은 자리 `Study|_Room` 0.05, `books|1004` 0.03 — 진짜 띄어쓰기는 0.28~0.60
  (`Momo Coffee Roasters` 0.47~0.53, 안내 문장 0.44~0.48, `손님용 WIFI` 0.36, `현관 비밀번호` 0.41).
  예외: `Harbor|Guest`(세리프 글꼴)는 밑줄 자리인데 1.07로 오히려 넓고, 자간 넓은 글자는 글자 사이 0.26~0.64.
- 어떤 글꼴·배치에서는 줄을 통째로 놓친다: 칠판 손글씨체의 PW 줄(`variants-06`), 작은 메모가 같은 줄에 붙은 PW 줄
  (`variants-28`), 굵은 값 `hello1234`(`sign3`).

## 2. 현재 파서가 하는 일 (동작 셀)

코드(`lib/features/wifi_scanner/…`)와 기존 테스트(`test/wifi_credential_parser_test.dart` 등)에서 뽑은 동작 목록이다.
실패 분석과 개선 항목은 이 셀 번호로 어느 규칙이 관여하는지 가리킨다.

### A. OCR (`data/services/ocr_service.dart`)

| 셀 | 동작 |
|---|---|
| A1 | ML Kit 온디바이스 **한국어 인식기 하나만** 쓴다. 한국어 인식기가 라틴 글자도 읽는다 (라틴 인식기는 플러그인 id 충돌로 사실상 같은 인식기였어서 뺐다). |
| A2 | `text` = ML Kit 원문(블록 → 줄 순서, `\n`). `layoutText` = 줄 상자의 세로 중심이 `min(높이)*0.5` 안이면 같은 행으로 묶고, 행 안은 왼쪽부터 탭(`\t`)으로 잇는다 (`layoutRows`). |
| A3 | iOS 플러그인은 글자 신뢰도를 주지 않는다(`confidence: nil`, `symbols: []`). 그래서 iOS의 "불확실 글자"는 기호 오인식 글자(`ㅡ 一 ー ㅣ 丨 〇 ○ 井 ©`)에서만 생긴다. |
| A4 | 실시간 인식은 가이드 영역 안 줄만 남긴다(`withLines`). 셔터 사진은 가이드 영역을 잘라 인식하고, 빠진 값이 있으면 전체 사진으로 다시 인식해 채운다. 갤러리 사진은 전체를 읽는다. |
| A5 | 상자 좌표는 ML Kit가 준 그대로 쓴다. 사진의 EXIF 회전을 따로 보정하지 않는다. |

### B. 정규화 (`core/utils/text_normalizer.dart`, 파서 입력 전에 줄마다)

| 셀 | 동작 |
|---|---|
| B1 | 전각 ASCII → 반각, 전각 공백·NBSP → 공백, 폭 없는 공백 제거, `İ` → `i`. |
| B2 | 대시류(`‐ ‑ ‒ – — ― −`) → `-`, 굽은 따옴표 → 곧은 따옴표, `…` → `...`. |
| B3 | 한국어 인식기가 기호를 자모·한자로 읽은 글자: `ㅡ 一 ー` → `-`, `ㅣ 丨` → `l`, `〇 ○` → `0`, `〜 ∼` → `~`, `井` → `#`, `©` → `@`. |

### C. 토큰화 (`WifiCredentialParser._tokenize`)

| 셀 | 동작 |
|---|---|
| C1 | `\n`으로 행, `\t`로 셀을 나눈다. 셀 앞의 글머리 기호(`• ▶ ※ ★ -` …)와 아이콘 자리(영숫자·한글이 아닌 한두 글자 + 공백, 예: `令 cafe`)를 떼고, 아이콘만 있는 셀은 버린다. |
| C2 | 작은 글씨 "아이디"를 깨뜨려 읽은 셀(`OFOI`, `OHOI`, `OFO1TA` … 모양)은 `아이디` 이름표로 되돌린다. |
| C3 | 대역 표시: 이름 앞 `5G`, `2.4G 전용 :`, `5G 8 :`(깨진 "전용")을 떼고, 대역만 있는 칸은 버리고, 한 칸에 `5G 이름A 2.4G 이름B`처럼 두 이름이 이어지면 나눈다(양쪽이 완성된 이름 모양일 때만). |

### D. 이름표 인식 (`_segmentCell`, `_passwordLabel`, `_ssidLabel`)

| 셀 | 동작 |
|---|---|
| D1 | 비밀번호 이름표 — 강: `password`(o↔0, 띄어 쓴 `p a s s w o r d`), `passward`, `passwd`, `passcode`, `pwd`, `P/W`, `P.W`, `PW`/`PVV`, `비밀번호`(글자 사이 공백·`|`·`I`·`l`·`1` 허용), `비번`, `암호`(`암호키`), `보안키`, `네트워크 키`, `패스워드`. 약: `pass`, `key`. 앞에 `와이파이`·`WiFi`·`네트워크`·`FREE/무료`가 붙어도 된다. |
| D2 | 이름 이름표 — 강: `SSID`(`S5ID`, `SSlD` …), `network name`, `user name`, `네트워크 이름/명`, `<와이파이 말> name/id/ssid/이름/명`. 중: `Wi-Fi` 변형(`WIFI`, `Wl-Fi`, `W-Fi`, `Wi-F`), `WLAN`, `와이파이`, `무선 인터넷`, `무선랜`, `인터넷`, `internet`, `connect to`, `join`, `아이디`. 약: `network`, `네트워크`, `ID`(`lD`, `1D`, `|D`, `I.D`, `I D`), `name`, `이름`. |
| D3 | 이름표 뒤 조사(`는 은 이 가 를 을`, ` is`)를 허용하고, 뒤에 글자·숫자·`_`가 바로 붙으면 이름표가 아니다(`WIFI_MOMO`, `Keyboard`). |
| D4 | 이름표 뒤 괄호 설명(`Wi-Fi (5G) :`, `비밀번호 (Password) :`), 콜론 앞 대역(`WIFI 2.4G :`), 두 말 이름표(`Wi-Fi / 와이파이 :`)를 이름표에 포함한다. |
| D5 | 구분자: `: = ： ; |`(1~3개, 뒤 `>` 허용), 공백이 뒤따르는 `- – — > → ➜ ➔ ⇒ =>`. |
| D6 | 셀 중간의 이름표는 구분자가 있거나 강한 비밀번호 이름표일 때만 인정한다. |
| D7 | 이름표 값이 잡음 낱말뿐이면(`FREE WIFI ZONE`, `와이파이 이용방법`) 제목(header)으로 보고 값을 비운다. |
| D8 | 구분자 없는 중·약 이름표 뒤에 여러 단어가 오면 이름표로 보지 않는다(따옴표로 감싼 값은 예외: `Connect to "Momo Guest"`). |
| D9 | 값 정리: 공백 뒤 괄호 설명(`12345678 (숫자 8자리)`), 문장 끝(`입니다`, `예요`, `이고` …), 감싼 따옴표만 뗀다. 대소문자·특수문자는 바꾸지 않는다. |

### E. 값 배정 (`parse` 본문)

| 셀 | 동작 |
|---|---|
| E1 | 이름표 바로 뒤 값(inline). 기본 점수: 구분자 있음 0.95(이름)/0.97(비밀번호), 강한 이름표 0.93/0.95, 그 밖 0.85. |
| E2 | 비밀번호 앞부분만 이름표 칸에 붙고 나머지가 옆 칸으로 쪼개진 경우(`PW : a ⇥ 123456789`) 이어 붙인다(합쳐 8~63자 ASCII일 때). |
| E3 | 값 없는 이름표가 이어지고(`ID / PW`) 같은 칸의 다음 이름표가 값 하나를 나눠 쓰면(`ID/PW : a / b`) 값을 나눈다. |
| E4 | 같은 행 다음 칸의 값(`Wi-Fi ⇥ cafe_momo`, 점수 0.9/0.92). |
| E5 | 비밀번호 이름표 옆·아래의 한글 글귀(옆 포스터)는 값이 아니다. 한글 글귀만 있는 행은 3줄까지 건너뛴다. |
| E6 | 다음 행의 값(점수 −0.02). 헤더 행과 값 행의 칸 수가 같으면 같은 열끼리 맞춘다(표). 아니면 앞쪽 값부터 이름표 순서대로. |
| E7 | 이름표 여러 개에 값 칸이 하나면 ` / `, `|`, `/`, 공백 순으로 나눠 본다. |
| E8 | 제목 이름표(`FREE WIFI`) 다음의 문장(공백 포함)은 값이 아니고, 제목 다음 줄 값은 −0.25. |

### F. 후보 보정 (`add`)

| 셀 | 동작 |
|---|---|
| F1 | 비밀번호 앞 마침표·쉼표를 뗀다(콜론을 `.`로 읽은 경우, 뒤가 8자 이상일 때). |
| F2 | 비밀번호 뒤 메모(`<=숫자 0`, `← zero`, 한글 설명)를 떼고, 메모가 "숫자 0"이면 `O/o→0`, "영문 O"면 `0→O`로 고친 값을 1순위, 원래 값을 0.9배 후보로. |
| F3 | `없음`, `none`, `open`, `x`, `-` 등은 빈 비밀번호(공개 네트워크) 후보. |
| F4 | 공백이 든 이름이 공유기 이름 모양(이미 `_`가 있음, 통신사 접두어, 3단어 이상에 숫자 토큰 2개)이면 공백을 `_`로 이은 값을 1순위(×0.9), 원래 값은 0.7. |
| F5 | 비밀번호 안 공백이 OCR 틈으로 보이면(조각에 숫자가 있거나 한 글자 조각) 붙인 값을 1순위, 공백 값은 −0.05 후보. |
| F6 | 점수 계수 — 이름: 32바이트 초과 ×0.3, 2단어 ×0.9(떨어진 칸)/×0.7, 3단어 ×0.7/×0.5, 4단어 이상 ×0.4, 연락처 모양 ×0.3, 잡음 낱말 ×0.2. 비밀번호: ASCII 아님 ×0.3, 4자 미만 ×0.3, 8자 미만 ×0.7, 63자 초과 ×0.3, 공백 ×0.8/×0.4. |

### G. 이름표 없는 추측 (`_addUnlabeledFallbacks`)

| 셀 | 동작 |
|---|---|
| G1 | 이름표로 이름을 못 찾았을 때, 한 단어만 있는 행 다음 행이 비밀번호 모양이면 윗줄을 이름(0.45), 아랫줄을 비밀번호로 본다. |
| G2 | 이름은 이름표로 찾았고 Wi-Fi 맥락이 있을 때, 깨진 이름표 줄(`비 번 : x`, `H| H x`: 앞부분 6자 이하·숫자 없음·연락처 이름표 아님)의 값을 비밀번호 후보(+0.05)로. |
| G3 | 한 행에 두 토큰(`lunahouse7 b83kd02jq1`)이면 이름·비밀번호 0.42씩. |
| G4 | 이름 모양(`_` 포함, 통신사 접두어, `_5G` 꼬리) 0.5. |
| G5 | 비밀번호 모양: 8~63자 ASCII, 연락처·전화번호·날짜 아님. 숫자만 0.4, 숫자+(영문|기호) 0.5. |

### H. 변형 후보

| 셀 | 동작 |
|---|---|
| H1 | 공백이 든 값마다 `_`·`-`·(비밀번호만) 공백 제거 후보. 이름 끝 대역(`… 5G`) 앞 공백이면 `_` 쪽이 +0.01로 1순위. |
| H2 | KT 이름의 `GIGA`/`GlGA`/`G1GA` → `GiGA` (+0.01). SK의 `WiFiGIGA`는 그대로. |
| H3 | 통신사 이름(`SK_WiFiGIGA`, `KT_GiGA_…`, `U+Net`) 16진수 꼬리 네 글자의 `O/o→0`, `I/l→1` (+0.01). |

### I. 선택 (`_select`)

| 셀 | 동작 |
|---|---|
| I1 | 같은 종류·값은 높은 점수만 남기고, 0.4 미만은 버리고, 점수 순으로 1순위를 고른다. |
| I2 | 이름과 비밀번호가 같은 값이면 점수가 낮은 쪽이 다음 후보로 내려간다. |
| I3 | 값에 공백이 있거나 구분자(` _ -`)만 다른 후보가 있으면 신뢰도를 0.75로 낮춰 "확인 필요"를 띄운다. |

### J. Wi-Fi가 아닌 글 거르기

| 셀 | 동작 |
|---|---|
| J1 | 글 전체에 Wi-Fi 단서(`Wi-Fi`·`WLAN`·`SSID`·`password`류·`비밀번호`류·`와이파이`·`무선랜` …)가 없고 이름이 공유기 이름도 아니면, 이름표 없는 작은 카드 모양(3줄 이하, 이름에 숫자·`_`·`-`·CamelCase, 비밀번호 8자 이상에 숫자+영문/기호, 날짜·전화·번호판 아님)일 때만 결과를 내고 아니면 후보까지 모두 버린다. |

### K. 추출기 (`wifi_credential_extractor.dart`)

| 셀 | 동작 |
|---|---|
| K1 | `layoutText`로 먼저 파싱하고, 이름·비밀번호 중 빠진 쪽이 있으면 원문(`text`)으로 다시 파싱해 빠진 쪽 후보만 채운다(`fillMissing`). 둘 다 없으면 원문 결과를 쓴다. |
| K2 | 불확실 글자 위치(A3)가 있으면 혼동 글자(`0↔@/O/o`, `1↔l/I/!`, `5↔S/$` …)로 바꾼 후보를 앞 두 자리까지 덧붙이고 신뢰도를 낮춘다. |
| K3 | 결과 화면 직전 `O·0·o`를 바꾼 후보를 덧붙인다(`withLookalikes`). 고른 값과 신뢰도는 그대로. |

### L. 투표기 (`credential_voter.dart`, 실시간·셔터)

| 셀 | 동작 |
|---|---|
| L1 | 최근 8개 판독 중 가장 흔한 길이끼리 글자 위치별 다수결. 3표 이상·일치율 0.6 이상이면 "안정"(셔터 없이 결과 띄움). |
| L2 | 한 프레임이라도 `@`로 읽었고 나머지가 `0/O/o`뿐이면 `@`를 고르고 그 자리를 불확실로 표시한다. |
| L3 | 셔터 사진은 2표. 한 번 안정된 결과는 다른 값이 안정될 때까지 유지한다(`heldOver`). |

## 3. 결과 요약

| 묶음 | 장 수 | 통과 | 알려진 실패 |
|---|---|---|---|
| variety (기존) | 24 | 18 | 6 (Wi-Fi 안내문 `06` `07` `09` `10` `16`, Wi-Fi 아닌 글 `23`) |
| variants (이번에 늘림) | 51 | 22 | 29 |
| 낱장 (`sign1~4`, `sign-hotspot`, `sign-sk-band`) | 6 | 5 | 1 (`sign3`) |
| EXIF 회전 사진 | 10 | 8 | 2 |
| **합계** | **91** | **53** | **38** |

Wi-Fi가 아닌 글 11장 중 `variety-23`, `variants-49~51` 4장이 Wi-Fi로 잘못 나온다. 원인별로 묶으면:

| 원인 | 건수 | 개선 |
|---|---|---|
| 구분자·이름표 모양을 모름 (`ID.`, `▶`, `[WIFI]`, 값 칸에 붙은 `:`, `Password/PIN:`) | 5 | P1-1 |
| OCR이 밑줄 옆에 공백을 넣음 (`Study _Room`, `one_ line_cafe`) | 2 | P1-2 |
| Wi-Fi가 아닌 글을 Wi-Fi로 냄 (화장실·현관 비밀번호, 예약 안내, SNS 카드) | 4 | P1-3, P1-4 |
| 한 글자 이름 (세로쓰기 이름표) | 1 | P1-5 |
| EXIF 회전 사진의 상자 좌표 | 2 | P2-1 (+P1-2) |
| OCR이 밑줄을 공백으로 읽음 (가게 이름 띄어쓰기와 글자로는 못 가림) | 4 | P2-2, P3-5 |
| 통신사 공유기 이름을 OCR이 깨뜨림 | 2 | P2-3 |
| 비밀번호 아래 줄 메모, 깨진 Wi-Fi 이름표, 비밀번호 대신 고른 문장 | 3 | P2-4, P2-5, P2-6 |
| 한 줄 두 대역, 이름 속 `.`, 자간 넓은 이름, 줄바꿈된 비밀번호 | 4 | P3-1~P3-4 |
| OCR이 글자를 바꿔 읽거나 빠뜨리거나 줄을 놓침 (파서로는 못 고침) | 11 | P4-1~P4-3 |

## 4. 알려진 실패

`test/ocr_fixture_test.dart`의 `knownFailures`와 이 표는 같아야 한다(목록 검사 ④가 확인). 값은 모두 지어낸 값이다.
"실제"는 지금 코드의 1순위 이름 · 비밀번호, `—`는 없음. 셀 번호는 2장.

<!-- known-failures:start -->
| fixture | 형태 | 기대 (이름 · 비밀번호) | 실제 (이름 · 비밀번호) | 원인 | 셀 | 개선 |
|---|---|---|---|---|---|---|
| `variants-17` | ID. / PW. (마침표 구분) | `orange_box` · `orange8282` | — · `orange8282` | `ID.`의 마침표를 구분자로 모름 → 약한 이름표 뒤 여러 단어로 보고 버림 | D5, D8 | P1-1 |
| `variants-18` | ▶ 기호 구분 | `star_lounge` · `star7979` | — · — | `►`(OCR이 읽은 ▶)를 구분자로 모름 | D5, D8 | P1-1 |
| `variants-20` | 이름표 자간이 넓음 | `spaced_wifi` · `spaced2468` | `:spaced_wifi` · `spaced2468` | 콜론이 값 칸(`:spaced_wifi`)에 붙어 같은 행 다음 칸 값으로 그대로 씀 | E4 | P1-1 |
| `variants-25` | 영문 공유기 라벨 | `TP-Link_5E2A` · `51837264` | `TP-Link_5E2A` · `/PIN:51837264` | `Password/PIN:`의 `/PIN`이 값에 붙음 | D4 | P1-1 |
| `variants-35` | 영수증 아래 와이파이 | `snack_bar_free` · `snack1004` | — · — | `[WIFI]`, `[PW]` 괄호 이름표를 모름 | C1, D1, D2 | P1-1 |
| `variety-06` | ID / PW 표 | `Study_Room` · `study4321` | `Study__Room` · `study4321` | OCR이 밑줄 앞에 공백을 넣음(`Study _Room`) → 공백까지 밑줄로 이음 | F4, D9 | P1-2 |
| `variants-19` | 한 줄에 모두 | `one_line_cafe` · `oneline2468` | — · `oneline2468` | OCR이 밑줄 뒤에 공백을 넣음(`one_ line_cafe`) → 여러 단어로 보고 이름표 버림 | D8, D9 | P1-2 |
| `variants-49` | 화장실 비밀번호 | (Wi-Fi 아님) | — · `1234*` | "화장실 비밀번호"를 비밀번호 이름표·Wi-Fi 단서로 씀 | D1, J1 | P1-3 |
| `variants-50` | 공동현관·도어락 비밀번호 | (Wi-Fi 아님) | — · `#2580*` | "공동현관/도어락 비밀번호"를 비밀번호 이름표·Wi-Fi 단서로 씀 | D1, J1 | P1-3 |
| `variety-23` | 예약 안내 (영문+숫자 두 줄) | (Wi-Fi 아님) | `table07` · `guest2026` | 제목 `Reservation` + 두 줄을 이름표 없는 카드로 봄 | G1, J1 | P1-4 |
| `variants-51` | SNS 홍보 카드 | (Wi-Fi 아님) | `@cafe_momo_official` · `#momo2026` | SNS 계정·해시태그를 카드의 이름·비밀번호로 봄 | G4, G5, J1 | P1-4 |
| `variants-09` | 세로쓰기 이름표 | `maru_guest` · `maru4949` | `파` · `maru4949` | 세로 이름표를 한 글자씩 읽고, 표 열 맞추기로 한 글자 `파`를 이름으로 고름 | E6, F6 | P1-5 |
| `photo-sign4-exif8` | EXIF 회전 8 (sign4) | `MOMO_GUEST` · `Coffee#2024` | `WELCOME` · `MOMO_GUEST` | 상자가 누운 좌표라 모든 줄이 한 행에 거꾸로 이어짐 → 이름표 다음 칸이 엉뚱한 값 | A2, A5, E4 | P2-1 |
| `photo-variety-06-exif6` | EXIF 회전 6 (variety-06) | `Study_Room` · `study4321` | — · `study4321` | 모든 줄이 한 행(`ID ⇥ PW ⇥ Study _Room ⇥ study4321`)이 되고 밑줄 앞 공백까지 겹침 | A2, A5, E3 | P2-1, P1-2 |
| `variants-01` | 얇은 글꼴 | `Lumi_Cafe` · `lumi7788` | `Lumi Cafe` · `lumi7788` | OCR이 밑줄을 공백으로 읽음 (단어 간격 0.04×줄 높이) | F4, H1, I3 | P2-2 |
| `variants-02` | 명조체 | `sodam_books` · `books1004` | `sodam books` · `books1004` | 위와 같음 (간격 0.03) | F4, H1, I3 | P2-2 |
| `variants-03` | 아주 굵게·좁은 자간, 이름표 위·값 아래 | `HANA_COFFEE` · `hana0303` | `HANA COFFEE` · `hana0303` | 위와 같음 (간격 0.05) | F4, H1, I3 | P2-2 |
| `variety-09` | 통신사 공유기 이름 | `KT_GiGA_5G_Wave2_4F1A` · `k9x2m4p8q1` | `KT_GiGA5G_Wave2_4FIA` · `k9x2m4p8q1` | OCR이 `GIGA` 뒤 밑줄을 빠뜨리고 꼬리 1을 I로 읽음 → H3의 이름 모양에 안 맞아 꼬리를 못 고침 | H2, H3, G4 | P2-3 |
| `variants-22` | SK 공유기 스티커 | `SK_WiFiGIGA9B2E` 또는 `_5G` · `B7DE1@4410` | `SK_WIF1GIGA9B2E` · `B7DE1@4410` | OCR이 `WiFi`를 `WIF1`로 읽음 | H2, H3 | P2-3 |
| `variants-27` | 아래 줄 메모 "0은 숫자" | `zero_cafe` · `c0ffee0909` | `zero_cafe` · `coffee0909` | OCR이 0을 o로 읽었고, 다음 줄 메모("※ 0은 모두 숫자")는 쓰지 않음 | F2 | P2-4 |
| `variants-07` | 포스트잇 마커, 살짝 기울임 | `hong_studio` · `hong0812` | — · `hong0812` | OCR이 `wifi`를 `wii`로 읽어 이름표를 못 찾음(`wii - hong_studio`) | D2, G2 | P2-5 |
| `sign3` | WIFI 제목 아래 ID / PW 두 열 | `momo_guest` · `hello1234` | `momo_guest` · `Ask our staff if it doesn't work` | OCR이 값 `hello1234`를 놓침 → PW 다음 줄 안내 문장을 비밀번호로 고름 | E6, F6 | P2-6 (+P4-2) |
| `variants-26` | 두 대역을 한 줄에 | `mint_house` 또는 `_5G` · `mint9090` | — · `mint9090` | `WiFi 2.4G 이름 /5G 이름` 한 칸을 여러 단어 값으로 보고 이름표 버림 | C3, D8 | P3-1 |
| `variety-10` | 문장형 | `Sunny_Cafe` · `sunny2024` | `Sunny.Cafe` · `sunny2024` | OCR이 밑줄을 마침표로 읽음 | H1 | P3-2 |
| `variants-04` | 값의 자간이 넓음 | `cozy_home` · `cozy2026` | `co_z_y_ho_me` · `cozy2026` | OCR이 글자 사이에 공백을 넣음(`co z y_ho me`) → 밑줄이 있으니 공유기 이름으로 보고 공백을 모두 밑줄로 | F4 | P3-3 |
| `variants-32` | 긴 비밀번호가 다음 줄로 넘어감 | `long_pw_cafe` · `abcdefgh12345678` | `long_pw_cafe` · `abcdefgh12` | 다음 줄로 넘어간 뒷부분(`345678`)을 잇지 않음 | E1, E6 | P3-4 |
| `variants-41` | 영문 문장 | `Harbor_Guest` · `harbor2026` | `Harbor Guest` · `harbor2026` | OCR이 밑줄을 공백으로 읽음, 단어 간격은 오히려 넓음(1.07×줄 높이) | F4, H1 | P3-5 |
| `variety-07` | 이름표 없는 두 줄 | `lunahouse7` · `b83kd02jq1` | `lunahouse7` · `b83kd02jql` | OCR이 끝의 1을 l로 읽음. 정답이 후보에도 없음 | K2, K3 | P4-1 |
| `variety-16` | O와 0이 섞임 | `OCEAN_0O` · `O0o0Ocean` | `0CEAN_00` · `00o00cean` | OCR이 O와 0을 서로 바꿔 읽음 | K3 | P4-1 |
| `variants-31` | O/0, I/l/1 혼동 | `HILL_TOP_10` · `l1Il0Oo2026` | `HILL_TOP_10` · `I1l0002026` | OCR이 한 글자를 빠뜨리고 나머지를 바꿔 읽음 | K2, K3 | P4-1 |
| `variants-45` | 층별 두 네트워크 | `floor1_cafe` 또는 `floor2_cafe` · `floors1212` | `floorl_cafe` · `floors1212` | OCR이 1을 l로 읽은 첫 이름을 고름 (같은 점수면 앞 이름) | I1, K3 | P4-1 |
| `variants-06` | 칠판 손글씨 | `chalk_cafe` · `chalk1234` | `chalk_cafe` · — | OCR이 PW 줄을 통째로 놓침 | A1 | P4-2 |
| `variants-28` | 같은 줄 메모 "← 0은 숫자" (영문 O도 섞임) | `loop_cafe` · `LOOP0909` | `loop_cafe` · — | OCR이 작은 메모가 붙은 PW 줄을 통째로 놓침 | A1 | P4-2 |
| `variants-08` | 한글 이름표 + 손글씨 값 | `dream_house` · `dream2580` | `dream_hou9e` · `drearm2580` | 손글씨체를 OCR이 잘못 읽음 | A1 | P4-3 |
| `variants-14` | 이모지 아이콘만 | `Sunrise_Inn` · `sunrise2026` | — · — | 이모지를 OCR이 글자로 읽어 값에 붙임(`al Sunrise_Inn`, `Psunrise2026`) | C1 | P4-3 |
| `variants-15` | 와이파이명 / 패스워드 | `nabi_hostel` · `nabi0505` | `nabihostel` · `nabi0505` | OCR이 밑줄을 통째로 빠뜨림 | A1 | P4-3 |
| `variants-46` | 손님용 / 직원용 | `guest_zone` · `guest3333` | `guestZone` · `guest3333` | OCR이 밑줄을 빠뜨리고 z를 Z로 읽음 | A1 | P4-3 |
| `variants-48` | 사무실 회의실 게스트 Wi-Fi | `Office_Guest_3F` · `visit2026#` | `OficeGuest 3F` · `visit2026#` | OCR이 f와 밑줄을 빠뜨림 | A1 | P4-3 |
<!-- known-failures:end -->

## 5. 개선 항목 (우선순위 순)

- **P1**: 작은 규칙 변경. 시제품으로 기대 효과를 확인했고 기존 테스트 324개가 그대로 통과했다. 바로 구현한다.
- **P2**: `OcrService`·fixture 로더까지 바꾸거나, 규칙이 크거나, 기존 테스트와 부딪혀 결정이 필요하다. 시제품으로 효과는 확인했다.
- **P3**: 시제품 없음. 오탐 위험이 커서 설계를 먼저 해야 한다.
- **P4**: OCR이 글자를 못 읽은 경우. 파서로는 못 고친다.

"고치는 fixture"는 시제품을 넣었을 때 통과로 바뀐 fixture다(항목 하나씩 따로 쟀다). 모든 항목에 공통인 회귀 검사는 6장.

### P1-1 구분자·이름표 모양 넓히기

- **고치는 fixture (5)**: `variants-17`, `variants-18` (구분자), `variants-35` (괄호 이름표), `variants-20` (값 앞 `:`), `variants-25` (`/PIN`).
- **구현 방향**:
  - `_separator`에 "공백이 뒤따르는 `.`"(`ID. x`, `PW. x`)과 화살표 글자 `▶ ► ▷ ▸ ➤ ➢ ☞ » ›`를 더한다.
  - `_tokenize`에서 칸 맨 앞의 `[…]`·`【…】`·`〔…〕`·`<…>`·`(…)` 안이 통째로 이름표면(`_matchLabel(inner, 0)?.valueStart == inner.length`) `inner : 나머지`로 바꾼다.
  - `_addDetached`에서 값 앞의 `:`·`=`·`：`·`;`·`|`를 뗀다.
  - `_tryLabel`의 `/` 처리에서 두 번째 이름표가 아니고 **다른 이름표도 아닌** 짧은 낱말(`[A-Za-z가-힣]{1,8}`, 뒤에 구분자)이면 이름표에 넣는다(`Password/PIN:`).
- **위험**: `.`을 구분자로 보면 문장 끝 마침표 뒤 값이 엉뚱하게 붙을 수 있다(`… password. 다음 문장`). `/낱말`이 다른 이름표를 삼키면 `ID/PW : a / b`가 깨진다 — 시제품 첫 판에서 실제로 깨졌고 "다른 이름표가 아니면" 조건으로 막았다.
- **회귀 검사**: 기존 `한 줄에 여러 라벨` 그룹(`ID/PW : x / y`, `구분자 없이 이어진 Network / PW`), `다양한 라벨 표현`, `검색으로 모은 실제 안내문 표기`(`Network → x`, `WIFI | x`). 새 단위 테스트: `ID. a_b\nPW. c1234567`, `WiFi ► a_b`, `[WIFI] a_b\n[PW] c1234567`, `Password/PIN: 12345678`, `ID/PW : a / b`(그대로), `No. 1234`(이름표 아님).

### P1-2 밑줄 옆 공백 지우기

- **고치는 fixture (2)**: `variety-06`, `variants-19`. P2-1과 함께면 `photo-variety-06-exif6`까지 3.
- **구현 방향**: `_cleanValue`에서 `\s*_\s*` → `_`. 이름표 판정(D8) 전에 적용되므로 `WIFI one_ line_cafe`도 이름표로 남는다.
- **위험**: 밑줄 앞뒤에 진짜 공백이 있는 이름·비밀번호(`a _ b`)는 거의 없지만 있으면 바뀐다. 하이픈까지 넓히면 `Cafe - Guest` 같은 이름이 바뀌므로 밑줄만 한다.
- **회귀 검사**: `밑줄을 공백으로 읽은 공유기 이름 (1.0.2 실패 사례)` 그룹(`KT_WIFI 5G_F3D6` 같은 부분 공백은 밑줄 옆 공백이 아니라 영향 없음), `밑줄을 공백으로 읽은 경우` 그룹. 새 테스트: `ID\tStudy _Room`, `WIFI one_ line_cafe / PW x1234567`.

### P1-3 화장실·현관 비밀번호 거르기

- **고치는 fixture (2)**: `variants-49`, `variants-50`. `variants-36`(숙소 안내, Wi-Fi와 현관 비밀번호가 함께)은 지금도 맞고 이 규칙 뒤에도 맞는다.
- **구현 방향**: 비밀번호 이름표 바로 앞이 `화장실|공동현관|현관|도어락|출입문|대문|주차장|사물함|보관함|택배함|금고`(+`문`)이면 `_segmentCell`에서 이름표로 보지 않고, `_wifiContext`를 볼 때도 이 구절을 빼고 본다.
- **위험**: 이 낱말 뒤에 진짜 Wi-Fi 비밀번호가 오는 표기(`현관 와이파이 비밀번호`)는 앞말이 바로 붙지 않으니 영향이 없지만, 낱말 목록을 넓힐수록 위험이 커진다. Wi-Fi 비밀번호와 함께 적힌 안내문은 Wi-Fi 쪽이 그대로 이겨야 한다.
- **회귀 검사**: `Wi-Fi와 관계없는 글은 인식하지 않는다` 그룹, fixture `variants-36`. 새 테스트: `화장실 비밀번호\n1234*` → 빈 결과, `공동현관 비밀번호 : #2580*` → 빈 결과, `WIFI : a_b\nPW : c1234567\n현관 비밀번호 : 1357*` → 비밀번호 `c1234567`.

### P1-4 이름표 없는 카드 모양 오탐 줄이기

- **고치는 fixture (2)**: `variety-23`, `variants-51`.
- **구현 방향**: `_cardLike`에서 이름이 `@`로 시작하면 아니고, 다른 줄이 `reservation|예약|order|주문|coupon|쿠폰|code|member(ship)|회원|follow (us)|팔로우|ticket|티켓|receipt|영수증`으로 시작하면 아니다. `_looksLikeSsid`에서 `@`로 시작하는 값을 뺀다.
- **위험**: 가게 이름 줄이 이 낱말로 시작하는 이름표 없는 카드(`ORDER COFFEE` / `cafe7` / `abc12345`)를 놓친다. 이름표 없는 두 줄 카드 자체가 추측이라 손실은 작다.
- **회귀 검사**: `이름표 없이 이름과 비밀번호 두 줄만 있는 안내문 (1.0.8 실패 사례)` 그룹(`CAFE LUNAHOUSE` 세 줄 카드가 그대로 맞아야 함), `Wi-Fi와 관계없는 글` 그룹, fixture `variety-07`·`variety-17~24`.

### P1-5 한 글자 이름 감점

- **고치는 fixture (1)**: `variants-09`.
- **구현 방향**: `_ssidFactor`에서 글자 수가 2 미만이면 ×0.2. 그러면 `파`가 빠지고 밑줄 모양 추측(G4)의 `maru_guest`가 뽑힌다.
- **위험**: 거의 없다(한 글자 Wi-Fi 이름은 드물다). 비밀번호에는 적용하지 않는다.
- **회귀 검사**: 전체 테스트. 새 테스트: 세로 이름표 모양 `와 ⇥ 비\n이 ⇥ a_b ⇥ 밀\n와이파 이 ⇥ 비밀번 호\n파 ⇥ 번\nc1234567`.

### P2-1 EXIF 회전 사진의 상자 좌표 바로 세우기

- **고치는 fixture (1~2)**: `photo-sign4-exif8`, P1-2와 함께면 `photo-variety-06-exif6`. 지금 통과하는 EXIF 사진 8장도 `layoutText`가 한 행으로 뭉개지지 않게 된다. 가장 위험한 실패(높은 신뢰도로 엉뚱한 값)라 P2 첫 번째로 둔다.
- **구현 방향**: `OcrService.recognizeFile(path)`에서 JPEG의 EXIF Orientation과 저장 크기를 읽고, 줄 상자를 1.9의 식으로 바꾼 뒤 `layoutRows`에 넘긴다(방향 3·6·8; 5·7은 거울상이라 드묾). 같은 함수(예: `uprightBox`)를 `ocr_service.dart`에 두고 `OcrFixture.toOcrResult()`도 fixture의 `image` 값으로 그 함수를 부르게 한다. 다른 길: 갤러리 사진도 `cropImageFile`처럼 `bakeOrientation`으로 똑바로 다시 저장한 뒤 인식(디코딩 비용).
- **위험**: 저장 크기를 잘못 읽으면 모든 상자가 틀어져 오히려 망가진다. 셔터 경로의 크롭 이미지는 이미 `bakeOrientation`을 거치므로 두 번 돌리면 안 된다 — EXIF가 없는 파일(크롭 결과)은 그대로 둔다.
- **회귀 검사**: fixture EXIF 사진 10장(방향 3·6·8, 이름표·값 같은 줄/다른 줄/표)과 원본 fixture의 결과가 같아야 한다. `ocr_layout_test.dart`, `integration_test/ocr_pipeline_test.dart`(기기).

### P2-2 단어 간격으로 OCR이 끼워 넣은 공백 가리기

- **고치는 fixture (3)**: `variants-01`, `variants-02`, `variants-03`. 실제 안내문에서 가장 흔할 실패 묶음이다(얇은·작은 글씨에서 밑줄이 사라짐).
- **구현 방향**: `OcrService`가 줄 글자를 단어 상자로 다시 잇되, 단어 사이 간격이 줄 높이의 0.12배보다 좁으면 보통 공백 대신 표시 글자(시제품은 U+2009)를 넣는다. 파서는 값을 정리할 때 표시 글자를 이름이면 `_`, 비밀번호면 빈 문자로 바꾼다(1.9의 간격 수치 참고: 밑줄 자리 0.03~0.05, 진짜 띄어쓰기 0.28~0.60). fixture에는 단어 상자가 이미 있으니 로더가 같은 lib 함수로 줄 글자를 만들면 다시 뽑지 않아도 된다.
- **위험**: 좁은 글꼴·작은 글씨에서 진짜 띄어쓰기가 좁게 잡히면 `Lemon House` 같은 이름에 밑줄이 생긴다. 기울어진 줄(`variants-11`)은 가로 간격이 왜곡될 수 있다. 표시 글자가 `normalizeOcrText`·불확실 글자 위치(K2)·투표기(L1, 글자 위치 다수결)에서 다른 글자로 섞이지 않게 해야 한다.
- **회귀 검사**: fixture `variants-43`(진짜 띄어쓰기 이름 `Momo Coffee Roasters`가 그대로여야 함), `sign3` 안내 문장, 단위 테스트 `일반 가게 이름의 공백은 그대로 둔다`. 문턱값을 바꿀 때는 fixture 전체의 간격 분포를 다시 본다.

### P2-3 통신사 공유기 이름 정규화

- **고치는 fixture (2)**: `variety-09`, `variants-22`.
- **결정 (2026-11-06, 운영자)**: `SK_WIF1GIGA`·`SK_WIFiGIGA`처럼 읽힌 SK 이름은 오인식이다. 실제 형식 `SK_WiFiGIGA`로
  고친 값을 1순위로 두고, 읽은 값은 후보로 남긴다.
- **구현 방향**:
  - KT — `^KT_?G[il1|]GA_?(2G|5G)_?(Wave2_?)?([0-9A-FOIL]{4})$`(대소문자 무시)이면 `KT_GiGA_<대역>_<Wave2_><16진수>`로
    고친 값을 +0.02로 넣는다(꼬리의 `O→0`, `I/L→1`).
  - SK — `^SK_?W[il1|]F[il1|]G[il1|]GA`(대소문자 무시)로 시작하면 그 접두어를 `SK_WiFiGIGA`로 바꾸고, 뒤(밑줄·16진수
    꼬리·`_5G`/`_2.4G`)는 읽은 그대로 둔 값을 +0.02로 넣는다. H3(16진수 꼬리 고침)보다 먼저 돌려야 고친 접두어에도
    꼬리 고침이 붙는다.
  - 기존 테스트 하나의 기대를 바꾼다: `통신사 공유기 이름의 16진수 꼬리`의
    `('SK_WIFiGIGA7COD_2.4G', 'SK_WIFiGIGA7C0D_2.4G')` → `('SK_WIFiGIGA7COD_2.4G', 'SK_WiFiGIGA7C0D_2.4G')`.
    읽은 값이 후보에 남는지 보는 검사는 그대로 둔다.
- **확인한 것 (시제품)**: 기존 테스트는 위 한 경우만 깨졌다(그 테스트는 반복문이라 첫 실패 뒤 경우가 가려지므로 16개
  경우를 따로 하나씩 돌려 모두 맞음을 봤다). `SK_WIF1GIGA9B2E→SK_WiFiGIGA9B2E`, `SK_WlFlGlGA1A2B_5G→SK_WiFiGIGA1A2B_5G`,
  `SKWiFiGIGA1A2B→SK_WiFiGIGA1A2B`, `SK_WIFiGIGA7COD_2.4G→SK_WiFiGIGA7C0D_2.4G`, `KT_GIGA5G_Wave2_4FIA→KT_GiGA_5G_Wave2_4F1A`,
  기존 16진수 꼬리 경우 6개, `SK WiFiGIGA 3A2B→SK_WiFiGIGA_3A2B`, 그리고 `SK_WiFiGIGA_3A2B`·`SK_WiFiGIGAHOME_5G`·
  `GIGABYTE_5G`·`MEGAGIGA2`는 그대로.
- **위험**: `KT_`·`SK`로 시작하는 가게 이름(`KT_momo_free`, `SKY_cafe`)은 모양이 달라 영향이 없다. 접두어만 고치므로
  16진수가 아닌 꼬리(`SK_WiFiGIGAHOME_5G`)와 이미 맞게 읽은 이름은 그대로다.
- **회귀 검사**: `KT GiGA 이름의 소문자 i`, `통신사 공유기 이름의 16진수 꼬리`(바꾼 기대 포함),
  `SK WiFiGIGA와 단어 속 giga는 건드리지 않는다`, `밑줄을 공백으로 읽은 공유기 이름` 그룹, fixture `variants-21`·
  `variants-22`·`variety-09`·`sign-sk-band`·`variety-08`.

### P2-4 비밀번호 아래 줄의 메모

- **고치는 fixture (1)**: `variants-27`.
- **구현 방향**: 이름표 없는 한글 줄이 "숫자 0/영문 O" 메모(F2의 `_digitZeroNote`/`_letterONote`)면, **바로 위 1~2행**의 비밀번호 후보에 F2와 같은 힌트를 적용해 +0.001로 넣는다(시제품은 행 제한 없이 모든 비밀번호 후보에 적용했다).
- **위험**: F2와 같다 — "0은 숫자" 메모가 있으면 영문 O까지 0으로 바뀐다(`LOOP0909` → `L0000909`; `variants-28`은 OCR이 그 줄을 놓쳐 확인 못 함). 메모 범위를 위 행으로 묶지 않으면 다른 줄의 메모가 섞인다.
- **회귀 검사**: `암호키 이름표와 비밀번호 뒤의 메모` 그룹. 새 테스트: `PW : coffee0909\n※ 0은 모두 숫자` → `c0ffee0909`(원래 값은 후보), 메모가 비밀번호보다 위에 있거나 멀리 있으면 그대로.

### P2-5 깨진 Wi-Fi 이름표 줄에서 이름 찾기

- **고치는 fixture (1)**: `variants-07`.
- **구현 방향**: G2의 짝. 이름표로 이름을 못 찾았고 비밀번호는 이름표로 찾았을 때(점수 0.9 이상), `짧은 영문·한글(2~6자) + 구분자 또는 공백 + 이름 모양 값(G4)` 한 칸짜리 행의 값을 이름 후보 0.55로 넣는다(`wii - hong_studio`).
- **위험**: 비밀번호가 이름표로 확실할 때만 켜지므로 작다. `Tel - 02_1234`처럼 이름 모양(밑줄)인 연락처 줄이 걸릴 수 있다 — G2처럼 연락처 이름표(`_contactLabel`)를 뺀다.
- **회귀 검사**: `자간이 넓거나 깨진 이름표` 그룹, `Wi-Fi와 관계없는 글` 그룹.

### P2-6 문장을 비밀번호로 고르지 않기

- **고치는 fixture**: 없음. `sign3`의 출력이 엉뚱한 문장(`Ask our staff if it doesn't work`) → 빈칸으로 바뀐다(OCR이 값을 못 읽어서 통과는 못 함). 사용자가 틀린 비밀번호로 연결을 시도하지 않고 직접 입력하게 된다.
- **구현 방향**: 떨어진 칸·다음 줄에서 가져온 비밀번호 값(`_addDetached`)이 3단어 이상이거나 `'`가 든 여러 단어면 버린다. 이름표 바로 뒤 값(E1)에는 적용하지 않는다.
- **위험**: 이름표 다음 줄에 띄어쓰기 든 비밀번호를 적은 안내문(드묾). 이름표 바로 뒤의 공백 든 비밀번호는 그대로다(`글자로만 된 문구는 띄어쓰기를 유지한다` 테스트).
- **회귀 검사**: `비밀번호 사이에 OCR이 넣은 공백` 그룹, `옆 포스터 글귀가 비밀번호 줄에 섞인 경우` 그룹. 이 항목을 넣으면 `sign3`의 `knownFailures` 사유를 "OCR이 값을 놓침, 비밀번호 없음"으로 바꾼다.

### P3-1 한 줄에 두 대역 이름 (시제품 없음)

- **대상**: `variants-26` (`WiFi 2.4G mint_house /5G mint_house 5G`).
- **방향**: D8(여러 단어면 이름표 버림) 전에, 이름 이름표 뒤 값이 `대역 이름 / 대역 이름` 꼴이면 `/`와 대역 표시로 나눠 첫 이름을 값으로, 나머지를 다음 칸으로 넘긴다. C3의 `_splitBands`가 `/5G`(앞 공백 없이 `/`)도 경계로 보게 한다.
- **위험**: 대역 표시 앞뒤의 공백·`/`가 이름의 일부인 경우(`iptime 5G 2F`)를 잘못 나눈다 — C3의 "양쪽이 완성된 이름일 때만" 조건을 그대로 쓴다.

### P3-2 이름 속 마침표 (시제품 없음)

- **대상**: `variety-10` (`Sunny.Cafe`).
- **방향**: 영문 단어 사이의 `.`을 `_`로 바꾼 후보를 더한다. 1순위로 올릴지는 실제 안내문 표본을 보고 정한다(진짜 마침표가 든 Wi-Fi 이름도 있다). 단어 간격(P2-2)처럼 기하 정보로 가를 수 있는지 먼저 본다.

### P3-3 자간 넓은 이름 (시제품 없음)

- **대상**: `variants-04` (`co z y_ho me`).
- **방향**: 한 값 안의 단어 상자들이 1~2글자짜리로 고르게 떨어져 있으면(자간 넓은 글씨) 공백을 모두 지운 값을 1순위로. 지금 F4는 밑줄이 하나라도 있으면 공백을 모두 밑줄로 바꾸므로, 자간 넓은 글씨로 보이면 F4보다 먼저 막는다.
- **위험**: `KT WIFI 5G F3D6`처럼 짧은 토큰이 많은 공유기 이름. 단어 상자 간격이 고른지(분산)로 가려야 한다.

### P3-4 줄바꿈된 비밀번호 잇기 (시제품 없음)

- **대상**: `variants-32` (`PW: abcdefgh12` / `345678`).
- **방향**: 비밀번호 바로 다음 행이 이름표 없는 ASCII 토큰 하나이고, 그 줄 상자의 왼쪽 끝이 비밀번호 값의 왼쪽 끝과 맞으면(들여 쓴 이어짐) 이은 값을 후보로. 텍스트만으로는 위험하니 줄 상자 좌표가 필요하다.
- **위험**: 비밀번호 아래 연도·층수·짧은 코드를 이어 붙인다.

### P3-5 넓은 간격의 밑줄 (시제품 없음)

- **대상**: `variants-41` (`Harbor Guest`, 간격 1.07×줄 높이).
- **방향**: P2-2를 넣은 뒤, 한 줄 안에서 다른 단어 간격의 두 배가 넘는 간격을 "빠진 글자" 후보로 본다.
- **위험**: 자간 넓은 글씨(`sign1`의 `ENJO Y YOUR COFFEE`, 단어 사이 1.0~1.14)와 겹친다.

### P4-1 OCR 글자 혼동 (파서로는 못 고침)

- **대상**: `variety-07`(1→l), `variety-16`(O↔0), `variants-31`, `variants-45`(1→l).
- **방향**: 1순위는 그대로 두고 결과 화면 후보를 넓힌다 — `withLookalikes`(K3)에 `l↔1↔I`를 더하면 `variety-07`의 `b83kd02jq1`이 후보에 나온다. 연결 실패 화면의 `confusableVariants`와 같은 표를 쓴다. Android에서는 주변 Wi-Fi 목록과 이름 후보를 맞춰 보는 방법도 있다(위치 권한 필요).
- **위험**: 후보가 많아지면 결과 화면이 복잡해진다. fixture 판정(1순위)은 바뀌지 않는다.

### P4-2 OCR이 줄을 통째로 놓침

- **대상**: `variants-06`, `variants-28`, `sign3`.
- **방향**: 이름이나 비밀번호 한쪽만 찾았을 때 대비를 높이거나 확대한 이미지로 한 번 더 인식해 빠진 쪽을 채운다(`fillMissing`과 같은 방식). 실시간 인식은 여러 프레임 투표(L1)로 이미 보완된다.
- **위험**: 인식 시간이 두 배가 된다. 전처리 이미지에서만 나온 값은 신뢰도를 낮춘다.

### P4-3 손글씨·이모지·특수 글꼴 오인식

- **대상**: `variants-08`, `variants-14`, `variants-15`, `variants-46`, `variants-48`.
- **방향**: 파서 쪽에서 할 수 있는 것은 `variants-14`의 아이콘 접두(`al `, 붙은 `P`)를 떼는 정도인데 오탐 위험이 크다. 이 묶음은 고치지 않고 회귀 감시용으로 둔다.

## 6. 회귀 검사 방법 (모든 항목 공통)

1. `flutter analyze && flutter test` — 기존 단위 테스트 324개와 fixture 검사가 함께 돈다. 각 항목의 "회귀 검사"에 적은 기존 그룹이 그 항목의 위험을 지키는 테스트다.
2. fixture 검사의 "알려진 실패 목록이 실제 결과와 같다"가 두 방향을 다 잡는다 — 고쳐진 fixture(목록과 이 문서 4장에서 지운다)와, 맞다가 틀리게 된 fixture(회귀).
3. 항목마다 위 "새 테스트"를 단위 테스트(`test/wifi_credential_parser_test.dart`)로 먼저 넣는다. fixture는 OCR 원문의 회귀 감시이고, 규칙의 경계는 단위 테스트로 정한다.
4. 항목 하나씩 넣고 fixture 차이를 본다(7장처럼). 한 항목이 다른 항목의 fixture를 깨지 않는지 보려면 `OCR_FIXTURE_REPORT`로 보고서를 뽑아 이전 보고서와 비교한다.
5. 기대값은 정상 인식으로 둔다. 규칙을 고치다 기존 테스트가 깨지면, 그 테스트의 기대가 오인식 모양을 정답으로
   고정한 것인지 먼저 본다 — 그렇다면 기대를 정상 인식 값으로 고치고(읽은 값은 후보에 남는지 검사), 아니라면 규칙을
   고친다. 지금 기존 단위 테스트에서 오인식 모양을 정답으로 둔 곳:
   - `통신사 공유기 이름의 16진수 꼬리`: `('SK_WIFiGIGA7COD_2.4G', 'SK_WIFiGIGA7C0D_2.4G')` — 꼬리의 `O`는 고치면서
     오인식 `WIFi`는 그대로 둠. 정상 인식 `SK_WiFiGIGA7C0D_2.4G`로 고친다(P2-3).
   - 확인할 것: `다른 통신사·공유기 이름도`의 `SK WiFiGIGA 3A2B` → `SK_WiFiGIGA_3A2B` — OCR이 넣은 공백 두 곳을 모두
     밑줄로 바꾼 기대다. 실제 SK 형식이 코드 주석·`_ispHexName`처럼 `SK_WiFiGIGA` + 16진수 4자(사이 밑줄 없음)라면
     정상 인식은 `SK_WiFiGIGA3A2B`이므로, 실제 형식을 확인해 맞으면 기대와 P2-3 규칙(접두어 뒤 공백·밑줄 처리)을 함께 고친다.
6. `OcrService`를 바꾸는 항목(P2-1, P2-2)은 fixture 로더가 같은 lib 함수를 쓰게 하고, 가능하면 `tool/ocr_dump.sh`로 다시 뽑아 원문이 그대로인지(단어 상자 외) 확인한 뒤 `integration_test/ocr_pipeline_test.dart`를 시뮬레이터에서 돌린다.

## 7. 시제품 측정 기록

파서(`wifi_credential_parser.dart`), `ocr_service.dart`, fixture 로더에 임시로 넣고 `flutter test`(기존 324개)와 fixture 검사를
돌린 뒤 되돌렸다. 커밋에는 들어 있지 않다. 기준: 통과 53/91.

| 항목 | 넣은 것 | 통과로 바뀐 fixture | 깨진 기존 테스트 |
|---|---|---|---|
| P1-1 | `.`·화살표 구분자 | `variants-17`, `variants-18` | 없음 |
| P1-1 | 괄호 이름표 | `variants-35` | 없음 |
| P1-1 | 떨어진 값 앞 `:` 떼기 | `variants-20` | 없음 |
| P1-1 | `/낱말` 이름표 (다른 이름표 아닐 때만) | `variants-25` | 없음 (조건 없이 넣은 첫 판은 `ID/PW : x / y`가 깨짐) |
| P1-2 | 밑줄 옆 공백 | `variety-06`, `variants-19` | 없음 |
| P1-3 | 화장실·현관 비밀번호 | `variants-49`, `variants-50` | 없음 |
| P1-4 | 카드 모양 오탐 | `variety-23`, `variants-51` | 없음 |
| P1-5 | 한 글자 이름 | `variants-09` | 없음 |
| P1 전체 | | 위 12개 (53 → 65) | 없음 |
| P2-1 | EXIF 좌표 (+로더) | `photo-sign4-exif8` | 없음 |
| P2-1 + P2-2 | EXIF + 단어 간격 (+로더) | `photo-sign4-exif8`, `variants-01`, `variants-02`, `variants-03` | 없음 |
| P2-3 | 첫 판: KT 정규화 + SK 이름 전체를 다시 씀(접두어 뒤 밑줄도 지움) | `variety-09`, `variants-22` | 3개 (`SK WiFiGIGA와 단어 속 giga는 건드리지 않는다`, `다른 통신사·공유기 이름도`, `16진수에 없는 O·I는 0·1로…`) |
| P2-3 | 보수판: KT 정규화 + SK는 숫자·세로선만 | `variety-09` | 없음 |
| P2-3 | **결정판**: KT 정규화 + SK 접두어만 `SK_WiFiGIGA`로, 뒤는 읽은 그대로 | `variety-09`, `variants-22` | 1개 — `16진수에 없는 O·I는 0·1로…`의 `SK_WIFiGIGA7COD_2.4G` 기대 (운영자 결정으로 바꿀 기대) |
| P2-4 | 아래 줄 메모 | `variants-27` | 없음 |
| P2-5 | 깨진 Wi-Fi 이름표 | `variants-07` | 없음 |
| P2-6 | 문장 거르기 | 없음 (`sign3` 비밀번호가 문장 → 없음) | 없음 |
| P1 + P2 전체 (P2-3은 보수판) | | 20개 (53 → 73), P1-2+P2-1로 `photo-variety-06-exif6`도 | 없음 |
| P1 + P2 전체 (P2-3은 결정판) | | 21개 (53 → 74) | 위 1개 (바꿀 기대) |
