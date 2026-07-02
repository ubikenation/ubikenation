-- =====================================================================
-- U-BIKE — Company wallet + automatic rider payout support
-- Apply once in the Supabase SQL editor (service role can't run DDL via the API).
-- Safe to re-run (idempotent).
-- =====================================================================

-- Company wallet: an append-only ledger that ACCUMULATES the platform's
-- commission cut (20% normal / 25% when the rider adjusted the fare). One row is
-- written per completed trip at escrow-release time. The company "wallet balance"
-- is simply the running SUM(amount) of this ledger.
create table if not exists company_ledger (
  id         uuid primary key default uuid_generate_v4(),
  trip_id    uuid references trips(id) on delete set null,
  amount     integer not null,        -- KES, the company's cut for this trip
  rate       numeric(4,3) not null,   -- 0.200 or 0.250
  reason     text,
  paid_at    timestamptz,             -- set when swept to the company M-Pesa (null = still in wallet)
  created_at timestamptz not null default now()
);
-- If the table already existed from an earlier version, add the payout-tracking column.
alter table company_ledger add column if not exists paid_at timestamptz;
create index if not exists company_ledger_created_idx on company_ledger (created_at desc);
create index if not exists company_ledger_unpaid_idx on company_ledger (paid_at) where paid_at is null;

-- The automatic payout scheduler processes each rider payout DELAY hours after the
-- trip completed. We already have payouts.created_at (set at release), so no schema
-- change is needed for timing — the backend selects pending payouts older than the
-- configured delay. This file exists mainly for the company_ledger table above.
