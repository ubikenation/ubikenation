-- =====================================================================
-- U-BIKE — "last seen" tracking for the 48h re-login rule (Supabase-only)
-- Apply once in the Supabase SQL editor. Safe to re-run.
--
-- The apps stamp profiles.last_seen_at when opened (via the user's own RLS
-- self-update policy). On launch/resume they compare it to now: idle ≥ 48h ⇒
-- force a fresh sign-in; away > 1h ⇒ show "welcome back". No local database.
-- Until this column exists the apps simply keep users signed in (fail-open).
-- =====================================================================

alter table profiles add column if not exists last_seen_at timestamptz;
