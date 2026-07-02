-- =====================================================================
-- U-BIKE — FULL USER RESET  (run in the Supabase SQL editor)
-- Deletes ALL riders, customers and their data so you can start fresh with
-- real people. ADMIN accounts are KEPT so you can still sign in to the panel.
--
-- ⚠️  DESTRUCTIVE AND IRREVERSIBLE. This erases every trip, wallet, payment,
--     payout, rating, registration and user account (except admins). There is
--     no undo. Only run this before going live / when you truly want a clean slate.
-- =====================================================================

begin;

-- 1) Operational + financial data (all rows; children first for FK safety).
delete from chat_messages;
delete from ratings;
delete from rider_violations;
delete from payouts;
delete from escrow;
delete from payments;
delete from wallet_ledger;
delete from wallets;
delete from company_ledger;                 -- company wallet ledger
delete from public.commuter_plans;          -- recurring errand plans
delete from trips;
delete from vehicles;
delete from riders;
delete from public.device_tokens;           -- FCM push tokens

-- 2) Profiles — keep admins only.
delete from profiles where coalesce(role, '') <> 'admin';

-- 3) Auth users — delete everyone who no longer has a (kept admin) profile.
delete from auth.users
 where id not in (select id from profiles);

-- 4) Reset the founding program counters (10 free bike, 10 free car, 5 free errands).
update founding_program
   set enabled = true, bike_slots = 10, car_slots = 10, errands_slots = 5
 where id = 1;

commit;

-- Sanity check (should show only your admin accounts):
-- select id, email, role from profiles order by role;
-- select count(*) as auth_users from auth.users;

-- =====================================================================
-- OPTIONAL — also delete the admin accounts for a TOTAL wipe (you will then
-- have to re-create an admin and re-run make-admin). Uncomment to use:
--
--   delete from profiles;      -- removes admins too
--   delete from auth.users;    -- removes all remaining accounts
-- =====================================================================
