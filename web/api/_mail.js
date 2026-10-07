// Play 테스터 명단에 추가된 신청자(알림 동의자)에게 Gmail(SMTP)로 설치 안내를 보낸다.
// GMAIL_USER / GMAIL_APP_PASSWORD 는 Vercel 환경변수. 앱 비밀번호가 없으면 보내지 않는다.
const nodemailer = require('nodemailer');

const TESTING_URL = 'https://play.google.com/apps/testing/com.kimtaejin.wifi_connector';
const STORE_URL = 'https://play.google.com/store/apps/details?id=com.kimtaejin.wifi_connector';

function configured() {
  return Boolean(process.env.GMAIL_USER && process.env.GMAIL_APP_PASSWORD);
}

function transport() {
  return nodemailer.createTransport({
    host: 'smtp.gmail.com',
    port: 465,
    secure: true,
    auth: { user: process.env.GMAIL_USER, pass: process.env.GMAIL_APP_PASSWORD },
  });
}

function addedText(email) {
  return `안녕하세요, 와이파이 렌즈입니다.
${email} 이 Google Play 테스터 명단에 추가됐어요. 이제 설치할 수 있어요!

1. 이 이메일의 Google 계정으로 로그인한 브라우저에서 아래 링크를 열고 "테스터 되기"를 눌러 주세요
   ${TESTING_URL}

2. 같은 계정으로 로그인된 안드로이드 휴대폰에서 아래 링크를 열어 설치해 주세요
   ${STORE_URL}

Google 정책상 베타 테스트는 14일 동안 진행돼요. 그동안 앱을 지우지 말고 가끔 열어서 써 봐 주세요.
인식이 안 되는 안내문이 있으면 이 메일에 답장으로 사진이나 상황을 보내 주시면 큰 도움이 돼요.

이메일 주소는 테스터 명단 등록과 안내에만 쓰고, 베타 테스트가 끝나면 지워요.
개인정보 처리방침: https://wifi-lens.vercel.app/privacy

와이파이 렌즈 드림`;
}

function addedHtml(email) {
  const esc = (s) => s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
  const link = (u) => `<a href="${u}" style="color:#5b67f1;word-break:break-all">${u}</a>`;
  return `<!DOCTYPE html><html lang="ko"><body style="margin:0;background:#f6f5fb;padding:24px 12px;font-family:-apple-system,'Apple SD Gothic Neo','Noto Sans KR',sans-serif;color:#1f2333;line-height:1.7">
<div style="max-width:560px;margin:0 auto;background:#fff;border-radius:16px;padding:28px 24px">
  <p style="margin:0;font-size:13px;font-weight:700;color:#5b67f1">와이파이 렌즈 · 안드로이드 베타</p>
  <h1 style="font-size:22px;margin:10px 0 8px">테스터 명단에 추가됐어요</h1>
  <p style="margin:0 0 20px;color:#6d7190"><b style="color:#1f2333">${esc(email)}</b> 이 Google Play 테스터 명단에 올라갔어요. 이제 바로 설치할 수 있어요.</p>
  <ol style="padding-left:20px;margin:0">
    <li style="margin-bottom:14px"><b>이 이메일의 Google 계정으로 로그인한 브라우저에서 아래 링크를 열고 "테스터 되기"를 눌러 주세요</b><br>${link(TESTING_URL)}</li>
    <li style="margin-bottom:14px"><b>같은 계정으로 로그인된 안드로이드 휴대폰에서 아래 링크를 열어 설치해 주세요</b><br>${link(STORE_URL)}</li>
  </ol>
  <div style="margin-top:20px;padding:14px 16px;background:#f6f5fb;border-radius:12px;font-size:14px">
    · Google 정책상 베타 테스트는 14일 동안 진행돼요. 그동안 앱을 지우지 말고 가끔 열어서 써 봐 주세요.<br>
    · 인식이 안 되는 안내문이 있으면 이 메일에 답장으로 사진이나 상황을 보내 주시면 큰 도움이 돼요.
  </div>
  <p style="margin:20px 0 0;font-size:12px;color:#6d7190">이메일 주소는 테스터 명단 등록과 안내에만 쓰고, 베타 테스트가 끝나면 지워요. <a href="https://wifi-lens.vercel.app/privacy" style="color:#6d7190">개인정보 처리방침</a></p>
</div></body></html>`;
}

/// 명단 추가 완료 알림. 동의한 신청자에게 보낸다.
async function sendAdded(email) {
  if (!configured()) return false;
  await transport().sendMail({
    from: `"와이파이 렌즈" <${process.env.GMAIL_USER}>`,
    to: email,
    replyTo: process.env.GMAIL_USER,
    subject: '[와이파이 렌즈] 테스터 명단에 추가됐어요. 이제 설치할 수 있어요',
    text: addedText(email),
    html: addedHtml(email),
  });
  return true;
}

module.exports = { sendAdded, configured };
