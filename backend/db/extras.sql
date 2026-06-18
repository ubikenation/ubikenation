-- =====================================================================
-- U-BIKE — Extra columns & constraints (run after schema.sql).
-- Adds detailed rider info storage and enforces unique phone numbers so the
-- same person cannot open multiple accounts (email uniqueness is already
-- enforced by Supabase Auth).
-- =====================================================================

-- 1) Detailed rider info (personal + extra fields) stored as JSON.
alter table public.riders add column if not exists details jsonb;

-- 2) Enforce one account per phone number (anti-fraud).
--    Partial unique index ignores null/empty phones.
create unique index if not exists profiles_phone_unique
  on public.profiles (phone)
  where phone is not null and phone <> '';

-- 3) Helpful: index for finding a profile by mpesa number.
create index if not exists profiles_mpesa_idx on public.profiles (mpesa_number);
