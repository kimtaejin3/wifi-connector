# 와이파이 렌즈 (Camera Wi-Fi Connector)

카페·음식점·숙소의 Wi-Fi 안내문을 카메라로 찍으면 SSID와 비밀번호를 자동으로 인식하고,
OS 공식 Wi-Fi API로 연결을 요청하는 Flutter 앱입니다. 요구사항은 [PRD.md](PRD.md)를 참고하세요.

```text
앱 실행 → 안내문에 카메라 비춤 → (온디바이스 OCR, 여러 프레임 다수결) → 확인/수정 → [Wi-Fi 연결] → OS 승인 → 연결
```

- 서버, 로그인, DB, 분석 도구 없음
- OCR은 Google ML Kit으로 기기 안에서만 처리 (한국어 + 라틴 문자)
- Wi-Fi 비밀번호는 로그로 남기지 않음. 인식 기록은 OS Keychain/Keystore에만 저장
- 하단 메뉴: **안내문**(문자 인식) · **기록**(인식해서 연결한 Wi-Fi)

## 개발 환경

| 항목 | 버전 |
|---|---|
| Flutter | 3.47 stable (Dart 3.13) |
| Android | minSdk 24, targetSdk 36 · Wi-Fi 연결은 Android 10(API 29)+ |
| iOS | 15.5+ (ML Kit 요구사항) · Xcode 26 |

주요 의존성: [`camera`](https://pub.dev/packages/camera), [`google_mlkit_text_recognition`](https://pub.dev/packages/google_mlkit_text_recognition),
[`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage), [`image`](https://pub.dev/packages/image).
Wi-Fi 연결은 유지보수 상태가 불확실한 Flutter 패키지 대신 MethodChannel로 네이티브 API를 직접 호출합니다.

```bash
flutter pub get
flutter analyze
flutter test                                   # Parser / 검증기 / 결과 화면 테스트
flutter test integration_test -d <device-id>   # 실제 ML Kit OCR → Parser (기기/에뮬레이터)
flutter run                                    # 실제 기기 연결 후
```

`integration_test/ocr_pipeline_test.dart`는 카메라 대신 안내문 이미지를 그려서 ML Kit으로 인식시키고,
좌표 기반 행 재구성과 Parser까지 거친 결과를 검증합니다 (영문/한글/2열 레이아웃/특수문자).

## 프로젝트 구조

```text
lib/
├── main.dart                         # 앱 진입점, 세로 고정, 한국어 로케일
├── core/
│   ├── theme/app_theme.dart          # 흰색/검정 Material 3 테마
│   └── utils/
│       ├── platform_channel.dart     # 네이티브 채널, 앱 설정 열기
│       ├── secret_mask.dart          # 로그용 비밀번호 마스킹
│       └── text_normalizer.dart      # 전각 문자·특수 대시 등 OCR 변형 정규화
└── features/wifi_scanner/
    ├── data/
    │   ├── models/
    │   │   ├── wifi_credential.dart        # WifiCredential, WifiCandidate
    │   │   └── saved_wifi.dart             # 인식 기록 한 건
    │   └── services/
    │       ├── camera_frame.dart           # 프리뷰 프레임 → ML Kit InputImage (형식·회전)
    │       ├── image_cropper.dart          # 가이드 영역 → 사진 좌표 변환, 크롭
    │       ├── ocr_service.dart            # ML Kit OCR (한국어+라틴) + 좌표 기반 행 재구성 + 글자 신뢰도
    │       ├── wifi_history_store.dart     # 인식 기록 (Keychain/Keystore)
    │       └── wifi_service.dart           # connectWifi / awaitConnection MethodChannel 래퍼
    ├── domain/services/
    │   ├── credential_voter.dart           # 여러 프레임 결과의 글자 단위 다수결
    │   ├── wifi_credential_parser.dart     # rule-based SSID/Password 파서 + 결과 병합
    │   ├── wifi_credential_extractor.dart  # 인식기별 결과 우선순위, 불확실 글자 후보
    │   └── wifi_input_validator.dart       # SSID 32바이트, WPA 8~63자 검증
    └── presentation/
        ├── screens/
        │   ├── home_shell.dart             # 하단 메뉴 (안내문 · 기록)
        │   ├── camera_screen.dart          # 안내문 인식: 프리뷰 + 실시간 인식 + 촬영
        │   ├── history_screen.dart         # 인식 기록 목록
        │   └── wifi_result_screen.dart     # 확인 → [수정하기] → 연결/에러 표시
        └── widgets/
            ├── credential_card.dart        # SSID/비밀번호 카드 (읽기 전용 ↔ 편집)
            └── live_result_banner.dart     # 실시간 인식이 안정됐을 때 뜨는 카드

android/app/src/main/kotlin/.../WifiConnectorPlugin.kt   # Android Wi-Fi 연결
ios/Runner/WifiConnectorPlugin.swift                     # iOS Wi-Fi 연결
```

## 동작 방식

### OCR

1. `camera`로 사진 촬영 (1080p, 오디오 없음). 초점·노출은 가이드 영역 중앙에 맞추고, 화면을 탭하면 그 지점에 다시 맞춥니다.
2. 사진에서 **정사각형 가이드 영역만 잘라냅니다** (`image_cropper.dart`, 사방 8% 여유). 메뉴판 등 주변 글자가 후보에 섞이지 않고 인식도 빨라집니다.
3. ML Kit **한국어 인식기와 라틴 인식기를 동시에** 실행합니다. 한국어 모델도 영문을 읽지만, 영문·숫자만 있는 안내문은 라틴 전용 모델이 더 정확합니다.
4. 인식 결과의 줄 좌표를 이용해 **같은 높이의 줄을 한 행으로 재구성** (셀 사이는 탭).
   라벨 열과 값 열이 떨어져 있는 안내문(`Wi-Fi      cafe_momo`)을 올바르게 짝짓기 위해서입니다.
5. 두 인식기 결과를 각각 파싱해 병합합니다. SSID나 비밀번호 중 하나라도 못 찾았으면 (안내문이 가이드보다 커서 잘렸을 수 있으므로) 전체 사진으로 한 번 더 인식해 빠진 값을 채웁니다. 가이드 안에서 찾은 값이 우선입니다.
6. 촬영한 사진과 크롭 파일은 인식 직후 삭제
7. 카메라 화면의 갤러리 버튼으로 이미 찍어 둔 안내문 사진을 골라 인식할 수도 있습니다 (`image_picker`, 사진 전체 인식, 사본은 인식 직후 삭제)

### 실시간 인식과 다수결 (`CredentialVoter`)

프리뷰가 켜져 있는 동안 약 0.35초마다 프레임을 두 인식기에 넣고, 가이드 영역 안의 줄만 파서에 넘겨
SSID/비밀번호 판독을 최근 8개까지 모읍니다. 같은 길이의 판독끼리 **글자 위치별 다수결**로 값을 정하므로
`@`를 어떤 프레임에서 `0`으로 읽어도 다른 프레임들이 `@`로 읽으면 `@`가 됩니다.

- 3개 이상 프레임이 기여하고 모든 글자의 일치율이 60% 이상이면 "Wi-Fi 정보를 찾았어요" 카드가 떠서 셔터 없이 넘어갈 수 있습니다.
- 셔터를 누르면 고해상도 사진(가이드 크롭)의 결과에 두 표를 주고 실시간 판독과 합칩니다.
- 일치율이 75% 미만인 글자 자리에는 대체 후보를 만들어 "후보" 칩으로 보여줍니다.

### Parser (`WifiCredentialParser`)

LLM 없이 규칙 기반으로 동작하며, 결과를 바로 확정하지 않고 **후보(Candidate)와 점수**를 만든 뒤
타입별 최고 점수 후보를 선택합니다. 다른 후보는 결과 화면에 "후보" 칩으로 보여줍니다.

| 지원 형식 | 예시 |
|---|---|
| 라벨 + 구분자 | `SSID: cafe`, `Wi-Fi : cafe`, `PW = 1234`, `SSID：cafe` |
| 라벨 + 공백 | `Network MOMO_GUEST`, `와이파이 cafe_wifi` |
| 라벨 다음 줄에 값 | `WIFI` ↵ `MOMO_WIFI` |
| 같은 행의 다른 셀 | `Wi-Fi` ⇥ `cafe_momo` |
| 한 줄에 여러 라벨 | `ID : momo  PW : 1234`, `Network: My Cafe PW: 1234` |
| 라벨 묶음 | `ID/PW : momo / 1234`, `ID / PW` ↵ `momo / 1234` |
| 표 형태 | `SSID  PASSWORD` ↵ `cafe_5G  12345678` |
| 보조 표기 | `Wi-Fi (5G) :`, `비밀번호 (Password) :`, `PW (대소문자 구분) :` |

- SSID 라벨: WiFi, Wi-Fi, WI-FI, SSID, Network, Network Name, ID, WIFI ID, 와이파이, 와이파이 이름, 네트워크, 네트워크 이름 (`Wl-Fi`, `SSlD` 같은 OCR 오인식 포함)
- 비밀번호 라벨: Password, PW, P/W, PWD, PASS, Passcode, Key, Wifi Password, WiFi PW, Passward, 비밀번호, 비번, 암호, 패스워드, 와이파이 비밀번호/비번
- `FREE WIFI`, `FREE WIFI ZONE`, `WIFI 비밀번호 안내` 같은 제목은 값으로 쓰지 않음
- 라벨이 없어도 `KT_GIGA_5G`, `iptime` 같은 SSID 형태나 영문+숫자 8자 이상 값은 낮은 점수 후보로 추천
- 값 정리: 앞뒤 공백, 라벨, 공백 뒤 괄호 설명(`12345678 (숫자 8자리)`)만 제거.
  **대소문자와 특수문자(`!@#$%&*_-.`)는 절대 바꾸지 않음**
- OCR 노이즈 보정: 전각 문자(`Ｔｅｓｔ１２３４５`)·특수 대시·따옴표를 ASCII로, 글머리 기호(`•`, `▶`) 제거,
  `:`를 `;`나 `|`로 읽은 경우, `와이 파이`/`비밀 번호`처럼 라벨 안에 들어간 공백, `ID`를 `lD`로 읽은 경우,
  `비밀번호는 abc12345 입니다` 같은 조사·문장 종결. `비밀번호 : 없음`/`none`은 공개 네트워크로 인식합니다.
- 여러 인식기 결과 병합(`merge`): 같은 값은 높은 점수를 쓰고, 두 인식기가 각각 확신하는 값이 서로 다르면
  선택된 값의 신뢰도를 기준값 아래로 낮춰 "확인 필요"를 띄우고 다른 값을 후보 칩으로 남깁니다.
- 점수가 `WifiCredential.confidentThreshold`(0.8) 미만이면 화면에 "확인 필요"를 표시.
  V2의 AI Parser fallback은 이 기준값 아래에서만 호출하도록 붙이면 됩니다.
- 앱은 어느 쪽이 맞는지 알 수 없으므로 값을 고치지 않고, 대체 후보를 "후보" 칩으로 보여줍니다.

### Wi-Fi 연결

| 플랫폼 | API | 사용자 확인 |
|---|---|---|
| Android 11+ | `Settings.ACTION_WIFI_ADD_NETWORKS` + `WifiNetworkSuggestion` | 시스템 "네트워크 저장" 화면 |
| Android 10 | `WifiManager.addNetworkSuggestions` | 최초 1회 시스템 알림에서 허용 |
| Android 9 이하 | 미지원 → Wi-Fi 설정 열기 안내 | – |
| iOS | `NEHotspotConfigurationManager.apply` | 시스템 "Wi-Fi 연결" 알림 |

비밀번호가 비어 있으면 Open 네트워크, 있으면 WPA2 Personal(WPA2/WPA3 전환 모드 포함)로 요청합니다.
`WifiNetworkSpecifier`는 로컬 기기 연결용 API라 사용하지 않습니다.

채널 `com.kimtaejin.wifi_connector/platform`의 `connectWifi` 응답:

| status | 의미 | 화면 |
|---|---|---|
| `connected` | OS가 이미 연결됐다고 알려줌 (iOS `alreadyAssociated`) | ✓ Wi-Fi에 연결되었습니다. |
| `requested` (+`alreadySaved`) | OS가 요청을 수락. 이어서 `awaitConnection`으로 실제 연결 확인 | 요청 완료 · 연결 확인 중… |
| `suggested` | Android 10 제안 등록. 이어서 `awaitConnection` | 요청 완료 + 알림에서 허용 안내 |
| `cancelled` | 사용자가 OS 화면에서 거절 | Wi-Fi 연결이 취소되었습니다. [다시 연결] |
| `failed` + reason | `invalid_password` / `invalid_ssid` / `wifi_disabled` / `unsupported` / `unknown` | 사유별 안내 + [다시 시도] |

`awaitConnection` {ssid, timeoutMs} → {connected, captivePortal}:

| 결과 | 화면 |
|---|---|
| `connected: true` | ✓ Wi-Fi에 연결되었습니다. (캡티브 포털이면 브라우저 로그인 안내) |
| `connected: false` | 아직 연결을 확인하지 못했어요. + 대소문자/비밀번호 확인, `alreadySaved`면 설정에서 삭제 안내, [Wi-Fi 설정 열기], [다시 시도] |

- iOS: `apply()`는 사용자가 승인한 직후 **실제 접속 전에** 돌아오는 경우가 많아, `NEHotspotNetwork.fetchCurrent`로 현재 SSID를 0.5초 간격, 최대 20초 확인하고 붙는 즉시 표시합니다 (앱이 설정한 네트워크는 위치 권한 없이 조회됨). 적용 전에 이 앱이 같은 SSID로 저장했던 옛 설정은 지웁니다. 확인 시간이 6초였을 때 실기기에서 "확인 못 함 → 다시 누르면 연결됨" 현상이 있었습니다.
- Android: 위치 권한 없이는 SSID를 읽을 수 없어, 요청 **전에** `ConnectivityManager` 콜백을 등록해 현재 Wi-Fi 네트워크와
  기본 게이트웨이를 기억해 두고, 승인 뒤 최대 20초 안에 **게이트웨이가 다른 새 Wi-Fi 연결**이 생기면 연결된 것으로 봅니다.
  저장 직후 OS가 기존 네트워크를 끊었다 다시 붙이는 경우(에뮬레이터에서 실제로 발생)를 새 연결로 오인하지 않기 위한 조건입니다.
  게이트웨이가 우연히 같은 다른 AP(둘 다 `192.168.0.1` 등)는 "확인 못 함"이 되며, 이 메시지는 실패로 단정하지 않습니다.

### 결과 화면

인식 결과는 먼저 **읽기 전용 카드**로 보여주고 [Wi-Fi 연결]을 바로 누를 수 있습니다. 틀렸으면 [수정하기]로 같은 카드 안에서 편집합니다.
비밀번호는 숨기지 않고 그대로 보여줍니다 (안내문과 바로 비교하는 용도라 가리는 이점이 없습니다).
직접 입력이거나 SSID/비밀번호 중 하나가 빠졌으면 처음부터 편집 상태입니다.
OS가 연결 요청을 받아들이면 **기록** 탭에 저장됩니다 (SSID당 한 건, 최대 50건, Keychain/Keystore).

## 인식률·연결 오류를 줄이기 위한 조치

| 문제 | 조치 | 위치 |
|---|---|---|
| 사진 전체를 인식해 메뉴·장식 글자가 후보에 섞임 | 가이드 영역만 크롭해 인식, 빠진 값이 있으면 전체 사진으로 보충 | `image_cropper.dart`, `camera_screen.dart` |
| 영문·숫자(`l/1/I`, `O/0`) 오인식 | 한국어 + 라틴 인식기 동시 실행 후 병합. 불일치하면 "확인 필요" + 후보 칩 | `ocr_service.dart`, `wifi_credential_parser.dart#merge` |
| 초점이 안내문에 맞지 않아 흐리게 찍힘 | 초점·노출을 가이드 중앙에 고정, 탭 초점, 촬영 직전 진동 제거 | `camera_screen.dart` |
| 전각 문자·특수 대시 등 비ASCII 변형 | ASCII로 정규화 (뜻이 하나로 정해지는 문자만) | `text_normalizer.dart` |
| 문장형 안내문(`비밀번호는 … 입니다`), 글머리 기호, `;`/`\|` 구분자, 라벨 안 공백 | 파서 규칙 추가 | `wifi_credential_parser.dart` |
| "비밀번호 없음"을 비밀번호로 오인 | 공개 네트워크로 인식해 빈 비밀번호로 연결 | `wifi_credential_parser.dart`, 결과 화면 |
| 밑줄·하이픈을 놓치거나 기호 앞뒤에서 단어가 갈라짐 (`cafe_5G` → `cafe 5G`, `Coffee!123` → `Coffee! 123`) | 공백이 든 값마다 `_`, `-`, 공백 제거 후보를 만들고 "확인 필요" 표시. `5G` 같은 대역 표기 앞 공백은 밑줄을 기본값으로 | `wifi_credential_parser.dart` |
| 한국어 인식기가 기호를 자모/한자로 읽음 (`-`→`ㅡ`/`一`, `0`→`〇`, `#`→`井`) | ASCII로 정규화 | `text_normalizer.dart` |
| 어떤 글자가 잘못 읽혔는지 모름 | Android ML Kit의 글자별 신뢰도가 0.65 미만인 글자 자리에 대체 후보를 만든다 (iOS는 신뢰도를 주지 않음) | `ocr_service.dart#uncertainCharIndexes` |
| 한 장의 OCR 결과가 촬영마다 흔들림 (`@`↔`0`) | 프리뷰 프레임을 계속 인식해 글자 단위 다수결, 안정되면 셔터 없이 진행 | `credential_voter.dart`, `camera_screen.dart` |
| 불확실한 글자를 사용자가 일일이 고쳐야 함 | 신뢰도 낮은 글자 자리에 혼동 문자(`0`→`@/O/o`, `1`→`l/I/!` …)를 넣은 값을 후보 칩으로 제시 | `wifi_credential_extractor.dart#withSubstitutions` |
| "요청 완료"만 보여 실제 연결 여부를 모름 | 요청 뒤 실제 연결을 기다려 연결됨 / 확인 못 함 / 캡티브 포털을 구분 | `WifiConnectorPlugin.kt`, `WifiConnectorPlugin.swift` |
| 같은 SSID가 이미 저장돼 있어 비밀번호가 갱신되지 않음 (Android) | `ADD_WIFI_RESULT_ALREADY_EXISTS`를 구분해 설정에서 삭제하도록 안내 | `WifiConnectorPlugin.kt` |
| OS API가 거부할 입력 | SSID 32바이트, WPA 8~63자 ASCII를 요청 전에 검증 | `wifi_input_validator.dart` |

한계: 산세리프 글꼴의 대문자 `I`와 소문자 `l`처럼 사람도 구분할 수 없는 글자는 OCR도 구분하지 못합니다.
그래서 값을 자동으로 고치는 대신 강조 표시와 후보 칩으로 사용자가 확인하게 합니다.
SSID 대소문자 오류는 주변 Wi-Fi 목록과 대조해야 잡을 수 있는데, Android/iOS 모두 위치 권한 없이는 스캔이 안 돼 MVP에서 제외했습니다.

## 실제 기기 테스트

> **에뮬레이터/시뮬레이터로는 실제 Wi-Fi 연결을 검증할 수 없습니다.**
> - iOS 시뮬레이터: 카메라가 없고 `NEHotspotConfiguration`이 동작하지 않습니다. 게다가 ML Kit pod에
>   arm64 시뮬레이터 슬라이스가 없어 시뮬레이터 빌드는 x86_64로만 만들어지며,
>   **Apple Silicon Mac의 iOS 26+ 시뮬레이터에서는 실행되지 않습니다.** iOS는 실제 iPhone으로 개발하세요.
> - Android 에뮬레이터: 시스템 "네트워크 저장" 화면, 취소/저장 결과, Wi-Fi 꺼짐 처리까지는 확인할 수 있지만
>   가상 AP(`AndroidWifi`)만 있어 새 AP에 실제로 붙는지는 확인할 수 없습니다. 가상 카메라에는 안내문을 비출 수 없으므로
>   OCR은 `integration_test`로 확인합니다.
> - debug APK는 ML Kit 네이티브 라이브러리(모든 ABI) 때문에 약 180MB입니다. 에뮬레이터 저장 공간이 부족하면
>   `INSTALL_FAILED_INSUFFICIENT_STORAGE`가 나므로 여유 공간이 있는 AVD를 쓰세요. 배포는 ABI별로 나뉘는 App Bundle(`flutter build appbundle`)을 사용합니다.

#### Android 에뮬레이터(API 35)에서 확인한 항목

| 항목 | 결과 |
|---|---|
| 카메라 권한 요청 → 거절 → 권한 안내 화면, 재요청 반복 없음 | ✅ |
| [설정 열기] → 앱 설정 → 권한 허용 후 복귀 시 카메라 재시작 | ✅ |
| 텍스트 없는 장면 촬영 → "Wi-Fi 정보를 찾지 못했어요" → 직접 입력 | ✅ |
| [Wi-Fi 연결] → 시스템 "Save this network?" 화면 표시 | ✅ |
| 시스템 화면 Cancel → "Wi-Fi 연결이 취소되었습니다" / [다시 연결] | ✅ |
| 시스템 화면 Save → "Wi-Fi 연결 요청이 완료되었습니다", 저장 목록에 `TestCafe` 추가 | ✅ |
| 이미 저장된 네트워크 → 시스템이 화면 없이 "이미 있음" 반환 → 요청 완료 | ✅ |
| Wi-Fi 꺼짐 → "Wi-Fi가 꺼져 있어요" → [Wi-Fi 설정 열기]로 Wi-Fi 패널 표시 | ✅ |
| Flutter 로그 / logcat에 비밀번호 문자열 없음 | ✅ |
| ML Kit 한국어+라틴 모델로 안내문 이미지 인식 → Parser (integration test 5건, 가이드 밖 글자 제외 포함) | ✅ |
| 촬영 → 크롭 → 이중 인식 → 전체 사진 재시도까지 7초 (크롭 전 단일 인식은 20초 이상) | ✅ |
| 저장 승인 → "연결 확인 중…" → 새 연결이 없으면 "아직 연결을 확인하지 못했어요" + [Wi-Fi 설정 열기] | ✅ |
| 저장 직후 기존 Wi-Fi가 끊겼다 다시 붙는 경우를 새 연결로 오인하지 않음 (게이트웨이 비교) | ✅ |
| 승인 뒤 게이트웨이가 다른 새 Wi-Fi 연결 → "Wi-Fi에 연결되었습니다" | ❌ 에뮬레이터에는 AP가 하나뿐이라 실기기 확인 필요 |

#### iPhone 실기기(iOS 26.6.2)에서 확인한 항목

무료 Personal Team 제약 때문에 entitlement를 뺀 release 빌드로 확인했습니다.

| 항목 | 결과 |
|---|---|
| 카메라 프리뷰 / 가이드 영역 / 촬영 | ✅ |
| 인쇄체 안내문 OCR 인식 (한글·영문) | ✅ |
| 인식 결과가 결과 화면에 채워짐 | ✅ |
| Wi-Fi 연결 요청 | ⚠️ entitlement 없이 빌드해 실패 안내 표시 (예상된 동작) |
| 실제 AP 연결 | ❌ 미확인 — 유료 계정 필요 |

#### Android 실기기(Galaxy S24, Android 14)에서 확인한 항목

| 항목 | 결과 |
|---|---|
| 모니터에 띄운 안내문 촬영 → 인식 → [Wi-Fi 연결] → 시스템 저장 승인 → **실제 AP(휴대폰 핫스팟) 연결** | ✅ MVP 완료 조건 충족 |
| SSID의 밑줄(`_`)을 놓침 → 공백/밑줄 후보 제시로 대응 | ✅ 개선 적용 |

### 준비: 테스트용 안내문과 AP

1. 공유기나 휴대폰 핫스팟으로 테스트 AP를 만듭니다 (예: SSID `TestCafe`, 비밀번호 `Test12345`, WPA2).
2. 아래 내용을 종이에 인쇄하거나 크게 적습니다 (모니터 화면을 찍어도 됩니다).

   ```text
   FREE WIFI

   SSID : TestCafe
   Password : Test12345
   ```

3. 테스트 기기에서 해당 네트워크가 이미 저장되어 있다면 먼저 "저장 안 함/이 네트워크 지우기"로 삭제합니다.
4. `test_signs/`에 카페 안내문 스타일의 테스트 이미지 4장이 있습니다 (영문 콜론형, 한글, 2열 표, 라벨 아래 값).
   모니터에 전체 화면으로 띄우거나 인쇄해서 찍으면 됩니다. `sign1.png`가 위 안내문과 같은 내용입니다.

### Android

1. 기기에서 개발자 옵션 → USB 디버깅을 켜고 USB로 연결합니다.
2. `flutter devices`로 기기가 보이는지 확인 후 `flutter run` (릴리스 동작 확인은 `flutter run --release`).
3. 카메라 권한을 허용하고 안내문을 가이드 영역에 맞춰 촬영합니다.
4. 결과 화면에 `TestCafe` / `Test12345`가 표시되는지 확인하고 **Wi-Fi 연결**을 누릅니다.
5. Android 11+: 시스템 "이 네트워크를 저장하시겠습니까?" 화면에서 **저장**을 누르면
   앱에 "Wi-Fi 연결 요청이 완료되었습니다."가 표시되고, 기기가 해당 AP에 연결됩니다.
   Android 10: 상단 알림의 "제안된 Wi-Fi 네트워크 허용"을 눌러야 연결됩니다.
6. 추가로 확인할 것
   - 시스템 화면에서 취소 → "Wi-Fi 연결이 취소되었습니다." / [다시 연결]
   - Wi-Fi를 끈 상태 → "Wi-Fi가 꺼져 있어요." / [Wi-Fi 설정 열기]
   - 카메라 권한 거절 → 권한 안내 / [설정 열기] → 설정에서 허용 후 돌아오면 카메라가 다시 켜짐

### iOS

1. `open ios/Runner.xcworkspace`로 Xcode를 열고 Runner 타겟 → Signing & Capabilities에서 Team을 선택합니다.
   Bundle Identifier(`com.kimtaejin.wifiConnector`)가 이미 사용 중이라는 오류가 나면 고유한 값으로 바꿉니다.
2. **유료 Apple Developer Program 멤버십이 필요합니다.** `ios/Runner/Runner.entitlements`에 선언한
   Hotspot Configuration / Access WiFi Information은 무료 계정(Personal Team)으로 서명할 수 없습니다.
   Xcode가 다음 오류로 거부합니다 (Xcode 26에서 확인):

   ```text
   Cannot create a iOS App Development provisioning profile for "com.kimtaejin.wifiConnector".
   Personal development teams, including "...", do not support the
   Access Wi-Fi Information and Hotspot capabilities.
   ```

   무료 계정으로 카메라/OCR/화면만 먼저 확인하려면 `Runner.entitlements`의 두 키를 임시로 지우고 빌드하세요.
   이 경우 Wi-Fi 연결 요청은 실패합니다.
3. iPhone을 연결하고 설정 → 개인정보 보호 및 보안 → 개발자 모드를 켠 뒤 `flutter run`.
   처음 실행 시 설정 → 일반 → VPN 및 기기 관리에서 개발자 앱을 신뢰해야 할 수 있습니다.
   무료 계정은 기기당 개발 앱 3개까지만 설치할 수 있어, 한도를 넘으면 설치가
   `ApplicationVerificationFailed`로 실패합니다 (기존 개발 앱을 지우면 해결).
   홈 화면 아이콘으로 앱을 켜려면 release 빌드여야 합니다. debug 빌드는 iOS 14+에서
   Flutter 도구/Xcode로만 실행할 수 있습니다 (`flutter run --release`).
4. 안내문을 촬영하고 **Wi-Fi 연결**을 누르면 iOS가 "Wi-Fi 네트워크 'TestCafe'에 연결하겠습니까?" 알림을 띄웁니다.
   **연결**을 누르면 최대 5초 동안 실제 연결을 확인한 뒤 "Wi-Fi에 연결되었습니다."를 표시합니다.
5. 알림에서 취소 → "Wi-Fi 연결이 취소되었습니다." / 틀린 비밀번호 → iOS가 "연결할 수 없음" 알림을 띄우고
   앱은 연결을 확인하지 못해 "요청 완료 + 연결되지 않으면 비밀번호 확인" 안내를 표시합니다.

### MVP 완료 체크리스트

- [ ] 앱 실행 시 바로 카메라 화면과 가이드 영역이 보인다
- [ ] 위 안내문 촬영 시 Network `TestCafe`, Password `Test12345`가 표시된다
- [ ] 값을 수정할 수 있고 비밀번호 보기/숨기기가 동작한다
- [ ] [Wi-Fi 연결] → OS 승인 화면 → 승인 후 해당 Wi-Fi에 연결된다 (Android / iOS 각각)
- [ ] 거절, Wi-Fi 꺼짐, 권한 거절, 인식 실패 시 안내가 올바르게 표시된다

## OS별 제약 사항

### Android

- **연결된 SSID를 읽을 수 없음**: 현재 연결된 SSID를 읽으려면 위치 권한이 필요합니다.
  PRD 원칙(불필요한 위치 권한 금지)에 따라 요청하지 않으므로, 승인 뒤 "게이트웨이가 다른 새 Wi-Fi 연결"이
  생겼는지로만 연결을 판단합니다. 비밀번호가 틀리면 Android는 네트워크를 저장한 뒤 설정 화면에
  "인증 문제"로 표시하며, 앱은 20초 뒤 "아직 연결을 확인하지 못했어요"와 함께 비밀번호 확인과
  Wi-Fi 설정 열기를 안내합니다. 이미 그 네트워크에 붙어 있었거나 OS가 기존 네트워크를 유지하는 경우에도
  같은 메시지가 나오므로 실패로 단정하지 않습니다.
- `ACTION_WIFI_ADD_NETWORKS`로 추가한 네트워크는 사용자가 저장한 네트워크가 됩니다
  (설정 → Wi-Fi에 표시, 앱을 지워도 유지). **이미 저장된 네트워크면 OS가 확인 화면 없이 "이미 있음"만 돌려주고
  새로 연결을 시도하지 않습니다.** 이 경우 앱은 연결 확인을 기다리지 않고 "이미 저장된 네트워크예요"와
  Wi-Fi 설정 열기를 바로 안내합니다 (이미 붙어 있으면 그대로 쓰면 되고, 아니면 설정에서 선택해야 합니다).
- 다른 Wi-Fi에 연결된 상태에서는 OS가 새 네트워크로 즉시 전환하지 않을 수 있습니다.
- WPA2 설정으로 요청합니다. API 35 에뮬레이터에서는 저장된 네트워크가 `wpa2-psk` + `wpa3-sae`(자동 업그레이드)로
  등록되는 것을 확인했지만, **WPA3 전용(SAE only) AP**에 실제로 붙는지는 기기/OS 버전에 따라 다를 수 있어
  실기기 확인이 필요합니다. 보안 방식을 미리 알려면 Wi-Fi 스캔(위치 권한)이 필요해 MVP에서 제외했습니다.
- API 29+에서는 앱이 Wi-Fi를 켤 수 없어, 꺼져 있으면 Wi-Fi 패널(`Settings.Panel.ACTION_WIFI`)로 안내합니다.
- **Android 10**: `addNetworkSuggestions`는 최초 1회 알림 승인이 필요하고, 제안된 네트워크는 저장 목록에
  보이지 않으며 앱 삭제 시 함께 제거됩니다. 같은 SSID를 다시 제안하면 기존 제안을 지우고 다시 등록합니다.
- **Android 9 이하**: 앱에서 Wi-Fi를 추가하는 비-deprecated API가 없어 연결을 지원하지 않고 Wi-Fi 설정으로 안내합니다.
- 권한: `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`(모두 normal 권한, 런타임 요청 없음), `CAMERA`(camera 플러그인).
  위치 권한은 요청하지 않습니다. camera 플러그인이 선언하는 `RECORD_AUDIO`, 외부 저장소 권한은 쓰지 않으므로
  `AndroidManifest.xml`에서 `tools:node="remove"`로 제거했습니다. `INTERNET`/`ACCESS_NETWORK_STATE`는 ML Kit
  라이브러리가 선언합니다 (아래 개인정보 참고).

### iOS

- `NEHotspotConfigurationManager`는 Hotspot Configuration entitlement가 필요하고, 이 entitlement는
  **유료 Apple Developer Program 계정에서만** 서명할 수 있습니다 (무료 Personal Team 불가).
- `apply()`는 비밀번호가 틀려도 에러 없이 끝나는 경우가 있어, 완료 후 `NEHotspotNetwork.fetchCurrent`로
  현재 SSID를 최대 5회(1초 간격) 확인합니다. 앱이 직접 설정한 네트워크는 위치 권한 없이 조회되며
  Access WiFi Information entitlement가 필요합니다. 확인하지 못하면 실패로 단정하지 않고 "요청 완료"로 표시합니다.
- `joinOnce = false`로 설정해 앱이 백그라운드로 가도 연결이 유지되고 설정 → Wi-Fi에 저장됩니다.
- 앱에서 Wi-Fi 설정 화면으로 바로 이동하는 공개 API가 없고(`App-Prefs:`는 비공개 URL로 심사 거절 대상),
  Wi-Fi가 꺼져 있는지도 알 수 없습니다.
- WEP 네트워크는 지원하지 않습니다 (`isWEP: false`).
- ML Kit iOS 최소 버전 때문에 배포 타겟은 iOS 15.5입니다.

### 공통

- Enterprise(802.1X) Wi-Fi와 Captive Portal 로그인 자동화는 MVP 범위가 아닙니다. 연결까지만 담당합니다.
- WPA 비밀번호는 8~63자의 ASCII 문자여야 하므로, 이를 벗어나면 OS에 요청하기 전에 입력 오류로 안내합니다.

## 개인정보

- Wi-Fi 비밀번호를 서버·분석 도구·로그·크래시 리포트로 보내지 않습니다. 앱에 서버, 분석, 크래시 리포터가 없습니다.
- 인식 기록(SSID·비밀번호)은 `flutter_secure_storage`를 통해 Android Keystore / iOS Keychain에만 저장하며,
  기록 탭에서 건별로 또는 전부 지울 수 있습니다. 평문 파일이나 SharedPreferences에는 쓰지 않습니다.
- `WifiCredential`, `WifiCandidate`, `OcrResult`의 `toString()`은 비밀번호/원문을 마스킹합니다 (`********`).
- 촬영 사진은 OCR 직후 삭제하고, SSID/비밀번호를 앱에 저장하지 않습니다 (앱 종료 시 사라짐).
  향후 저장 기능을 추가한다면 Keychain / Keystore를 사용해야 합니다.
- 참고: ML Kit은 이미지나 인식 텍스트를 전송하지 않지만, Google 정책에 따라 API 사용량·성능 지표를
  Google에 보낼 수 있습니다 ([ML Kit 이용 약관](https://developers.google.com/ml-kit/terms)).

## V2 후보

- 비밀번호만 인식된 경우 주변 Wi-Fi 목록에서 SSID 선택 (Wi-Fi 스캔 권한 필요)
- 파서 신뢰도 0.8 미만일 때만 호출하는 AI/VLM fallback
- 카메라 스트림 실시간 인식 + 발견 시 오버레이
