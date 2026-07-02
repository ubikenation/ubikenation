-- =====================================================================
-- U-BIKE — Postgres functions (run AFTER schema.sql)
-- Atomic money mutations and race-safe founding-slot allocation.
-- =====================================================================

-- ---------------------------------------------------------------------
-- wallet_apply: atomically upsert a wallet balance and append a ledger row.
-- direction 'credit' adds, 'debit' subtracts (and guards against overdraft).
-- Returns the new available balance.
-- ---------------------------------------------------------------------
create or replace function wallet_apply(
  p_profile uuid,
  p_direction ledger_direction,
  p_amount integer,
  p_reason text,
  p_trip uuid default null,
  p_payment uuid default null
) returns integer
language plpgsql
as $$
declare
  v_balance integer;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'amount must be positive';
  end if;

  insert into wallets (profile_id, balance)
  values (p_profile, 0)
  on conflict (profile_id) do nothing;

  -- lock the row for the duration of the transaction
  select balance into v_balance from wallets where profile_id = p_profile for update;

  if p_direction = 'credit' then
    v_balance := v_balance + p_amount;
  else
    if v_balance < p_amount then
      raise exception 'insufficient wallet balance: have %, need %', v_balance, p_amount;
    end if;
    v_balance := v_balance - p_amount;
  end if;

  update wallets set balance = v_balance, updated_at = now() where profile_id = p_profile;

  insert into wallet_ledger (profile_id, direction, amount, balance_after, reason, trip_id, payment_id)
  values (p_profile, p_direction, p_amount, v_balance, p_reason, p_trip, p_payment);

  return v_balance;
end;
$$;

-- ---------------------------------------------------------------------
-- claim_founding_slot: race-safe allocation of a free founding slot.
-- Locks the program row, counts current founders of that kind, and marks
-- the rider as founding (fee 0) if a slot remains; otherwise sets the
-- normal fee. Returns the fee that applies.
-- ---------------------------------------------------------------------
-- Errands riders now have their own founding program too (first 5 free, then a fee),
-- so this takes an errands fee and reads errands_slots. Drop the old 4-arg version.
drop function if exists claim_founding_slot(uuid, rider_kind, integer, integer);
create or replace function claim_founding_slot(
  p_rider uuid,
  p_kind rider_kind,
  p_bike_fee integer,
  p_car_fee integer,
  p_errands_fee integer
) returns integer
language plpgsql
as $$
declare
  v_enabled boolean;
  v_slots integer;
  v_used integer;
  v_fee integer;
  v_is_founding boolean;
begin
  select enabled,
         case p_kind when 'bike' then bike_slots when 'car' then car_slots else errands_slots end
    into v_enabled, v_slots
    from founding_program where id = 1 for update;

  select count(*) into v_used
    from riders where kind = p_kind and is_founding = true and id <> p_rider;

  if coalesce(v_enabled, true) and v_used < coalesce(v_slots, 0) then
    v_is_founding := true;
    v_fee := 0;
  else
    v_is_founding := false;
    v_fee := case p_kind when 'bike' then p_bike_fee when 'car' then p_car_fee else p_errands_fee end;
  end if;

  update riders
    set is_founding = v_is_founding, registration_fee = v_fee
    where id = p_rider;

  return v_fee;
end;
$$;
