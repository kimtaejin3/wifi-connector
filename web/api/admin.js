// 관리용. ADMIN_TOKEN 헤더가 맞을 때만 동작한다.
//   GET  /api/admin?action=pending        → Play 명단에 아직 안 올린 이메일 목록
//   POST /api/admin {action:"added", emails:[...]}
//        → 해당 이메일에 added_at 기록, 동의한 사람에게 "명단 추가됨" 메일 1회 발송
const { sendAdded } = require('./_mail');

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  const token = req.headers['x-admin-token'];
  if (!process.env.ADMIN_TOKEN || token !== process.env.ADMIN_TOKEN) {
    res.statusCode = 401;
    return res.json({ ok: false, error: 'unauthorized' });
  }
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const headers = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
  const rest = (path, init = {}) => fetch(`${url}/rest/v1/${path}`, { ...init, headers: { ...headers, ...(init.headers || {}) } });

  let body = req.body;
  if (typeof body === 'string') { try { body = JSON.parse(body); } catch { body = {}; } }
  body = body || {};
  const action = (req.method === 'GET' ? req.query?.action : body.action) || 'pending';

  if (action === 'pending') {
    const r = await rest('beta_testers?added_at=is.null&select=email,notify_consent,created_at&order=created_at');
    return res.json({ ok: true, pending: await r.json() });
  }

  if (action === 'added') {
    const emails = [...new Set((body.emails || []).map((e) => String(e).trim().toLowerCase()).filter(Boolean))];
    if (!emails.length) { res.statusCode = 400; return res.json({ ok: false, error: 'no_emails' }); }
    const list = `(${emails.map((e) => `"${e}"`).join(',')})`;
    const now = new Date().toISOString();
    // 추가 시각 기록 (이미 기록된 건 그대로)
    await rest(`beta_testers?email=in.${list}&added_at=is.null`, {
      method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ added_at: now }),
    });
    // 동의했고 아직 알림을 받지 않은 사람에게만 발송
    const q = await rest(`beta_testers?email=in.${list}&notify_consent=is.true&added_notified_at=is.null&select=email`);
    const targets = q.ok ? await q.json() : [];
    const sent = [], failed = [];
    for (const { email } of targets) {
      try {
        if (await sendAdded(email)) {
          await rest(`beta_testers?email=eq.${encodeURIComponent(email)}`, {
            method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ added_notified_at: new Date().toISOString() }),
          });
          sent.push(email);
        } else failed.push(email);
      } catch { failed.push(email); }
    }
    return res.json({ ok: true, marked: emails.length, sent, failed });
  }

  res.statusCode = 400;
  return res.json({ ok: false, error: 'unknown_action' });
};
