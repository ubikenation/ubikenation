-- =====================================================================
-- U-BIKE — Auto-create a profile (and wallet) for every new auth user.
-- Run this in the Supabase SQL Editor (after schema.sql).
--
-- WHY THIS MATTERS: trips.customer_id and riders.profile_id are foreign
-- keys to public.profiles(id). Without a profiles row, a signed-in user
-- cannot create a trip or register as a rider. This trigger guarantees the
-- row exists the moment they sign up, using the role/name/phone captured
-- in the app's signUp metadata.
-- =====================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, role, full_name, phone, mpesa_number, email)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'role', ''), 'customer')::user_role,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'phone',
    new.raw_user_meta_data ->> 'phone',
    new.email
  )
  on conflict (id) do update
    set full_name    = coalesce(excluded.full_name, public.profiles.full_name),
        phone        = coalesce(excluded.phone, public.profiles.phone),
        mpesa_number = coalesce(excluded.mpesa_number, public.profiles.mpesa_number),
        email        = excluded.email,
        role         = excluded.role;

  -- Seed an empty wallet so top-ups / earnings have a row to update.
  insert into public.wallets (profile_id) values (new.id)
  on conflict (profile_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill: create profiles for any existing auth users that don't have one yet.
insert into public.profiles (id, role, full_name, phone, mpesa_number, email)
select
  u.id,
  coalesce(nullif(u.raw_user_meta_data ->> 'role', ''), 'customer')::user_role,
  u.raw_user_meta_data ->> 'full_name',
  u.raw_user_meta_data ->> 'phone',
  u.raw_user_meta_data ->> 'phone',
  u.email
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null;
