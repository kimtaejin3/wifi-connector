# google_mlkit_text_recognition 플러그인은 중국어·데바나가리·일본어 인식기도 참조하지만,
# 이 앱은 한국어(라틴 포함) 모델만 번들한다. 없는 클래스에 대한 R8 경고를 끈다.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**

# Play 1.0.6(9)에서 카메라 프레임을 ML Kit에 넘길 때 매 프레임 NullPointerException이 나서
# 글자 인식이 전혀 되지 않았다 (디버그 빌드에서는 정상). ML Kit과 플러그인 코드는 축소·최적화하지 않는다.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-dontwarn com.google.mlkit.**
