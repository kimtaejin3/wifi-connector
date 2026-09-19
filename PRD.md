# PRD — Camera Wi-Fi Connector

## 1. 프로젝트 개요

카페, 음식점, 숙박시설 등에서 종이나 메뉴판에 적혀 있는 Wi-Fi 이름(SSID)과 비밀번호를 사용자가 직접 입력하지 않고,

**카메라로 촬영 → 텍스트 자동 인식 → Wi-Fi 정보 추출 → 연결 요청**

까지 할 수 있는 모바일 앱을 구현한다.

예시로 다음과 같은 안내문이 있다고 가정한다.

```text
FREE WIFI

Wi-Fi : cafe_momo_5G
Password : momo1234
```

사용자가 해당 안내문을 카메라로 비추면 앱에서 자동으로 다음 정보를 추출한다.

```text
SSID: cafe_momo_5G
Password: momo1234
```

이후 사용자가 **[Wi-Fi 연결]** 버튼을 누르면 OS의 공식 Wi-Fi API를 이용해 연결을 요청한다.

---

# 2. 핵심 가치

기존:

```text
Wi-Fi 안내판 발견
↓
SSID 확인
↓
설정 앱 실행
↓
Wi-Fi 목록에서 찾기
↓
비밀번호 기억 또는 복사
↓
입력
↓
연결
```

목표:

```text
Wi-Fi 안내판 발견
↓
카메라로 촬영
↓
[연결]
↓
OS 승인
↓
연결 완료
```

사용자가 긴 Wi-Fi 비밀번호를 직접 입력해야 하는 불편을 없애는 것이 핵심이다.

---

# 3. MVP 범위

## 반드시 구현

* Flutter 기반 iOS / Android 앱
* 카메라 실시간 Preview
* 촬영 기능
* OCR 텍스트 인식
* SSID 자동 추출
* Password 자동 추출
* 추출된 정보 확인/수정 UI
* Wi-Fi 연결 요청
* 연결 성공/실패 상태 표시
* OCR 재촬영
* 직접 SSID/PW 수정

## MVP에서 제외

* 회원가입
* 로그인
* 서버
* DB
* 클라우드 저장
* 사용자 행동 분석
* 광고
* 결제
* Wi-Fi 정보 공유
* 지도
* 매장 DB 구축
* LLM API
* 사진 서버 업로드

가능하면 **완전한 온디바이스 앱**으로 만든다.

---

# 4. 기술 스택

## Framework

Flutter

가능하면 최신 Stable Flutter를 사용한다.

## OCR

Google ML Kit Text Recognition을 우선 사용한다.

OCR은 서버 API를 사용하지 않고 가능한 경우 온디바이스에서 실행한다.

목표:

```text
Camera Image
   ↓
ML Kit OCR
   ↓
Raw Text
   ↓
WiFi Credential Parser
   ↓
SSID + Password
```

---

# 5. 핵심 화면

앱을 실행하면 복잡한 홈 화면 없이 바로 카메라 화면이 나타난다.

```text
┌────────────────────────────┐
│                            │
│         Camera             │
│                            │
│      ┌──────────────┐      │
│      │ Wi-Fi 안내를 │      │
│      │ 비춰주세요   │      │
│      └──────────────┘      │
│                            │
│                            │
│      [    촬영    ]         │
│                            │
└────────────────────────────┘
```

촬영 후:

```text
┌────────────────────────────┐
│                            │
│      Wi-Fi를 찾았어요       │
│                            │
│  네트워크                   │
│ ┌────────────────────────┐ │
│ │ cafe_momo_5G           │ │
│ └────────────────────────┘ │
│                            │
│  비밀번호                   │
│ ┌────────────────────────┐ │
│ │ momo1234               │ │
│ └────────────────────────┘ │
│                            │
│      [ Wi-Fi 연결 ]         │
│                            │
│        다시 촬영            │
│                            │
└────────────────────────────┘
```

SSID와 Password input은 반드시 수정 가능하게 한다.

OCR이 틀렸을 경우 사용자가 직접 수정할 수 있어야 한다.

---

# 6. OCR 처리

이미지를 촬영하면 OCR을 실행한다.

예:

```text
WELCOME TO MOMO CAFE

WIFI
momo_cafe_5G

PASSWORD
momo1234

Enjoy!
```

Raw OCR Result:

```text
WELCOME TO MOMO CAFE
WIFI
momo_cafe_5G
PASSWORD
momo1234
Enjoy!
```

Credential Parser에 전달한다.

---

# 7. Wi-Fi Credential Parser

별도의 service로 구현한다.

예:

```text
wifi_credential_parser.dart
```

입력:

```dart
String rawText
```

출력:

```dart
class WifiCredential {
  String? ssid;
  String? password;
  double ssidConfidence;
  double passwordConfidence;
}
```

---

# 8. 지원해야 하는 표현

SSID 관련 Keyword:

```text
WiFi
Wi-Fi
Wifi
WI-FI
SSID
Network
Network Name
와이파이
와이파이 이름
네트워크
네트워크 이름
```

Password 관련 Keyword:

```text
Password
PASSWORD
PW
P/W
PASS
Passcode
Key
Wifi Password
WiFi PW
비밀번호
비번
암호
와이파이 비밀번호
와이파이 비번
```

---

# 9. Parser 기본 알고리즘

우선 LLM 없이 Rule-based로 구현한다.

### Case 1

```text
SSID: cafe_wifi
Password: 12345678
```

→

```text
ssid = cafe_wifi
password = 12345678
```

### Case 2

```text
WiFi
cafe_wifi

PW
12345678
```

→ Keyword 다음 줄을 값으로 판단.

### Case 3

```text
Wi-Fi : cafe_wifi
PW : 12345678
```

→ `:`, `=`, 공백을 기준으로 파싱.

### Case 4

```text
와이파이 cafe_wifi
비밀번호 abc12345
```

→ 한글 keyword 지원.

---

# 10. Candidate 방식

OCR 결과를 바로 확정하지 말고 Candidate를 만든다.

예:

```dart
class WifiCandidate {
  String value;
  WifiCandidateType type;
  double score;
}
```

예:

```text
WIFI
MOMO_GUEST
PASSWORD
hello1234
```

Candidate:

```text
MOMO_GUEST

SSID Score: 0.95
Password Score: 0.15
```

```text
hello1234

SSID Score: 0.1
Password Score: 0.97
```

최고 점수를 가진 candidate를 자동 선택한다.

---

# 11. 문자열 정리

OCR 오인식 때문에 다음 normalization을 수행한다.

앞뒤 공백 제거:

```text
" cafe_wifi "
→
"cafe_wifi"
```

Label 제거:

```text
"Password: hello1234"
→
"hello1234"
```

단, 비밀번호 자체는 변경하면 안 된다.

특히 다음 문자는 실제 비밀번호에 들어갈 수 있기 때문에 임의 제거 금지:

```text
!
@
#
$
%
&
*
_
-
.
```

대소문자도 절대 변경하지 않는다.

```text
CafeABC123
```

와

```text
cafeabc123
```

는 다른 비밀번호일 수 있다.

---

# 12. Wi-Fi 연결 Architecture

Flutter layer와 Native layer를 분리한다.

```text
Flutter UI

        ↓

WifiService

        ↓

Platform Channel

   ↙             ↘

Android          iOS
Native           Native

   ↓              ↓

Android WiFi     NetworkExtension
API              Framework
```

Flutter plugin으로 요구사항을 안정적으로 구현할 수 있다면 plugin을 사용할 수 있다.

다만 최신 OS에서 동작하지 않거나 maintenance 상태가 좋지 않은 package에 의존하지 않는다.

필요하면 직접 MethodChannel을 구현한다.

---

# 13. Android 구현

Android 11(API 30)+에서는 저장 가능한 Wi-Fi 네트워크 추가 UX에 `Settings.ACTION_WIFI_ADD_NETWORKS` 사용을 우선 검토한다.

사용자에게 Android 시스템 승인 UI를 표시한다.

대략적인 Native Flow:

```text
Flutter

↓

connectWifi(ssid, password)

↓

WifiNetworkSuggestion 생성

↓

ACTION_WIFI_ADD_NETWORKS

↓

Android System Dialog

↓

사용자 승인

↓

Wi-Fi 연결
```

Android에서 인터넷 접속용 Wi-Fi 연결에는 `WifiNetworkSpecifier`를 기본 선택으로 사용하지 않는다.

`WifiNetworkSpecifier`는 특정 AP/기기와의 로컬 연결 용도에 가까우며, 일반 인터넷 Wi-Fi 연결에는 Android 공식 가이드에 맞는 Saved Network / Suggestion 방식의 API를 사용한다.

Android 10과 이하 버전은 별도 호환성을 조사하여 처리하되 MVP에서는 현대 Android 버전을 우선한다.

---

# 14. iOS 구현

iOS에서는 NetworkExtension Framework를 사용한다.

핵심 API:

```swift
NEHotspotConfiguration
NEHotspotConfigurationManager
```

개념적으로:

```swift
let configuration = NEHotspotConfiguration(
    ssid: ssid,
    passphrase: password,
    isWEP: false
)

NEHotspotConfigurationManager.shared.apply(configuration)
```

사용자가 시스템에서 Wi-Fi 연결을 승인하도록 한다.

앱이 사용자의 승인 없이 강제로 Wi-Fi 설정을 변경하는 것을 목표로 하지 않는다.

---

# 15. 연결 UX

사용자가:

```text
[Wi-Fi 연결]
```

선택.

상태:

```text
연결 요청 중...
```

성공 시:

```text
✓ Wi-Fi 연결 요청이 완료되었습니다.
```

실패 시:

```text
Wi-Fi에 연결하지 못했습니다.

SSID 또는 비밀번호를 확인해주세요.

[다시 시도]
```

사용자가 OS에서 거절한 경우:

```text
Wi-Fi 연결이 취소되었습니다.

[다시 연결]
```

---

# 16. 중요한 OS 제약

이 앱의 목표는 OS 보안을 우회해서 Wi-Fi에 자동 접속하는 것이 아니다.

반드시 Android / iOS의 공식 API를 사용한다.

따라서 UX는 기본적으로:

```text
촬영
↓
OCR
↓
정보 추출
↓
연결 클릭
↓
OS 승인
↓
연결
```

형태로 설계한다.

OS가 승인 화면을 요구하면 그대로 노출한다.

---

# 17. Wi-Fi 종류

MVP에서는 다음만 지원한다.

### Open Wi-Fi

```text
SSID만 존재
```

지원.

### WPA / WPA2 Personal

```text
SSID + Password
```

지원.

### WPA3

Android/iOS API 지원 여부에 따라 가능한 범위에서 처리.

### Enterprise Wi-Fi

예:

```text
802.1X
ID
Password
Certificate
```

MVP 제외.

### Captive Portal

예:

```text
Wi-Fi 연결 후
브라우저 로그인
```

연결까지만 담당한다.

Portal 로그인 자동화는 하지 않는다.

---

# 18. SSID를 인식하지 못한 경우

예를 들어 종이에:

```text
Wi-Fi Password
hello1234
```

만 적혀 있을 수 있다.

이 경우 임의의 주변 네트워크에 바로 접속하면 안 된다.

UI:

```text
비밀번호를 찾았어요.

Password
hello1234

Wi-Fi 이름을 입력해주세요.

[                     ]

[연결]
```

MVP에서는 SSID를 사용자가 직접 입력하도록 한다.

---

# 19. V2 후보 기능

MVP가 안정적으로 동작한 다음 고려한다.

## 주변 Wi-Fi 기반 SSID 추천

Password만 OCR 된 경우 주변 Wi-Fi 정보를 이용하여 후보를 보여준다.

예:

```text
비밀번호: hello1234

주변 Wi-Fi

○ MOMO_CAFE
○ KT_GIGA_1234
○ iptime
```

사용자가 직접 선택한다.

OS별 Wi-Fi Scan 권한과 개인정보 제한을 준수한다.

---

# 20. V2 — AI/VLM 분석

Rule-based parser가 실패한 경우에만 AI fallback을 사용할 수 있도록 architecture를 설계한다.

예:

```text
OCR
↓
Rule Parser

confidence > 0.8
↓
바로 결과

confidence < 0.8
↓
AI Parser
```

AI 입력 예:

```json
{
  "text": "WELCOME MOMO WIFI MOMO5G FREE ACCESS CODE momo1234"
}
```

출력:

```json
{
  "ssid": "MOMO5G",
  "password": "momo1234",
  "confidence": 0.94
}
```

단 MVP에서는 구현하지 않는다.

---

# 21. Camera UX

실시간 Camera Preview 가운데 가이드 영역을 제공한다.

```text
┌──────────────────────────────┐
│                              │
│      Wi-Fi 안내문을           │
│      영역 안에 맞춰주세요      │
│                              │
│    ┌────────────────────┐    │
│    │                    │    │
│    │    Wi-Fi 안내문     │    │
│    │                    │    │
│    └────────────────────┘    │
│                              │
│          ● 촬영              │
│                              │
└──────────────────────────────┘
```

사용자가 무엇을 찍어야 하는지 즉시 이해할 수 있어야 한다.

---

# 22. Future — 실시간 인식

초기 MVP에서는 사진 촬영 후 OCR해도 된다.

V2에서는 실시간 OCR을 추가한다.

카메라에:

```text
WiFi: MOMO
PW: 12345678
```

가 보이는 순간:

```text
✓ Wi-Fi 정보 발견

MOMO

[연결]
```

Overlay를 띄운다.

---

# 23. UI Design

전체적인 디자인 방향:

* Minimal
* Modern
* 큰 Camera Preview
* 불필요한 설정 제거
* 한 화면 한 행동
* 흰색/검정 중심
* 연결 CTA 강조
* Material 3 기반
* iOS에서도 지나치게 Android스럽지 않도록 구성

사용자가 처음 실행했을 때 설명서를 읽지 않아도 사용할 수 있어야 한다.

---

# 24. 권한

필요한 권한만 요청한다.

## Camera

카메라 촬영용.

사용자가 카메라 기능을 실행할 때 요청.

## Wi-Fi 관련 권한

Android 버전에 따라 필요한 권한을 공식 문서를 기준으로 최소한으로 요청한다.

불필요한 위치 권한을 요구하지 않는다.

---

# 25. Privacy

사용자의 Wi-Fi Password는 민감 정보로 취급한다.

다음 원칙을 따른다.

```text
Wi-Fi Password 서버 전송 금지
Wi-Fi Password Analytics 전송 금지
Wi-Fi Password 로그 기록 금지
Wi-Fi Password Crash Report 포함 금지
```

예:

절대 금지:

```dart
print("wifi password = $password");
```

Production뿐 아니라 가능하면 Development log에서도 비밀번호 전체를 출력하지 않는다.

필요하면:

```text
Password detected: ********
```

정도로 masking한다.

---

# 26. Local Storage

MVP에서는 Wi-Fi 비밀번호를 저장하지 않는다.

앱 종료 후 Wi-Fi 정보를 자체적으로 보관하지 않는다.

향후 저장 기능을 추가하더라도 OS Keychain / Keystore를 사용해야 한다.

---

# 27. 에러 케이스

반드시 처리한다.

### OCR 실패

```text
Wi-Fi 정보를 찾지 못했어요.

안내문이 화면에 잘 보이도록 다시 촬영해주세요.

[다시 촬영]
```

### SSID만 발견

```text
Wi-Fi 이름은 찾았지만
비밀번호를 찾지 못했어요.

SSID
MOMO_CAFE

Password
[               ]

[연결]
```

### Password만 발견

```text
비밀번호는 찾았지만
Wi-Fi 이름을 찾지 못했어요.

SSID
[               ]

Password
hello1234

[연결]
```

### 잘못된 Password

```text
연결할 수 없습니다.

비밀번호를 확인해주세요.
```

### 연결 거절

```text
Wi-Fi 연결 요청이 취소되었습니다.
```

### Camera Permission 거절

```text
Wi-Fi 안내문을 촬영하려면
카메라 권한이 필요합니다.

[설정 열기]
```

---

# 28. Project Structure

가능하면 다음과 같이 구성한다.

```text
lib/
├── main.dart
│
├── core/
│   ├── constants/
│   ├── errors/
│   └── utils/
│
├── features/
│   └── wifi_scanner/
│       ├── data/
│       │   ├── models/
│       │   │   └── wifi_credential.dart
│       │   └── services/
│       │       ├── ocr_service.dart
│       │       └── wifi_service.dart
│       │
│       ├── domain/
│       │   └── services/
│       │       └── wifi_credential_parser.dart
│       │
│       └── presentation/
│           ├── screens/
│           │   ├── camera_screen.dart
│           │   └── wifi_result_screen.dart
│           │
│           └── widgets/
│
├── shared/
│   └── widgets/
│
android/
│
ios/
```

과도한 Clean Architecture는 사용하지 않는다.

작은 MVP에 적합한 수준으로만 구조화한다.

---

# 29. Parser Test

Wi-Fi parser에는 반드시 Unit Test를 작성한다.

예:

```text
SSID: MOMO_WIFI
Password: 12345678
```

Expected:

```json
{
  "ssid": "MOMO_WIFI",
  "password": "12345678"
}
```

---

다음 케이스:

```text
WIFI
MOMO_WIFI

PW
abc12345
```

Expected:

```json
{
  "ssid": "MOMO_WIFI",
  "password": "abc12345"
}
```

---

다음 케이스:

```text
와이파이 : 카페모모
비밀번호 : hello1234
```

Expected:

```json
{
  "ssid": "카페모모",
  "password": "hello1234"
}
```

---

다음 케이스:

```text
Free WIFI
Network MOMO_GUEST
Password Coffee!123
```

Expected:

```json
{
  "ssid": "MOMO_GUEST",
  "password": "Coffee!123"
}
```

대소문자와 특수문자가 보존되어야 한다.

---

# 30. 구현 우선순위

## Phase 1

Flutter 프로젝트 생성.

Camera Preview 구현.

촬영 가능 상태까지 만든다.

## Phase 2

ML Kit OCR 연결.

촬영한 사진에서 텍스트를 추출한다.

Debug 화면에서 Raw OCR Result를 확인한다.

## Phase 3

WifiCredentialParser 구현.

SSID / Password 자동 추출.

Unit Test 작성.

## Phase 4

Result Screen 구현.

SSID / Password 수정 가능.

Password show/hide 지원.

## Phase 5

Android Native Wi-Fi 연결 구현.

실제 Android 기기에서 검증.

## Phase 6

iOS Native Wi-Fi 연결 구현.

실제 iPhone에서 검증.

## Phase 7

권한 / 에러 처리.

## Phase 8

UI polish.

---

# 31. MVP 완료 조건

다음 시나리오가 실제 기기에서 동작하면 MVP 완료로 판단한다.

카페 테이블 위에 다음 종이를 둔다.

```text
FREE WIFI

SSID : TestCafe
Password : Test12345
```

앱 실행.

↓

카메라로 촬영.

↓

앱에서 다음 결과 표시.

```text
Network

TestCafe

Password

Test12345
```

↓

사용자가:

```text
Wi-Fi 연결
```

선택.

↓

Android 또는 iOS 공식 Wi-Fi 연결 Flow 실행.

↓

사용자 승인.

↓

해당 Wi-Fi 연결.

이 전체 과정이 정상적으로 동작해야 한다.

---

# 32. 구현 원칙

Claude Code는 다음 원칙을 따라 구현한다.

1. 먼저 현재 Flutter / Android / iOS 공식 API를 확인하고 deprecated API를 사용하지 않는다.
2. 동작 여부가 불확실한 Flutter Wi-Fi package에 무조건 의존하지 않는다.
3. 필요한 경우 MethodChannel을 이용하여 Native API를 직접 구현한다.
4. Wi-Fi 비밀번호를 로그에 남기지 않는다.
5. 서버를 만들지 않는다.
6. OCR은 가능한 한 온디바이스에서 처리한다.
7. 사용자의 Wi-Fi 데이터를 저장하지 않는다.
8. Android/iOS의 보안 정책을 우회하지 않는다.
9. OS가 사용자 확인을 요구하면 시스템 확인 UI를 그대로 사용한다.
10. 실제 기기 테스트를 기준으로 구현한다.
11. Simulator / Emulator에서 Wi-Fi 연결 기능이 정상적으로 테스트되지 않을 수 있으므로 실제 Android/iPhone 테스트 방법을 README에 작성한다.
12. 구현 중 발견한 OS별 제약 사항도 README에 기록한다.

---

# 33. Claude Code 실행 지시

위 PRD를 기준으로 Flutter MVP를 구현하라.

우선 전체 기능을 한 번에 구현하지 말고 다음 순서로 작업한다.

```text
1. Flutter 프로젝트 구조 생성
2. Camera 구현
3. OCR 구현
4. Wi-Fi Credential Parser 구현
5. Parser Unit Test
6. Result UI
7. Android Wi-Fi Native Integration
8. iOS Wi-Fi Native Integration
9. Error Handling
10. README 작성
```

각 단계가 완료될 때마다 build error와 lint error를 해결한 뒤 다음 단계로 넘어간다.

기존 코드가 있다면 먼저 프로젝트 구조와 dependency를 분석하고 기존 architecture를 최대한 유지한다.

불필요한 abstraction이나 premature optimization은 피한다.

목표는 **실제로 카페에서 꺼내 사용할 수 있는 최소한의 동작하는 MVP**다.
