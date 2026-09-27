# google_mlkit_text_recognition 플러그인은 중국어·데바나가리·일본어 인식기도 참조하지만,
# 이 앱은 한국어(라틴 포함) 모델만 번들한다. 없는 클래스에 대한 R8 경고를 끈다.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
