-- =====================================================================
-- U-BIKE — v2 flow migration (run after schema.sql + extras.sql).
-- Implements the Uber/Bolt-style ordering (match before payment), the
-- adjustment-based commission (20% normal / 25% when the rider adjusts),
-- two-way live location, recurring "commuter plans" for errands, and
-- richer rider/vehicle identity (car + number-plate photos).
--
-- Apply in the Supabase SQL editor (DDL — service_role JWT cannot ALTER TYPE).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) New trip_status values for the reordered lifecycle.
--    (ALTER TYPE ... ADD VALUE is idempotent via IF NOT EXISTS on PG12+.)
-- ---------------------------------------------------------------------
alter type trip_status add value if not exists 'quote_pending';
alter type trip_status add value if not exists 'awaiting_payment';
alter type trip_status add value if not exists 'awaiting_balance';
alter type trip_status add value if not exists 'scheduled';

-- ---------------------------------------------------------------------
-- 2) TRIPS — commission, adjustment flag, customer live location, and the
--    list of riders the customer has already passed on (for re-matching).
-- ---------------------------------------------------------------------
alter table public.trips add column if not exists commission_rate numeric(4,3);
alter table public.trips add column if not exists adjusted boolean not null default false;
alter table public.trips add column if not exists customer_lat double precision;
alter table public.trips add column if not exists customer_lng double precision;
alter table public.trips add column if not exists customer_location_at timestamptz;
alter table public.trips add column if not exists declined_rider_ids uuid[] not null default '{}';

-- ---------------------------------------------------------------------
-- 3) RIDERS — denormalised single-vehicle identity (bike/errand riders use
--    one vehicle; cars also use the vehicles table). Lets the customer app
--    fetch "rider + car + plate" in one read, Bolt-style.
-- ---------------------------------------------------------------------
alter table public.riders add column if not exists plate_number  text;
alter table public.riders add column if not exists plate_photo_url text;
alter table public.riders add column if not exists vehicle_make  text;
alter table public.riders add column if not exists vehicle_model text;
alter table public.riders add column if not exists vehicle_color text;

-- ---------------------------------------------------------------------
-- 4) VEHICLES — number-plate photo path (car riders may register several).
-- ---------------------------------------------------------------------
alter table public.vehicles add column if not exists plate_photo_url text;

-- ---------------------------------------------------------------------
-- 5) COMMUTER PLANS — recurring/subscription errands. Priced automatically
--    from the errand type + description at create time (re-estimated on edit).
-- ---------------------------------------------------------------------
do $$ begin
  create type commuter_frequency as enum ('daily','weekdays','weekly');
exception when duplicate_object then null; end $$;

do $$ begin
  create type plan_status as enum ('active','paused','cancelled');
exception when duplicate_object then null; end $$;

create table if not exists public.commuter_plans (
  id              uuid primary key default uuid_generate_v4(),
  customer_id     uuid not null references public.profiles(id) on delete cascade,
  errand_type     text not null,
  description     text not null default '',
  -- locations
  pickup_lat      double precision not null,
  pickup_lng      double precision not null,
  pickup_address  text,
  dropoff_lat     double precision,
  dropoff_lng     double precision,
  dropoff_address text,
  distance_km     numeric(8,2) not null default 0,
  duration_min    numeric(8,2) not null default 0,
  -- auto fare estimate (snapshot; per-run trips re-price at run time)
  fare_estimate   integer not null default 0,
  upfront_amount  integer not null default 0,
  balance_amount  integer not null default 0,
  -- schedule
  frequency       commuter_frequency not null default 'weekdays',
  time_of_day     time not null default '08:00',
  days_of_week    int[] not null default '{1,2,3,4,5}',   -- 0=Sun .. 6=Sat
  next_run_at     timestamptz,
  status          plan_status not null default 'active',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists idx_commuter_plans_customer on public.commuter_plans (customer_id, created_at desc);
create index if not exists idx_commuter_plans_due on public.commuter_plans (next_run_at) where status = 'active';

drop trigger if exists trg_commuter_plans_updated on public.commuter_plans;
create trigger trg_commuter_plans_updated before update on public.commuter_plans
  for each row execute function set_updated_at();

-- RLS: a customer manages only their own plans (backend service-role bypasses).
alter table public.commuter_plans enable row level security;
drop policy if exists commuter_plans_self on public.commuter_plans;
create policy commuter_plans_self on public.commuter_plans
  for all using (auth.uid() = customer_id) with check (auth.uid() = customer_id);
