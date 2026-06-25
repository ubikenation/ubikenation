-- =====================================================================
-- U-BIKE — Let customers remove trips from their history (soft delete).
-- Run in the Supabase SQL editor. A flag keeps the financial record intact
-- while hiding the trip from the customer's history list.
-- =====================================================================

alter table public.trips add column if not exists hidden_by_customer boolean not null default false;
