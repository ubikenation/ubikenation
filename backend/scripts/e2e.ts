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

  // 4) rider adjustment validation (no reason required now)
  const adj = await R.post('/api/fare/validate-adjustment', { originalFare: 300, proposedFare: 500 });
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

  // Helper: simulate a customer paying (no live Paystack charge) by funding escrow
  // and advancing the trip status exactly like the payment webhook would.
  async function fundUpfront(id: string) {
    const { data: t } = await supabaseAdmin.from('trips').select('upfront_amount').eq('id', id).single();
    await supabaseAdmin.from('escrow').upsert(
      { trip_id: id, amount: t!.upfront_amount, status: 'held', held_at: new Date().toISOString() },
      { onConflict: 'trip_id' });
    await supabaseAdmin.from('trips').update({ status: 'rider_assigned' }).eq('id', id);
  }
  async function fundBalance(id: string) {
    const { data: t } = await supabaseAdmin.from('trips').select('final_fare').eq('id', id).single();
    await supabaseAdmin.from('escrow').upsert(
      { trip_id: id, amount: t!.final_fare, status: 'held', held_at: new Date().toISOString() },
      { onConflict: 'trip_id' });
  }

  // 10) customer requests a ride → goes straight to matching (searching), NO payment yet
  const trip = await C.post('/api/trips', {
    tripType: 'bike', vehicleClass: 'standard_bike',
    pickup: { lat: -1.2921, lng: 36.8219, address: 'CBD' },
    dropoff: { lat: -1.30, lng: 36.78, address: 'Westlands' },
    distanceKm: 6, durationMin: 18,
  });
  const tripId = trip.data?.data?.tripId as string;
  ok('POST /api/trips (create → searching, no upfront)',
    trip.status === 201 && !!tripId && trip.data.data.status === 'searching',
    `status=${trip.data?.data?.status} fare=${trip.data?.data?.fare}`);

  // 11) rider sees available trip (within 5km, randomised)
  const avail = await R.get('/api/trips/available');
  const sees = Array.isArray(avail.data.data) && avail.data.data.some((t: { id: string }) => t.id === tripId);
  ok('GET /api/trips/available shows the trip', avail.status === 200 && sees);

  // 12) rider accepts → quote_pending (customer still just sees "finding…")
  const acc = await R.post(`/api/trips/${tripId}/accept`);
  ok('POST /api/trips/:id/accept → quote_pending', acc.status === 200 && acc.data.data.status === 'quote_pending', errMsg(acc.data));

  // 13) rider accepts the AUTO fare (no adjust) → awaiting_payment, 20% commission
  const quote = await R.post(`/api/trips/${tripId}/quote`, {});
  ok('POST /api/trips/:id/quote (auto, no adjust)', quote.status === 200 && quote.data.data.adjusted === false,
    `final=${quote.data?.data?.finalFare} upfront=${quote.data?.data?.upfront}`);

  // 13b) customer fetches rider + vehicle identity for tracking
  const rloc = await C.get(`/api/trips/${tripId}/rider-location`);
  ok('GET /api/trips/:id/rider-location (rider + car)',
    rloc.status === 200 && rloc.data.data.hasRider === true && rloc.data.data.riderLat != null,
    `rider@${rloc.data?.data?.riderLat},${rloc.data?.data?.riderLng} plate=${rloc.data?.data?.plateNumber}`);

  // 14) customer pays 50% (simulated) → rider_assigned; push live location; rider traces it
  await fundUpfront(tripId);
  const cpush = await C.post(`/api/trips/${tripId}/customer-location`, { lat: -1.2925, lng: 36.8225 });
  ok('POST /api/trips/:id/customer-location', cpush.status === 200);
  const cloc = await R.get(`/api/trips/${tripId}/customer-location`);
  ok('GET /api/trips/:id/customer-location (rider traces customer)',
    cloc.status === 200 && cloc.data.data.customerLat != null);

  // 15) lifecycle: arrived → start → complete-without-balance → pay balance → completed (20/80)
  const arr = await R.post(`/api/trips/${tripId}/arrived`);
  ok('POST /api/trips/:id/arrived', arr.status === 200);
  const st = await R.post(`/api/trips/${tripId}/start`);
  ok('POST /api/trips/:id/start', st.status === 200 && st.data.data.status === 'in_progress');
  const compEarly = await R.post(`/api/trips/${tripId}/complete`);
  ok('Complete before balance → awaiting_balance', compEarly.status === 200 && compEarly.data.data.status === 'awaiting_balance', errMsg(compEarly.data));
  await fundBalance(tripId);
  const comp = await R.post(`/api/trips/${tripId}/complete`);
  const split = comp.data?.data?.split;
  const { data: fareRow } = await supabaseAdmin.from('trips').select('final_fare').eq('id', tripId).single();
  const expected20 = Math.round((fareRow!.final_fare as number) * 0.2);
  ok('Complete (escrow release, 20% no-adjust)', comp.status === 200 && !!split && split.companyAmount === expected20,
    split ? `company=${split.companyAmount} (exp ${expected20}) rider=${split.riderAmount}` : errMsg(comp.data));

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

  // 21) errand auto fare estimate (scans listed items)
  const errFew = await C.post('/api/fare/errand-estimate', { errandType: 'grocery_shopping', description: '2kg sugar\n1 loaf bread', distanceKm: 3, durationMin: 9 });
  const errMany = await C.post('/api/fare/errand-estimate', { errandType: 'grocery_shopping', description: '2kg sugar\n1 loaf bread\n500g rice\n1L milk\n6 eggs\n2 soap', distanceKm: 3, durationMin: 9 });
  const scales = (errFew.data?.data?.fare ?? 0) > 0 && (errMany.data?.data?.fare ?? 0) > (errFew.data?.data?.fare ?? 0);
  ok('POST /api/fare/errand-estimate (scales with items)', errFew.status === 200 && scales,
    `2 items=${errFew.data?.data?.fare} 6 items=${errMany.data?.data?.fare}`);

  // 22) customer trip history
  const mine = await C.get('/api/trips/mine');
  const hasTrip = Array.isArray(mine.data.data) && mine.data.data.some((t: { id: string }) => t.id === tripId);
  ok('GET /api/trips/mine (customer history)', mine.status === 200 && hasTrip, `count=${mine.data?.data?.length}`);

  // 23) customer wallet endpoint
  const cwallet = await C.get('/api/payments/wallet');
  ok('GET /api/payments/wallet (customer)', cwallet.status === 200 && cwallet.data.data.wallet !== undefined);

  // 24) rider violation report → warning on first offence
  const viol = await R.post('/api/riders/violation', { kind: 'offline_during_trip', tripId });
  ok('POST /api/riders/violation (warning)', viol.status === 200 && viol.data.data.severity === 'warning', `offence=${viol.data?.data?.offence}`);

  // 25) admin list endpoints
  const aRiders = await A.get('/api/admin/riders?status=activated');
  ok('GET /api/admin/riders', aRiders.status === 200 && Array.isArray(aRiders.data.data));
  const aTrips = await A.get('/api/admin/trips');
  ok('GET /api/admin/trips', aTrips.status === 200 && Array.isArray(aTrips.data.data));
  const aPayouts = await A.get('/api/admin/payouts');
  ok('GET /api/admin/payouts', aPayouts.status === 200 && Array.isArray(aPayouts.data.data));
  const aDocs = await A.get(`/api/admin/riders/${riderId}/documents`);
  ok('GET /api/admin/riders/:id/documents', aDocs.status === 200 && Array.isArray(aDocs.data.data), `docs=${aDocs.data?.data?.length}`);

  // 26) admin reject path (suspend a fresh rider would change state) — toggle founding instead (non-destructive)
  const fToggle = await A.patch('/api/admin/founding', { enabled: true });
  ok('PATCH /api/admin/founding', fToggle.status === 200);

  // 27) ADJUSTED trip → 25% commission (rider nudges the fare up)
  const trip2 = await C.post('/api/trips', {
    tripType: 'bike', vehicleClass: 'standard_bike',
    pickup: { lat: -1.2921, lng: 36.8219, address: 'CBD' },
    dropoff: { lat: -1.31, lng: 36.77, address: 'Far' },
    distanceKm: 8, durationMin: 25,
  });
  const tripId2 = trip2.data?.data?.tripId as string;
  await R.post(`/api/trips/${tripId2}/accept`);
  const baseFare2 = trip2.data?.data?.fare as number;
  const q2 = await R.post(`/api/trips/${tripId2}/quote`, { proposedFare: Math.round(baseFare2 * 1.2) });
  ok('Quote with adjustment → adjusted=true', q2.status === 200 && q2.data.data.adjusted === true, `final=${q2.data?.data?.finalFare}`);
  const { data: t2row } = await supabaseAdmin.from('trips').select('commission_rate, final_fare').eq('id', tripId2).single();
  ok('Adjusted trip sets 25% commission_rate', Number(t2row!.commission_rate) === 0.25, `rate=${t2row?.commission_rate}`);
  await fundUpfront(tripId2);
  await R.post(`/api/trips/${tripId2}/arrived`);
  await R.post(`/api/trips/${tripId2}/start`);
  await fundBalance(tripId2);
  const comp2 = await R.post(`/api/trips/${tripId2}/complete`);
  const split2 = comp2.data?.data?.split;
  const expected25 = Math.round((t2row!.final_fare as number) * 0.25);
  ok('Complete (escrow release, 25% adjusted)', comp2.status === 200 && !!split2 && split2.companyAmount === expected25,
    split2 ? `company=${split2.companyAmount} (exp ${expected25})` : errMsg(comp2.data));

  // 28) REQUERY: customer passes on a rider → re-search excludes that rider
  const trip3 = await C.post('/api/trips', {
    tripType: 'bike', vehicleClass: 'standard_bike',
    pickup: { lat: -1.2921, lng: 36.8219, address: 'CBD' },
    dropoff: { lat: -1.30, lng: 36.79, address: 'Near' },
    distanceKm: 4, durationMin: 12,
  });
  const tripId3 = trip3.data?.data?.tripId as string;
  await R.post(`/api/trips/${tripId3}/accept`);
  const rq = await C.post(`/api/trips/${tripId3}/requery`);
  ok('POST /api/trips/:id/requery → searching', rq.status === 200 && rq.data.data.status === 'searching');
  const avail3 = await R.get('/api/trips/available');
  const excluded = !avail3.data.data.some((t: { id: string }) => t.id === tripId3);
  ok('Re-search excludes the passed-on rider', avail3.status === 200 && excluded);

  // 29) COMMUTER PLAN (recurring errand) — auto-priced
  const plan = await C.post('/api/plans', {
    errandType: 'grocery_shopping',
    description: '2kg sugar\n1 loaf bread\n1L milk',
    pickup: { lat: -1.2921, lng: 36.8219, address: 'Home' },
    dropoff: { lat: -1.30, lng: 36.79, address: 'Market' },
    distanceKm: 3, durationMin: 10,
    frequency: 'weekdays', timeOfDay: '08:00',
  });
  ok('POST /api/plans (commuter plan, auto fare)', plan.status === 201 && plan.data.data.fare_estimate > 0,
    `est=${plan.data?.data?.fare_estimate} next=${plan.data?.data?.next_run_at}`);
  const planList = await C.get('/api/plans/mine');
  ok('GET /api/plans/mine', planList.status === 200 && Array.isArray(planList.data.data) && planList.data.data.length > 0);

  // 30) SCHEDULED trip — parked until due
  const future = new Date(Date.now() + 3 * 3600_000).toISOString();
  const sched = await C.post('/api/trips/schedule', {
    tripType: 'bike', vehicleClass: 'standard_bike',
    pickup: { lat: -1.2921, lng: 36.8219, address: 'CBD' },
    dropoff: { lat: -1.30, lng: 36.78, address: 'Westlands' },
    distanceKm: 6, durationMin: 18, scheduledFor: future,
  });
  ok('POST /api/trips/schedule → scheduled', sched.status === 201 && sched.data.data.status === 'scheduled',
    `status=${sched.data?.data?.status}`);

  // 31) DEVICE TOKEN registration (FCM)
  const dev = await C.post('/api/devices/register', { token: `e2e-token-${stamp}`, platform: 'android' });
  ok('POST /api/devices/register (FCM token)', dev.status === 200 && dev.data.data.ok === true);

  // 32) RIDER EXPLICIT DECLINE → request hidden from that rider
  const trip5 = await C.post('/api/trips', {
    tripType: 'bike', vehicleClass: 'standard_bike',
    pickup: { lat: -1.2921, lng: 36.8219, address: 'CBD' },
    dropoff: { lat: -1.30, lng: 36.79, address: 'Near' },
    distanceKm: 4, durationMin: 12,
  });
  const tripId5 = trip5.data?.data?.tripId as string;
  const dec = await R.post(`/api/trips/${tripId5}/decline`);
  ok('POST /api/trips/:id/decline', dec.status === 200 && dec.data.data.declined === true);
  const avail5 = await R.get('/api/trips/available');
  ok('Declined request hidden from the rider', avail5.status === 200 && !avail5.data.data.some((t: { id: string }) => t.id === tripId5));

  // 33) DISPUTE → admin sees it → admin REFUND → customer wallet credited, trip cancelled
  const trip4 = await C.post('/api/trips', {
    tripType: 'bike', vehicleClass: 'standard_bike',
    pickup: { lat: -1.2921, lng: 36.8219, address: 'CBD' },
    dropoff: { lat: -1.30, lng: 36.78, address: 'Westlands' },
    distanceKm: 6, durationMin: 18,
  });
  const tripId4 = trip4.data?.data?.tripId as string;
  await R.post(`/api/trips/${tripId4}/accept`);
  await R.post(`/api/trips/${tripId4}/quote`, {});
  await fundUpfront(tripId4);
  await R.post(`/api/trips/${tripId4}/arrived`);
  await R.post(`/api/trips/${tripId4}/start`);
  const dsp = await C.post(`/api/trips/${tripId4}/dispute`, { reason: 'Took the wrong route' });
  ok('POST /api/trips/:id/dispute → disputed', dsp.status === 200 && dsp.data.data.status === 'disputed', errMsg(dsp.data));
  const aDisp = await A.get('/api/admin/disputes');
  ok('Admin sees the open dispute', aDisp.status === 200 && aDisp.data.data.some((d: { id: string }) => d.id === tripId4));
  const wBefore = (await C.get('/api/payments/wallet')).data.data.wallet.balance as number;
  const refund = await A.post(`/api/admin/trips/${tripId4}/refund`);
  ok('Admin refund returns amount', refund.status === 200 && refund.data.data.refunded > 0, `refunded=${refund.data?.data?.refunded}`);
  const wAfter = (await C.get('/api/payments/wallet')).data.data.wallet.balance as number;
  ok('Customer wallet credited by the refund', wAfter > wBefore, `before=${wBefore} after=${wAfter}`);
  const { data: t4row } = await supabaseAdmin.from('trips').select('status').eq('id', tripId4).single();
  ok('Disputed trip → cancelled after refund', t4row!.status === 'cancelled', `status=${t4row?.status}`);

  // 34) ADMIN commuter-plans list
  const aPlans = await A.get('/api/admin/plans');
  ok('GET /api/admin/plans', aPlans.status === 200 && Array.isArray(aPlans.data.data) && aPlans.data.data.length > 0,
    `count=${aPlans.data?.data?.length}`);

  // 35) TWO-WAY CHAT (customer ↔ rider, both directions deliver + are visible)
  const cMsg = await C.post(`/api/trips/${tripId}/chat`, { body: 'Hi, I am at the gate' });
  ok('Customer sends chat (delivered)', cMsg.status === 201 && cMsg.data.data.delivered === true, errMsg(cMsg.data));
  const rInbox = await R.get(`/api/trips/${tripId}/chat`);
  ok('Rider receives the customer message',
    rInbox.status === 200 && rInbox.data.data.some((m: { body: string }) => m.body === 'Hi, I am at the gate'));
  const rMsg = await R.post(`/api/trips/${tripId}/chat`, { body: 'On my way, 2 minutes' });
  ok('Rider replies (delivered)', rMsg.status === 201 && rMsg.data.data.delivered === true);
  const cInbox = await C.get(`/api/trips/${tripId}/chat`);
  ok('Customer receives the rider reply',
    cInbox.status === 200 && cInbox.data.data.some((m: { body: string }) => m.body === 'On my way, 2 minutes'));

  // 36) ZEGO CALL TOKENS — both parties get a valid token for the SAME room (trip)
  const cTok = await C.get(`/api/calls/token?tripId=${tripId}`);
  const rTok = await R.get(`/api/calls/token?tripId=${tripId}`);
  ok('Customer gets a ZEGO voice token', cTok.status === 200 && (cTok.data?.data?.token ?? '').startsWith('04') && cTok.data.data.appId > 0,
    `appId=${cTok.data?.data?.appId}`);
  ok('Rider gets a ZEGO voice token', rTok.status === 200 && (rTok.data?.data?.token ?? '').startsWith('04'));
  ok('Both join the same call room (the trip)', cTok.data?.data?.roomId === tripId && rTok.data?.data?.roomId === tripId);

  // 37) ERRAND RIDER sees the errand details before accepting
  const erider = await ensureUser(`ubike.e2e.erider.${stamp}@gmail.com`, 'passw0rd!', 'errands_rider', 'Errand Rider', '254700000009');
  const ER = api(erider.token);
  await ER.post('/api/riders/register', { kind: 'errands' });
  await ER.post('/api/riders/documents', { kind: 'errands', documents: docs });
  const { data: erRow } = await supabaseAdmin.from('riders').select('id').eq('profile_id', erider.id).eq('kind', 'errands').single();
  await A.post(`/api/admin/riders/${erRow!.id}/approve`);
  await ER.post('/api/riders/online', { isOnline: true });
  await ER.post('/api/riders/location', { lat: -1.2921, lng: 36.8219 });
  const errTrip = await C.post('/api/trips', {
    tripType: 'errands', vehicleClass: 'errands',
    pickup: { lat: -1.2921, lng: 36.8219, address: 'Home' },
    dropoff: { lat: -1.30, lng: 36.79, address: 'Shop' },
    distanceKm: 3, durationMin: 10,
    errandType: 'grocery_shopping',
    errandDetails: { description: '2kg sugar\n1 loaf bread\n6 eggs' },
  });
  const errId = errTrip.data?.data?.tripId as string;
  const eAvail = await ER.get('/api/trips/available');
  const seen = (eAvail.data?.data ?? []).find((t: { id: string }) => t.id === errId);
  ok('Errand rider sees the errand request', eAvail.status === 200 && !!seen);
  ok('Errand request shows type + the customer\'s description',
    !!seen && seen.errand_type === 'grocery_shopping' && (seen.errand_details?.description ?? '').includes('sugar'),
    seen ? `type=${seen.errand_type}` : 'not found');

  console.log(`\n=== RESULT: ${pass} passed, ${fail} failed ===\n`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
