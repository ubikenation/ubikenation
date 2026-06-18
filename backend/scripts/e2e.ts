/* End-to-end API smoke test against the live backend + Supabase.
 * Creates real auth users, signs them in for JWTs, and exercises every route. */
import axios, { AxiosError } from 'axios';
import { createClient } from '@supabase/supabase-js';
import { supabaseAdmin } from '../src/config/supabase';
import { env } from '../src/config/env';

const BASE = process.env.E2E_BASE ?? 'http://localhost:8080';
const anon = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

let pass = 0;
let fail = 0;
function ok(name: string, cond: boolean, extra = '') {
  console.log(`${cond ? '✅' : '❌'} ${name}${extra ? '  — ' + extra : ''}`);
  cond ? pass++ : fail++;
}
function api(token?: string) {
  return axios.create({
    baseURL: BASE,
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    validateStatus: () => true,
  });
}
function errMsg(e: unknown) {
  const ax = e as AxiosError<{ error?: { message?: string } }>;
  return ax.response?.data?.error?.message ?? (e as Error).message;
}

async function ensureUser(email: string, password: string, role: string, fullName: string, mpesa?: string) {
  // delete existing test user with this email (idempotent)
  const { data: list } = await supabaseAdmin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  const existing = list.users.find((u) => u.email === email);
  if (existing) await supabaseAdmin.auth.admin.deleteUser(existing.id);

  const { data, error } = await supabaseAdmin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName, role },
  });
  if (error || !data.user) throw new Error(`createUser ${email}: ${error?.message}`);
  const id = data.user.id;

  await supabaseAdmin.from('profiles').upsert({
    id,
    role,
    full_name: fullName,
    email,
    mpesa_number: mpesa ?? null,
  });

  const { data: signin, error: sErr } = await anon.auth.signInWithPassword({ email, password });
  if (sErr || !signin.session) throw new Error(`signin ${email}: ${sErr?.message}`);
  return { id, token: signin.session.access_token };
}

async function main() {
  console.log('\n=== U-BIKE API END-TO-END TEST ===\n');
  const stamp = Date.now();

  // 0) health
  const h = await api().get('/health');
  ok('GET /health', h.status === 200 && h.data.status === 'ok');

  // 1) users
  // Use a Paystack-acceptable email domain (it rejects .test TLDs).
  const customer = await ensureUser(`ubike.e2e.cust.${stamp}@gmail.com`, 'passw0rd!', 'customer', 'Test Customer');
  const rider = await ensureUser(`ubike.e2e.rider.${stamp}@gmail.com`, 'passw0rd!', 'bike_rider', 'Test Rider', '254700000001');
  const admin = await ensureUser(`ubike.e2e.admin.${stamp}@gmail.com`, 'passw0rd!', 'admin', 'Test Admin');
  ok('Create + sign in 3 users (customer/rider/admin)', !!(customer.token && rider.token && admin.token));

  const C = api(customer.token);
  const R = api(rider.token);
  const A = api(admin.token);

  // 2) auth guard
  const noauth = await api().post('/api/fare/estimate', {});
  ok('Auth guard rejects no-token (401)', noauth.status === 401);

  // 3) fare estimate
  const fare = await C.post('/api/fare/estimate', { vehicleClass: 'economy', distanceKm: 5, durationMin: 15 });
  ok('POST /api/fare/estimate', fare.status === 200 && fare.data.data.fare >= 300, `fare=${fare.data?.data?.fare}`);

  // 4) rider adjustment validation
  const adj = await R.post('/api/fare/validate-adjustment', { originalFare: 300, proposedFare: 500, reason: 'heavy_rain' });
  ok('Adjustment caps at +30%', adj.status === 200 && adj.data.data.cappedFare === 390, `capped=${adj.data?.data?.cappedFare}`);

  // 5) registration fee quote (founding aware)
  const feeQ = await R.get('/api/riders/registration-fee?kind=bike');
  ok('GET registration-fee (bike)', feeQ.status === 200, `fee=${feeQ.data?.data?.registrationFee} remaining=${feeQ.data?.data?.slotsRemaining}`);

  // 6) register rider (claims founding slot)
  const reg = await R.post('/api/riders/register', { kind: 'bike' });
  const riderId = reg.data?.data?.riderId as string;
  ok('POST /api/riders/register', reg.status === 201 && !!riderId, `founding=${reg.data?.data?.isFounding} fee=${reg.data?.data?.registrationFee}`);

  // 7) submit documents
  const docs = {
    national_id_url: 'u/id.jpg', driving_license_url: 'u/dl.jpg', profile_photo_url: 'u/pp.jpg',
    selfie_url: 'u/se.jpg', vehicle_photo_url: 'u/vp.jpg', ownership_proof_url: 'u/op.jpg',
    insurance_url: 'u/in.jpg', inspection_url: 'u/insp.jpg',
  };
  const sub = await R.post('/api/riders/documents', { kind: 'bike', documents: docs });
  ok('POST /api/riders/documents → under_review', sub.status === 200 && sub.data.data.status === 'under_review', errMsg(sub.data));

  // 8) admin approves rider → activated
  const appr = await A.post(`/api/admin/riders/${riderId}/approve`);
  ok('Admin approve rider → activated', appr.status === 200 && appr.data.data.status === 'activated');

  // 9) rider online + location
  const onl = await R.post('/api/riders/online', { isOnline: true });
  ok('POST /api/riders/online', onl.status === 200);
  const loc = await R.post('/api/riders/location', { lat: -1.292, lng: 36.821 });
  ok('POST /api/riders/location', loc.status === 200);

  // 10) customer creates trip
  const trip = await C.post('/api/trips', {
    tripType: 'bike', vehicleClass: 'standard_bike',
    pickup: { lat: -1.2921, lng: 36.8219, address: 'CBD' },
    dropoff: { lat: -1.30, lng: 36.78, address: 'Westlands' },
    distanceKm: 6, durationMin: 18,
  });
  const tripId = trip.data?.data?.tripId as string;
  ok('POST /api/trips (create)', trip.status === 201 && !!tripId, `fare=${trip.data?.data?.fare} upfront=${trip.data?.data?.upfront}`);

  // 11) simulate upfront settled → searching (skip live Paystack charge)
  await supabaseAdmin.from('trips').update({ status: 'searching' }).eq('id', tripId);

  // 12) rider sees available trip
  const avail = await R.get('/api/trips/available');
  const sees = Array.isArray(avail.data.data) && avail.data.data.some((t: { id: string }) => t.id === tripId);
  ok('GET /api/trips/available shows the trip', avail.status === 200 && sees);

  // 13) rider accepts
  const acc = await R.post(`/api/trips/${tripId}/accept`);
  ok('POST /api/trips/:id/accept', acc.status === 200 && acc.data.data.status === 'rider_assigned', errMsg(acc.data));

  // 14) rider adjusts fare, customer accepts
  const radj = await R.post(`/api/trips/${tripId}/adjust`, { proposedFare: 250, reason: 'traffic_congestion' });
  ok('POST /api/trips/:id/adjust', radj.status === 200, `capped=${radj.data?.data?.cappedFare}`);
  const cresp = await C.post(`/api/trips/${tripId}/adjust-response`, { accept: true });
  ok('Customer accepts adjustment', cresp.status === 200 && cresp.data.data.accepted === true);

  // 15) lifecycle: arrived → start → complete
  const arr = await R.post(`/api/trips/${tripId}/arrived`);
  ok('POST /api/trips/:id/arrived', arr.status === 200);
  const st = await R.post(`/api/trips/${tripId}/start`);
  ok('POST /api/trips/:id/start', st.status === 200 && st.data.data.status === 'in_progress');
  const comp = await R.post(`/api/trips/${tripId}/complete`);
  const split = comp.data?.data?.split;
  ok('POST /api/trips/:id/complete (escrow release + 20/80)', comp.status === 200 && !!split,
    split ? `company=${split.companyAmount} rider=${split.riderAmount}` : errMsg(comp.data));

  // 16) rider wallet credited
  const wallet = await R.get('/api/payments/wallet');
  ok('Rider wallet credited 80%', wallet.status === 200 && wallet.data.data.wallet.balance > 0,
    `balance=${wallet.data?.data?.wallet?.balance}`);

  // 17) customer rates rider
  const rate = await C.post(`/api/trips/${tripId}/rate`, { stars: 5, comment: 'Great ride' });
  ok('POST /api/trips/:id/rate', rate.status === 200);

  // 18) chat moderation blocks a phone number
  const chat = await C.post(`/api/trips/${tripId}/chat`, { body: 'call me on 0712 345 678' });
  ok('Chat blocks phone number', chat.status === 201 && chat.data.data.blocked === true, `reason=${chat.data?.data?.reason}`);

  // 19) admin stats + founding
  const stats = await A.get('/api/admin/stats');
  ok('GET /api/admin/stats', stats.status === 200 && typeof stats.data.data.totalUsers === 'number',
    `users=${stats.data?.data?.totalUsers} tripsToday=${stats.data?.data?.tripsToday}`);
  const founding = await A.get('/api/admin/founding');
  ok('GET /api/admin/founding', founding.status === 200,
    `bikeRemaining=${founding.data?.data?.bikeRemaining} carRemaining=${founding.data?.data?.carRemaining}`);

  // 20) Paystack connectivity (initialize only — no charge)
  const pay = await C.post('/api/payments/initiate', { purpose: 'wallet_topup', amount: 100 });
  const payUrl = pay.data?.data?.authorizationUrl;
  ok('Paystack initialize (connectivity)', pay.status === 201 && !!payUrl,
    payUrl ? 'checkout URL returned' : `status=${pay.status} ${JSON.stringify(pay.data?.error ?? pay.data)}`);

  console.log(`\n=== RESULT: ${pass} passed, ${fail} failed ===\n`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
