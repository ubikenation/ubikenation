-- =====================================================================
-- U-BIKE — Extra columns & constraints (run after schema.sql).
-- Adds detailed rider info storage and enforces unique phone numbers so the
-- same person cannot open multiple accounts (email uniqueness is already
-- enforced by Supabase Auth).
-- =====================================================================

-- 1) Detailed rider info (personal + extra fields) stored as JSON.
alter table public.riders add column if not exists details jsonb;

-- 2) Enforce one account per phone number (anti-fraud).
--    First, clear duplicate phones (keep the earliest profile per phone) so the
--    unique index can be created. This only affects already-duplicated rows.
with dups as (
  select id, row_number() over (partition by phone order by created_at) as rn
  from public.profiles
  where phone is not null and phone <> ''
)
update public.profiles p
   set phone = null
  from dups
 where dups.id = p.id and dups.rn > 1;

--    Partial unique index ignores null/empty phones.
create unique index if not exists profiles_phone_unique
  on public.profiles (phone)
  where phone is not null and phone <> '';

-- 3) Helpful: index for finding a profile by mpesa number.
create index if not exists profiles_mpesa_idx on public.profiles (mpesa_number);
