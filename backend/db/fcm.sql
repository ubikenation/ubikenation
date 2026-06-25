-- =====================================================================
-- U-BIKE — FCM device tokens (run in the Supabase SQL editor).
-- Stores each user's push tokens so the backend can notify riders of new
-- requests and customers when a rider is found / arriving.
-- =====================================================================

create table if not exists public.device_tokens (
  id         uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  token      text not null unique,
  platform   text,                         -- 'android' | 'ios' | 'web'
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_device_tokens_profile on public.device_tokens (profile_id);

drop trigger if exists trg_device_tokens_updated on public.device_tokens;
create trigger trg_device_tokens_updated before update on public.device_tokens
  for each row execute function set_updated_at();

-- RLS: a user manages only their own device tokens (backend service-role bypasses).
alter table public.device_tokens enable row level security;
drop policy if exists device_tokens_self on public.device_tokens;
create policy device_tokens_self on public.device_tokens
  for all using (auth.uid() = profile_id) with check (auth.uid() = profile_id);
