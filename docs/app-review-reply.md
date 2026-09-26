# App Review 답변 (Guideline 2.1 Information Needed, 1.0.0 빌드 2)

Apple이 요청한 것은 두 가지예요.

1. App Store Connect의 앱 심사 메시지에 답장하기: 아래 "답장 본문"과 화면 녹화 영상
2. 버전 페이지의 "앱 심사 정보 > 메모"에 같은 내용 넣기: `docs/app-store.md`의 메모 참고

## 화면 녹화 준비

- 녹화는 실제 iPhone으로 해요. iOS는 최신 버전이어야 해요.
- Galaxy에서 모바일 핫스팟을 켜고 이름을 `WifiLens_Test`, 비밀번호를 `lens2026!`로 설정해요.
- Mac 화면에 `test_signs/sign-hotspot.png`를 전체 화면으로 띄워요.
- iPhone 설정의 Wi-Fi에서 `WifiLens_Test`가 저장되어 있으면 "이 네트워크 설정 지우기"로 지워요.
- 제어 센터에 "화면 기록"이 없으면 설정 > 제어 센터에서 추가해요.

## 녹화 순서 (약 1분)

1. 홈 화면에서 화면 기록을 시작해요.
2. 홈 화면에서 와이파이 렌즈 아이콘을 눌러 앱을 실행해요. 녹화는 반드시 앱 실행 장면부터 시작해야 해요.
3. 카메라를 Mac 화면의 안내문에 비춰요. "Wi-Fi 정보를 찾았어요" 배너가 뜨면 "확인"을 눌러요.
4. 결과 화면에서 이름과 비밀번호를 보여 주고 "Wi-Fi 연결"을 눌러요.
5. iOS의 "Wi-Fi 네트워크에 연결하겠습니까?" 알림에서 "연결"을 눌러요.
6. "Wi-Fi에 연결되었습니다"가 뜨면 닫기를 눌러요.
7. 기록 탭에 `WifiLens_Test`가 남은 것을 보여 줘요.
8. 안내문 탭으로 돌아가 왼쪽 아래 갤러리 버튼을 눌러요. 안내문 사진을 골라 결과 화면이 뜨는 것까지 보여 줘요. 이 사진은 미리 찍어 두세요.
9. 화면 기록을 끝내요. 영상은 사진 앱에 저장돼요.

영상에 실제 집 Wi-Fi 이름이나 비밀번호, 알림 미리보기가 나오지 않게 해 주세요. 녹화 전에 집중 모드를 켜 두면 알림이 뜨지 않아요.

## 답장 본문 (그대로 복사해서 붙여 넣기)

```
Hello App Review Team,

Thank you for the review. Here is the requested information.

1. Screen recording
The attached recording was captured on a physical iPhone running the latest iOS. It starts from launching the app on the Home Screen and shows the full flow: pointing the camera at a Wi-Fi sign, confirming the recognized network name and password, joining the network through the system "Join Wi-Fi Network?" alert, the connection confirmation, and the History tab. Choosing a photo of a sign from the photo library (bottom-left button) leads to the same result screen.
The app has no account registration, login, user-generated content, or paid content.

2. Purpose and target audience
Wi-Fi Lens (와이파이 렌즈) helps people join Wi-Fi at cafes, restaurants, hotels, and offices, where the network name and password are printed on a sign. Instead of typing a long password by hand, the user points the camera at the sign. The app reads the network name and password, lets the user check or correct them, and asks iOS to join the network. The target audience is anyone who uses public or guest Wi-Fi, especially in Korea where printed Wi-Fi signs are common.

3. How to use the main features
No login or account is needed.
- Launch the app. The camera opens on the "안내문" (Sign) tab.
- Point the camera at a Wi-Fi sign such as the attached test image (Wi-Fi : WifiLens_Test / PW : lens2026!). When the banner appears, tap "확인" (OK).
- Review the network name and password, then tap "Wi-Fi 연결" (Connect Wi-Fi) and approve the iOS alert.
- Alternatively, tap the photo button at the bottom left and choose a photo of a sign.
- Networks that iOS accepted are listed in the "기록" (History) tab. Tapping one opens its name and password so it can be joined again.
Note: iOS can only join a network that is actually in range. To test a successful join, create a hotspot named WifiLens_Test with the password lens2026!, or use any nearby network and a sign showing its name and password.

4. External services, tools, and platforms
- Google ML Kit Text Recognition (on-device). Recognition runs entirely on the device. Camera frames, photos, and recognized text are never sent off the device.
- Apple NetworkExtension (NEHotspotConfigurationManager) to request joining the network, and NEHotspotNetwork to confirm the connection. The system alert always asks the user before joining.
- Keychain to store the History list on the device.
The app has no server, no authentication service, no payment processor, no analytics SDK, and no AI or cloud service.

5. Regional differences
The app works the same way in all regions. It recognizes Korean and Latin characters. There is no region-specific content or feature.

6. Regulated industry or third-party material
Not applicable. The app does not operate in a regulated industry and contains no protected third-party material.

Thank you.
```
