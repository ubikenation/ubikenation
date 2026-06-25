-- =====================================================================
-- U-BIKE — Optional: enforce unique full names (run in the Supabase SQL editor).
--
-- Phone numbers are ALREADY unique (extras.sql) and emails are unique via Supabase
-- Auth, so identity is already protected. This adds a case-insensitive unique name.
--
-- ⚠️ WARNING: real people DO share names (e.g. two "John Mwangi"). With this index,
-- the second person with an identical name cannot register. Apply only if you really
-- want that. Phone + email uniqueness is the safer anti-fraud control.
-- =====================================================================

-- Clear duplicate names first (keep the earliest), so the index can be created.
with dups as (
  select id, row_number() over (partition by lower(trim(full_name)) order by created_at) as rn
  from public.profiles
  where full_name is not null and trim(full_name) <> ''
)
update public.profiles p
   set full_name = full_name || ' (' || left(p.id::text, 4) || ')'
  from dups
 where dups.id = p.id and dups.rn > 1;

create unique index if not exists profiles_full_name_unique
  on public.profiles (lower(trim(full_name)))
  where full_name is not null and trim(full_name) <> '';
