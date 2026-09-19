/// 로그 등에 비밀번호를 남겨야 할 때 내용 대신 마스킹된 문자열을 쓴다.
/// 길이도 노출하지 않도록 항상 같은 길이로 표시한다.
String maskSecret(String? secret) {
  if (secret == null) return 'null';
  if (secret.isEmpty) return '(empty)';
  return '********';
}
