-- 베타 테스터 신청 테이블 (Supabase 프로젝트 wifi-lens).
-- 변경 시 Supabase 대시보드 SQL Editor에 그대로 붙여 넣어 실행한다.
create table if not exists public.beta_testers (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  notify_consent boolean not null default false, -- 명단 추가 시 메일 알림 동의
  source text,
  user_agent text,
  added_at timestamptz,     -- Play 테스터 명단에 추가한 시각 (수기 등록 후 기록)
  notified_at timestamptz,  -- 알림 메일 보낸 시각
  created_at timestamptz not null default now()
);
alter table public.beta_testers enable row level security; -- 정책 없음: 서비스 키로만 접근
create index if not exists beta_testers_created_at_idx on public.beta_testers (created_at desc);

-- 이미 만들어진 테이블에 칸만 추가할 때
alter table public.beta_testers
  add column if not exists notify_consent boolean not null default false,
  add column if not exists added_at timestamptz,
  add column if not exists notified_at timestamptz;
