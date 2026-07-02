-- =====================================================================
-- U-BIKE — Errands riders founding program (first 5 free, then KES 2,000)
-- Apply once in the Supabase SQL editor. Safe to re-run (idempotent).
-- =====================================================================

-- 1) Add the errands slot count to the founding program (default 5 free slots).
alter table founding_program add column if not exists errands_slots integer not null default 5;
update founding_program set errands_slots = 5 where id = 1 and errands_slots is null;

-- 2) Slot allocator now handles ALL three kinds (bike/car/errands). Errands used to
--    be hard-coded free; now it uses errands_slots + an errands fee. Replace the old
--    4-arg function with the 5-arg one.
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
