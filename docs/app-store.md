# App Store 등록 정보 (와이파이 렌즈)

App Store Connect에 그대로 붙여 넣을 수 있게 정리한 문구입니다. 글자 수 제한은 괄호에 적었습니다.

## 앱 정보

| 항목 | 값 |
|---|---|
| 이름 (30자) | 와이파이 렌즈 |
| 부제 (30자) | 안내문 비추면 Wi-Fi 자동 연결 |
| 기본 카테고리 | 유틸리티 |
| 보조 카테고리 | 생산성 |
| 저작권 | 2026 Taejin Kim |
| 지원 URL | https://github.com/kimtaejin3/wifi-connector |
| 개인정보 처리방침 URL | https://github.com/kimtaejin3/wifi-connector/blob/main/docs/privacy.md |
| 마케팅 URL | 비워 둠 |

## 프로모션 텍스트 (170자, 심사 없이 수정 가능)

카페와 식당 벽의 Wi-Fi 안내문, 이제 비밀번호를 따라 치지 마세요. 카메라로 비추면 Wi-Fi 이름과 비밀번호를 읽고 바로 연결해 드려요.

## 설명 (4000자)

긴 Wi-Fi 비밀번호를 한 글자씩 옮겨 치던 번거로움을 없앴습니다.
카페, 식당, 숙소에 붙은 Wi-Fi 안내문을 카메라로 비추면 와이파이 렌즈가 네트워크 이름과 비밀번호를 찾아 바로 연결해 드립니다.

■ 비추기만 하면 끝
안내문을 화면 가운데 영역에 맞추면 셔터를 누르지 않아도 글자를 읽기 시작합니다. 여러 장면을 비교해 가장 정확한 값을 고르기 때문에 흔들려도 잘 읽습니다.

■ 다양한 안내문 형식
"Wi-Fi : 카페모모", "ID / PW", "비밀번호는 abc12345 입니다" 처럼 가게마다 다른 표기를 알아봅니다. 한글과 영문, 특수문자, 대소문자를 그대로 인식합니다.

■ 확인하고 연결
찾은 Wi-Fi 이름과 비밀번호를 보여 드리고, 틀린 글자가 있으면 바로 고칠 수 있습니다. 헷갈리기 쉬운 글자는 다른 후보로 함께 제안합니다.

■ 사진으로도 연결
미리 찍어 둔 안내문 사진을 갤러리에서 골라도 됩니다.

■ 연결한 Wi-Fi는 기록에
연결한 Wi-Fi 이름과 비밀번호가 기록 탭에 남아 언제든 다시 확인할 수 있습니다. 기록은 기기의 키체인에만 암호화되어 저장됩니다.

■ 개인정보를 밖으로 보내지 않습니다
글자 인식은 모두 기기 안에서 처리합니다. 회원가입도, 서버도 없고, 사진은 인식 직후 지웁니다. 위치 권한도 요청하지 않습니다.

※ Wi-Fi 연결은 iOS가 보여 주는 "Wi-Fi 네트워크에 연결하겠습니까?" 확인을 거쳐 이루어집니다.
※ 브라우저 로그인이 필요한 Wi-Fi는 연결 후 로그인 화면이 따로 나타납니다.

## 키워드 (100자, 쉼표로 구분, 띄어쓰기 없이)

와이파이,wifi,비밀번호,자동연결,카메라,OCR,카페,인식,스캔,무선인터넷,공유기,핫스팟,연결,QR

## 스크린샷

6.5″ 디스플레이용(1284×2778) 4장이 `store/`에 있습니다. App Store Connect의 "iPhone 6.5 디스플레이"에 순서대로 올립니다.

| 순서 | 파일 | 상단 문구 | 화면 |
|---|---|---|---|
| 1 | `store/s1.png` | 와이파이 안내문을 비추면 바로 연결할 수 있어요 | 카메라로 안내문을 비추고 "Wi-Fi 정보를 찾았어요" 배너 |
| 2 | `store/s2.png` | 와이파이 이름과 비밀번호를 정확하게 인식해요 | 결과 화면과 Wi-Fi 연결 버튼 |
| 3 | `store/s3.png` | 승인 한 번이면 연결 끝 | "Wi-Fi에 연결되었습니다" |
| 4 | `store/s4.png` | 연결한 와이파이는 기록에 남아요 | 기록 탭 |

모든 화면의 Wi-Fi 이름과 비밀번호는 예시 안내문(MomoCafe_5G / coffee2024!)으로 맞췄습니다.

## 연령 등급 설문

모든 항목 "없음" / "아니요" → **4+**

## 앱 개인정보 (App Privacy)

- 개발자가 데이터를 수집하나요? → **예**, 단 아래 한 항목만 (앱에 포함된 Google ML Kit SDK 때문)
  - **진단 → 성능 데이터 / 기타 진단 데이터**
    - 용도: 앱 기능
    - 사용자와 연결됨: 아니요
    - 추적에 사용: 아니요
- 그 밖의 데이터(연락처, 위치, 사진, 식별자 등)는 수집하지 않음

사진과 인식 글자는 기기 밖으로 나가지 않으므로 "사진 또는 비디오" 수집에 해당하지 않습니다.
ML Kit의 진단 정보 전송이 없다고 판단되면 "데이터를 수집하지 않음"으로 답해도 되지만, 보수적으로 위처럼 신고하는 것을 권장합니다.

## 심사 정보 (App Review 메모)

로그인 없음 (데모 계정 불필요)

메모 (2026-09-26 Guideline 2.1 요청에 따라 보강):

```
PURPOSE
Wi-Fi Lens reads a printed Wi-Fi sign (network name and password) with the camera and asks iOS to join that network, so people do not have to type long passwords at cafes, restaurants, hotels, and offices. No account, no login, no paid content, no user-generated content.

HOW TO TEST
1. Launch the app. The camera opens on the "안내문" (Sign) tab.
2. Point the camera at the attached test image (Wi-Fi : WifiLens_Test / PW : lens2026!). When the banner appears, tap "확인" (OK).
3. Check the name and password, tap "Wi-Fi 연결" (Connect Wi-Fi), and approve the iOS "Join Wi-Fi Network?" alert.
4. Or tap the photo button at the bottom left and choose a photo of a sign.
5. Networks that iOS accepted appear in the "기록" (History) tab.
iOS can only join a network that is in range. To see a successful join, create a hotspot named WifiLens_Test with the password lens2026!.

EXTERNAL SERVICES
- Google ML Kit Text Recognition, on-device only. Images and recognized text never leave the device.
- Apple NEHotspotConfigurationManager to request the join (the system alert always asks the user) and NEHotspotNetwork to confirm it. No location permission.
- Keychain for the on-device History list.
No server, authentication, payments, analytics, or AI/cloud services.

REGIONS
Works the same in all regions. Recognizes Korean and Latin text.

REGULATED CONTENT
Not applicable.
```

첨부: `test_signs/sign-hotspot.png`

## 수출 규정

앱은 암호화를 직접 쓰지 않으므로 `Info.plist`에 `ITSAppUsesNonExemptEncryption = NO`를 넣어 두었습니다. 빌드를 올릴 때마다 묻는 수출 규정 질문이 생략됩니다.
