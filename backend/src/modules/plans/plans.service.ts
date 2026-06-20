import { supabaseAdmin } from '../../config/supabase';
import { conflict, forbidden, notFound } from '../../utils/http';
import { estimateErrandFare } from '../fare/fare.service';
import { createTrip } from '../trips/trips.service';
import type { CommuterFrequency } from '../../types/domain';

export interface CreatePlanInput {
  customerId: string;
  errandType: string;
  description: string;
  pickup: { lat: number; lng: number; address?: string };
  dropoff?: { lat: number; lng: number; address?: string };
  distanceKm: number;
  durationMin: number;
  frequency: CommuterFrequency;
  timeOfDay: string; // 'HH:MM'
  daysOfWeek?: number[]; // 0=Sun .. 6=Sat (used for 'weekly')
}

/**
 * Creates a recurring "commuter plan" for an errand. The fare is estimated
 * automatically from the errand type + description (same engine as one-off errands),
 * and the first run time is scheduled. A cron (future) calls runDuePlans() to spin up
 * the actual trips.
 */
export async function createCommuterPlan(input: CreatePlanInput) {
  const est = await estimateErrandFare({
    errandType: input.errandType,
    description: input.description,
    distanceKm: input.distanceKm,
    durationMin: input.durationMin,
  });

  const days = input.frequency === 'weekly' ? input.daysOfWeek ?? [] : defaultDays(input.frequency);
  const nextRun = computeNextRun(input.timeOfDay, days);

  const { data, error } = await supabaseAdmin
    .from('commuter_plans')
    .insert({
      customer_id: input.customerId,
      errand_type: input.errandType,
      description: input.description,
      pickup_lat: input.pickup.lat,
      pickup_lng: input.pickup.lng,
      pickup_address: input.pickup.address,
      dropoff_lat: input.dropoff?.lat,
      dropoff_lng: input.dropoff?.lng,
      dropoff_address: input.dropoff?.address,
      distance_km: input.distanceKm,
      duration_min: input.durationMin,
      fare_estimate: est.fare,
      upfront_amount: est.upfront,
      balance_amount: est.balance,
      frequency: input.frequency,
      time_of_day: input.timeOfDay,
      days_of_week: days,
      next_run_at: nextRun.toISOString(),
      status: 'active',
    })
    .select('id, fare_estimate, upfront_amount, balance_amount, frequency, time_of_day, days_of_week, next_run_at, status')
    .single();
  if (error) throw new Error(`could not create commuter plan: ${error.message}`);
  return { ...data, estimate: est };
}

export async function listMyPlans(customerId: string) {
  const { data } = await supabaseAdmin
    .from('commuter_plans')
    .select('*')
    .eq('customer_id', customerId)
    .order('created_at', { ascending: false });
  return data ?? [];
}

/** Pause / resume / cancel a plan (owner only). */
export async function setPlanStatus(planId: string, customerId: string, status: 'active' | 'paused' | 'cancelled') {
  const { data: plan } = await supabaseAdmin
    .from('commuter_plans')
    .select('id, customer_id, status, time_of_day, days_of_week')
    .eq('id', planId)
    .single();
  if (!plan) throw notFound('plan not found');
  if (plan.customer_id !== customerId) throw forbidden();
  if (plan.status === 'cancelled') throw conflict('plan already cancelled');

  const patch: Record<string, unknown> = { status };
  // Resuming re-arms the next run time.
  if (status === 'active') {
    patch.next_run_at = computeNextRun(plan.time_of_day as string, (plan.days_of_week as number[]) ?? []).toISOString();
  }
  await supabaseAdmin.from('commuter_plans').update(patch).eq('id', planId);
  return { status };
}

/**
 * Spins up the actual errand trips for every active plan that is due. Each created
 * trip enters the normal matching flow (searching → rider → quote → pay). Intended to
 * be invoked by a scheduled function / cron. Returns how many trips were created.
 */
export async function runDuePlans(now = new Date()) {
  const { data: due } = await supabaseAdmin
    .from('commuter_plans')
    .select('*')
    .eq('status', 'active')
    .lte('next_run_at', now.toISOString());

  let created = 0;
  for (const plan of due ?? []) {
    await createTrip({
      customerId: plan.customer_id,
      tripType: 'errands',
      vehicleClass: 'errands',
      pickup: { lat: plan.pickup_lat, lng: plan.pickup_lng, address: plan.pickup_address ?? undefined },
      dropoff:
        plan.dropoff_lat != null
          ? { lat: plan.dropoff_lat, lng: plan.dropoff_lng, address: plan.dropoff_address ?? undefined }
          : undefined,
      distanceKm: Number(plan.distance_km ?? 0),
      durationMin: Number(plan.duration_min ?? 0),
      errandType: plan.errand_type,
      errandDetails: { description: plan.description, commuterPlanId: plan.id },
    });
    const next = computeNextRun(plan.time_of_day as string, (plan.days_of_week as number[]) ?? [], addDays(now, 1));
    await supabaseAdmin.from('commuter_plans').update({ next_run_at: next.toISOString() }).eq('id', plan.id);
    created++;
  }
  return { created };
}

/**
 * Moves scheduled trips whose time has arrived into matching. Intended to be invoked
 * by the same scheduled function / cron as runDuePlans.
 */
export async function releaseDueScheduledTrips(now = new Date()) {
  const { data } = await supabaseAdmin
    .from('trips')
    .update({ status: 'searching' })
    .eq('status', 'scheduled')
    .lte('scheduled_for', now.toISOString())
    .select('id');
  return { released: data?.length ?? 0 };
}

// ---- schedule helpers -------------------------------------------------------
function defaultDays(freq: CommuterFrequency): number[] {
  if (freq === 'daily') return [0, 1, 2, 3, 4, 5, 6];
  if (freq === 'weekdays') return [1, 2, 3, 4, 5];
  return [];
}

/** Next datetime at `HH:MM` on one of `days` (0=Sun..6=Sat), at or after `from`. */
function computeNextRun(timeOfDay: string, days: number[], from = new Date()): Date {
  const [h, m] = timeOfDay.split(':').map((n) => parseInt(n, 10));
  const allowed = days.length ? days : [0, 1, 2, 3, 4, 5, 6];
  for (let i = 0; i < 8; i++) {
    const d = addDays(from, i);
    d.setHours(h, m || 0, 0, 0);
    if (allowed.includes(d.getDay()) && d.getTime() >= from.getTime()) return d;
  }
  // Fallback: tomorrow at the requested time.
  const d = addDays(from, 1);
  d.setHours(h, m || 0, 0, 0);
  return d;
}

function addDays(d: Date, n: number): Date {
  const r = new Date(d);
  r.setDate(r.getDate() + n);
  return r;
}
