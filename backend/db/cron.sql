-- =====================================================================
-- U-BIKE — Optional pg_cron scheduler (Supabase) for commuter plans + scheduled rides.
--
-- The backend ALREADY runs an in-process scheduler (ENABLE_SCHEDULER, default on),
-- which is enough for a single backend instance. Use this pg_cron job INSTEAD when
-- you run multiple backend instances (set ENABLE_SCHEDULER=false on them) so the
-- "due" work fires exactly once from the database every minute.
--
-- Prereqs (enable once in the Supabase dashboard → Database → Extensions):
--   - pg_cron
--   - pg_net   (for net.http_post)
-- Then set a CRON_SECRET env var on the backend and put the SAME value below.
-- Replace <BACKEND_URL> with your deployed backend origin (e.g. https://api.ubike...).
-- =====================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Remove a previous job with this name if re-running.
select cron.unschedule('ubike-run-due')
where exists (select 1 from cron.job where jobname = 'ubike-run-due');

-- Every minute: POST /api/plans/run-due with the shared cron secret.
select cron.schedule(
  'ubike-run-due',
  '* * * * *',
  $$
    select net.http_post(
      url     := '<BACKEND_URL>/api/plans/run-due',
      headers := jsonb_build_object(
                   'Content-Type', 'application/json',
                   'x-cron-secret', '<CRON_SECRET>'
                 ),
      body    := '{}'::jsonb
    );
  $$
);

-- To inspect / remove later:
--   select * from cron.job;
--   select cron.unschedule('ubike-run-due');
