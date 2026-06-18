/* End-to-end flow test for EVERY service type (bike, car, errands):
 * customer books + (simulated) pays 50% -> a rider within ~5km sees the request
 * (a rider out of range does NOT) -> accept -> arrived -> start -> complete ->
 * auto-rating applied. Run against a backend with the latest code. */
import axios from 'axios';
import { createClient } from '@supabase/supabase-js';
import { supabaseAdmin } from '../src/config/supabase';
import { env } from '../src/config/env';

const BASE = process.env.E2E_BASE ?? 'http://localhost:8080';
const anon = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, { auth: { persistSession: false } });

// Meru town as the pickup.
const PICKUP = { lat: 0.0463, lng: 37.6559 };
const NEAR = { lat: 0.0463 + 0.04, lng: 37.6559 }; // ~4.4 km away
const FAR = { lat: 0.0463 + 0.5, lng: 37.6559 }; // ~55 km away

let pass = 0;
let fail = 0;
const created: string[] = [];
function ok(name: string, cond: boolean, extra = '') {
  console.log(`${cond ? '✅' : '❌'} ${name}${extra ? '  — ' + extra : ''}`);
  cond ? pass++ : fail++;
}
function api(token?: string) {
  return axios.create({ baseURL: BASE, headers: token ? { Authorization: `Bearer ${token}` } : {}, validateStatus: () => true });
}

async function makeUser(role: string, name: string) {
  const email = `flow_${role}_${Date.now()}_${Math.floor(Math.random() * 1e4)}@gmail.com`;
  const { data } = await supabaseAdmin.auth.admin.createUser({ email, password: 'passw0rd!', email_confirm: true, user_metadata: { role, full_name: name } });
  created.push(data.user!.id);
  await supabaseAdmin.from('profiles').upsert({ id: data.user!.id, role, full_name: name, email });
  const { data: s } = await anon.auth.signInWithPassword({ email, password: 'passw0rd!' });
  return { id: data.user!.id, token: s.session!.access_token, email };
}

async function makeRider(kind: 'bike' | 'car' | 'errands', loc: { lat: number; lng: number }) {
  const u = await makeUser(`${kind}_rider`, `${kind} rider`);
  const R = api(u.token);
  await R.post('/api/riders/register', { kind });
  const { data: rider } = await supabaseAdmin.from('riders').select('id').eq('profile_id', u.id).single();
  // Activate directly + set online + location.
  await supabaseAdmin.from('riders').update({ status: 'activated', is_online: true, last_lat: loc.lat, last_lng: loc.lng, last_location_at: new Date().toISOString() }).eq('id', rider!.id);
  return { ...u, R, riderId: rider!.id };
}

async function runFlow(label: string, kind: 'bike' | 'car' | 'errands', vehicleClass: string, customer: { token: string }) {
  console.log(`\n--- ${label.toUpperCase()} FLOW ---`);
  const C = api(customer.token);
  const near = await makeRider(kind, NEAR);
  const far = await makeRider(kind, FAR);

  // Customer creates the trip.
  const body: Record<string, unknown> = {
    tripType: kind === 'errands' ? 'errands' : kind,
    vehicleClass,
    pickup: { lat: PICKUP.lat, lng: PICKUP.lng, address: 'Meru Town' },
    dropoff: { lat: PICKUP.lat + 0.02, lng: PICKUP.lng + 0.02, address: 'Makutano' },
    distanceKm: 3, durationMin: 9,
  };
  if (kind === 'errands') { body.errandType = 'grocery_shopping'; body.errandDetails = { description: '2kg sugar\n1 loaf bread\n1L milk' }; }
  const trip = await C.post('/api/trips', body);
  const tripId = trip.data?.data?.tripId as string;
  ok(`${label}: customer creates + pays 50%`, trip.status === 201 && !!tripId, `fare=${trip.data?.data?.fare} upfront=${trip.data?.data?.upfront}`);

  // Simulate the 50% upfront settling -> searching (no live Paystack charge).
  await supabaseAdmin.from('trips').update({ status: 'searching' }).eq('id', tripId);

  // Rider within 5km sees the request; far rider does not.
  const nearSees = await near.R.get('/api/trips/available');
  const farSees = await far.R.get('/api/trips/available');
  const nearHas = Array.isArray(nearSees.data.data) && nearSees.data.data.some((t: { id: string }) => t.id === tripId);
  const farHas = Array.isArray(farSees.data.data) && farSees.data.data.some((t: { id: string }) => t.id === tripId);
  ok(`${label}: rider @~5km is alerted`, nearHas, `nearTrips=${nearSees.data?.data?.length}`);
  ok(`${label}: rider @~55km is NOT alerted (out of range)`, !farHas, `farTrips=${farSees.data?.data?.length}`);

  // Closest rider accepts.
  const acc = await near.R.post(`/api/trips/${tripId}/accept`);
  ok(`${label}: closest rider accepts`, acc.status === 200 && acc.data.data.status === 'rider_assigned');

  // Customer sees the rider's live location.
  const rloc = await C.get(`/api/trips/${tripId}/rider-location`);
  ok(`${label}: customer sees live rider location`, rloc.status === 200 && rloc.data.data.riderLat != null,
    `rider@${rloc.data?.data?.riderLat?.toFixed?.(3)},${rloc.data?.data?.riderLng?.toFixed?.(3)}`);

  // Lifecycle.
  await near.R.post(`/api/trips/${tripId}/arrived`);
  await near.R.post(`/api/trips/${tripId}/start`);
  const comp = await near.R.post(`/api/trips/${tripId}/complete`);
  ok(`${label}: arrived -> start -> complete (escrow 20/80)`, comp.status === 200 && !!comp.data.data.split,
    comp.data?.data?.split ? `rider=${comp.data.data.split.riderAmount}` : '');

  // Auto-rating: the rider's rating_count should have incremented WITHOUT a manual rate.
  const { data: riderRow } = await supabaseAdmin.from('riders').select('rating_avg, rating_count').eq('id', near.riderId).single();
  ok(`${label}: system auto-graded the rider`, (riderRow?.rating_count ?? 0) >= 1, `avg=${riderRow?.rating_avg} count=${riderRow?.rating_count}`);
}

async function main() {
  console.log('\n=== U-BIKE FULL FLOW TEST (bike / car / errands) ===');
  const customer = await makeUser('customer', 'Flow Customer');

  await runFlow('Bike', 'bike', 'standard_bike', customer);
  await runFlow('Car', 'car', 'economy', customer);
  await runFlow('Errands', 'errands', 'errands', customer);

  // Cleanup all test users.
  for (const id of created) await supabaseAdmin.auth.admin.deleteUser(id).catch(() => {});
  await supabaseAdmin.auth.admin.deleteUser(customer.id).catch(() => {});

  console.log(`\n=== RESULT: ${pass} passed, ${fail} failed ===\n`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => { console.error('FATAL', e); process.exit(1); });
