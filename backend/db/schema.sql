-- =====================================================================
-- U-BIKE PLATFORM — PostgreSQL schema for Supabase
-- Run in Supabase SQL editor (or via supabase db push).
-- Designed around Supabase Auth: app users reference auth.users(id).
-- =====================================================================

create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- ENUMS
-- ---------------------------------------------------------------------
do $$ begin
  create type user_role        as enum ('customer','bike_rider','car_rider','errands_rider','admin');
  create type vehicle_class     as enum ('standard_bike','electric_bike','economy','comfort','suv','errands');
  create type rider_kind        as enum ('bike','car','errands');
  create type rider_status      as enum ('submitted','under_review','approved','activated','suspended','banned');
  create type trip_type         as enum ('bike','car','errands','scheduled');
  create type trip_status       as enum (
    'pending_payment','searching','rider_assigned','arrived',
    'in_progress','completed','cancelled','expired','disputed');
  create type payment_purpose   as enum ('trip_upfront','trip_balance','wallet_topup','rider_registration','payout');
  create type payment_status    as enum ('pending','success','failed','refunded');
  create type ledger_direction  as enum ('credit','debit');
  create type escrow_status     as enum ('held','released','refunded');
  create type payout_status     as enum ('pending','processing','completed','failed');
  create type adjustment_reason as enum (
    'heavy_rain','flooding','road_closure','accident_ahead','traffic_congestion',
    'diversion_route','security_alert','fuel_cost_surge','remote_pickup_area','public_event_congestion');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- PROFILES  (1:1 with auth.users)
-- ---------------------------------------------------------------------
create table if not exists profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  role          user_role not null default 'customer',
  full_name     text,
  email         text,
  phone         text,
  mpesa_number  text,
  avatar_url    text,
  is_active     boolean not null default true,
  last_seen_at  timestamptz,                      -- app last-opened (48h re-login rule)
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- RIDERS  (verification + founding-rider tracking)
-- ---------------------------------------------------------------------
create table if not exists riders (
  id                  uuid primary key default uuid_generate_v4(),
  profile_id          uuid not null references profiles(id) on delete cascade,
  kind                rider_kind not null,
  status              rider_status not null default 'submitted',
  is_founding         boolean not null default false,
  registration_fee    integer not null default 0,            -- KES, computed at submit time
  registration_paid   boolean not null default false,
  registration_payment_id uuid,
  -- documents (Supabase Storage paths)
  national_id_url     text,
  driving_license_url text,
  profile_photo_url   text,
  selfie_url          text,
  vehicle_photo_url   text,
  ownership_proof_url text,
  logbook_url         text,
  insurance_url       text,
  inspection_url      text,
  -- live status
  is_online           boolean not null default false,
  last_lat            double precision,
  last_lng            double precision,
  last_location_at    timestamptz,
  rating_avg          numeric(3,2) not null default 5.00,
  rating_count        integer not null default 0,
  violation_count     integer not null default 0,
  submitted_at        timestamptz not null default now(),
  approved_at         timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (profile_id, kind)
);
create index if not exists idx_riders_online on riders (kind, is_online) where is_online = true;
create index if not exists idx_riders_status on riders (status);

-- ---------------------------------------------------------------------
-- VEHICLES  (a car rider may register multiple — fee is per vehicle)
-- ---------------------------------------------------------------------
create table if not exists vehicles (
  id            uuid primary key default uuid_generate_v4(),
  rider_id      uuid not null references riders(id) on delete cascade,
  vehicle_class vehicle_class not null,
  plate_number  text,
  make          text,
  model         text,
  color         text,
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- FARE CONFIG  (server-side; customer never sees the formula)
-- ---------------------------------------------------------------------
create table if not exists fare_config (
  vehicle_class   vehicle_class primary key,
  base_fare       integer not null,   -- KES
  per_km          numeric(8,2) not null,
  per_min         numeric(8,2) not null,
  minimum_fare    integer not null
);
insert into fare_config (vehicle_class, base_fare, per_km, per_min, minimum_fare) values
  ('standard_bike',  50, 18, 2.5, 120),
  ('electric_bike',  60, 22, 3.0, 150),
  ('economy',       120, 38, 4.5, 300),
  ('comfort',       180, 55, 6.0, 450),
  ('suv',           250, 75, 8.0, 600),
  ('errands',       150, 30, 3.0, 300)
on conflict (vehicle_class) do nothing;

-- ---------------------------------------------------------------------
-- TRIPS / ERRANDS
-- ---------------------------------------------------------------------
create table if not exists trips (
  id                 uuid primary key default uuid_generate_v4(),
  customer_id        uuid not null references profiles(id) on delete restrict,
  rider_id           uuid references riders(id) on delete set null,
  trip_type          trip_type not null,
  vehicle_class      vehicle_class not null,
  status             trip_status not null default 'pending_payment',
  -- locations
  pickup_lat         double precision not null,
  pickup_lng         double precision not null,
  pickup_address     text,
  dropoff_lat        double precision,
  dropoff_lng        double precision,
  dropoff_address    text,
  -- distance/time estimate
  distance_km        numeric(8,2),
  duration_min       numeric(8,2),
  -- fare
  base_fare          integer not null,        -- system-calculated original fare (KES)
  adjusted_fare      integer,                 -- rider-adjusted fare (<= +30%)
  adjustment_reason  adjustment_reason,
  adjustment_accepted boolean,
  final_fare         integer,                 -- agreed fare used for settlement
  upfront_amount     integer,                 -- 50%
  balance_amount     integer,                 -- 50%
  -- errands extras
  errand_type        text,
  errand_details     jsonb,
  -- scheduling
  scheduled_for      timestamptz,
  -- lifecycle timestamps
  requested_at       timestamptz not null default now(),
  assigned_at        timestamptz,
  started_at         timestamptz,
  completed_at       timestamptz,
  cancelled_at       timestamptz,
  cancel_reason      text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists idx_trips_customer on trips (customer_id, created_at desc);
create index if not exists idx_trips_rider on trips (rider_id, created_at desc);
create index if not exists idx_trips_status on trips (status);

-- ---------------------------------------------------------------------
-- WALLETS + LEDGER  (double-entry-style for customers & riders)
-- ---------------------------------------------------------------------
create table if not exists wallets (
  profile_id uuid primary key references profiles(id) on delete cascade,
  balance    integer not null default 0,   -- KES, available
  pending    integer not null default 0,   -- earnings not yet settled
  updated_at timestamptz not null default now()
);

create table if not exists wallet_ledger (
  id          uuid primary key default uuid_generate_v4(),
  profile_id  uuid not null references profiles(id) on delete cascade,
  direction   ledger_direction not null,
  amount      integer not null check (amount > 0),
  balance_after integer not null,
  reason      text not null,
  trip_id     uuid references trips(id) on delete set null,
  payment_id  uuid,
  created_at  timestamptz not null default now()
);
create index if not exists idx_ledger_profile on wallet_ledger (profile_id, created_at desc);

-- ---------------------------------------------------------------------
-- PAYMENTS  (Paystack)
-- ---------------------------------------------------------------------
create table if not exists payments (
  id            uuid primary key default uuid_generate_v4(),
  profile_id    uuid not null references profiles(id) on delete restrict,
  trip_id       uuid references trips(id) on delete set null,
  purpose       payment_purpose not null,
  amount        integer not null,            -- KES
  status        payment_status not null default 'pending',
  paystack_ref  text unique,
  paystack_access_code text,
  authorization_url text,
  raw_event     jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists idx_payments_profile on payments (profile_id, created_at desc);

-- ---------------------------------------------------------------------
-- ESCROW  (per-trip held funds)
-- ---------------------------------------------------------------------
create table if not exists escrow (
  trip_id      uuid primary key references trips(id) on delete cascade,
  amount       integer not null,
  status       escrow_status not null default 'held',
  held_at      timestamptz not null default now(),
  released_at  timestamptz,
  refunded_at  timestamptz
);

-- ---------------------------------------------------------------------
-- PAYOUTS  (rider settlement to M-Pesa, 24–48h)
-- ---------------------------------------------------------------------
create table if not exists payouts (
  id           uuid primary key default uuid_generate_v4(),
  rider_id     uuid not null references riders(id) on delete restrict,
  amount       integer not null,
  mpesa_number text not null,
  status       payout_status not null default 'pending',
  trip_id      uuid references trips(id) on delete set null,
  reference    text,
  created_at   timestamptz not null default now(),
  processed_at timestamptz
);

-- ---------------------------------------------------------------------
-- RATINGS
-- ---------------------------------------------------------------------
create table if not exists ratings (
  id          uuid primary key default uuid_generate_v4(),
  trip_id     uuid not null references trips(id) on delete cascade,
  customer_id uuid not null references profiles(id) on delete cascade,
  rider_id    uuid not null references riders(id) on delete cascade,
  stars       smallint not null check (stars between 1 and 5),
  comment     text,
  created_at  timestamptz not null default now(),
  unique (trip_id)
);

-- ---------------------------------------------------------------------
-- CHAT  (text only; moderation flags stored)
-- ---------------------------------------------------------------------
create table if not exists chat_messages (
  id          uuid primary key default uuid_generate_v4(),
  trip_id     uuid not null references trips(id) on delete cascade,
  sender_id   uuid not null references profiles(id) on delete cascade,
  body        text not null,
  blocked     boolean not null default false,
  block_reason text,
  created_at  timestamptz not null default now()
);
create index if not exists idx_chat_trip on chat_messages (trip_id, created_at);

-- ---------------------------------------------------------------------
-- RIDER VIOLATIONS  (offline during trip, false adjustments, etc.)
-- ---------------------------------------------------------------------
create table if not exists rider_violations (
  id         uuid primary key default uuid_generate_v4(),
  rider_id   uuid not null references riders(id) on delete cascade,
  trip_id    uuid references trips(id) on delete set null,
  kind       text not null,        -- 'offline_during_trip','false_adjustment','gps_off', etc.
  severity   text not null default 'warning',  -- warning | suspension | termination
  details    jsonb,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- FOUNDING RIDERS PROGRAM  (admin-controllable promotion)
-- ---------------------------------------------------------------------
create table if not exists founding_program (
  id            int primary key default 1 check (id = 1),
  bike_slots    int not null default 10,
  car_slots     int not null default 10,
  errands_slots int not null default 5,
  enabled       boolean not null default true,
  updated_at    timestamptz not null default now()
);
insert into founding_program (id) values (1) on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- updated_at trigger
-- ---------------------------------------------------------------------
create or replace function set_updated_at() returns trigger as $$
begin new.updated_at = now(); return new; end; $$ language plpgsql;

do $$
declare t text;
begin
  foreach t in array array['profiles','riders','trips','payments','wallets'] loop
    execute format(
      'drop trigger if exists trg_%1$s_updated on %1$s;
       create trigger trg_%1$s_updated before update on %1$s
       for each row execute function set_updated_at();', t);
  end loop;
end $$;

-- =====================================================================
-- ROW LEVEL SECURITY
-- Service-role key (backend) bypasses RLS. These policies protect any
-- direct client (anon/authenticated) access via Supabase.
-- =====================================================================
alter table profiles       enable row level security;
alter table riders         enable row level security;
alter table trips          enable row level security;
alter table wallets        enable row level security;
alter table wallet_ledger  enable row level security;
alter table payments       enable row level security;
alter table chat_messages  enable row level security;
alter table ratings        enable row level security;

-- profiles: a user sees/edits only their own row
drop policy if exists profiles_self on profiles;
create policy profiles_self on profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);

-- riders: a rider sees only their own rider record
drop policy if exists riders_self on riders;
create policy riders_self on riders
  for all using (auth.uid() = profile_id) with check (auth.uid() = profile_id);

-- trips: visible to the customer or the assigned rider
drop policy if exists trips_party on trips;
create policy trips_party on trips
  for select using (
    auth.uid() = customer_id
    or exists (select 1 from riders r where r.id = trips.rider_id and r.profile_id = auth.uid())
  );

-- wallets / ledger / payments: owner only (read)
drop policy if exists wallets_self on wallets;
create policy wallets_self on wallets for select using (auth.uid() = profile_id);
drop policy if exists ledger_self on wallet_ledger;
create policy ledger_self on wallet_ledger for select using (auth.uid() = profile_id);
drop policy if exists payments_self on payments;
create policy payments_self on payments for select using (auth.uid() = profile_id);

-- chat: parties of the trip
drop policy if exists chat_party on chat_messages;
create policy chat_party on chat_messages
  for select using (
    exists (
      select 1 from trips t
      where t.id = chat_messages.trip_id
        and (t.customer_id = auth.uid()
             or exists (select 1 from riders r where r.id = t.rider_id and r.profile_id = auth.uid()))
    )
  );

-- ratings: readable by trip parties
drop policy if exists ratings_party on ratings;
create policy ratings_party on ratings
  for select using (auth.uid() = customer_id);
