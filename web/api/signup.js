// 베타 테스터 이메일 등록. Supabase의 beta_testers 테이블에 저장한다.
// 서비스 키는 Vercel 환경변수에만 있고 브라우저에는 내려가지 않는다.

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') {
    res.statusCode = 405;
    return res.json({ ok: false, error: 'method' });
  }

  let body = req.body;
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch { body = {}; }
  }
  body = body || {};

  // 봇이 채우는 숨은 칸. 값이 있으면 저장하지 않고 성공처럼 답한다.
  if (body.website) return res.json({ ok: true });

  const email = String(body.email || '').trim().toLowerCase();
  if (!EMAIL.test(email) || email.length > 254) {
    res.statusCode = 400;
    return res.json({ ok: false, error: 'invalid_email' });
  }

  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    res.statusCode = 500;
    return res.json({ ok: false, error: 'not_configured' });
  }

  const row = {
    email,
    source: String(body.source || 'web').slice(0, 40),
    user_agent: String(req.headers['user-agent'] || '').slice(0, 300),
  };

  // 같은 이메일이 이미 있으면 그대로 두고 성공으로 처리한다 (중복 등록 허용).
  const r = await fetch(`${url}/rest/v1/beta_testers?on_conflict=email`, {
    method: 'POST',
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
      Prefer: 'resolution=ignore-duplicates,return=minimal',
    },
    body: JSON.stringify(row),
  });

  if (!r.ok) {
    res.statusCode = 502;
    return res.json({ ok: false, error: 'storage' });
  }
  return res.json({ ok: true });
};
