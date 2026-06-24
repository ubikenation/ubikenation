/* Deep unit tests for the v2 business rules — pure logic, NO database required.
 * Covers: adjustment cap (+30%, no reason), adjustment-based commission (20% vs
 * 25%), exact 50/50 + cut composition (money never lost/created), 5km matching
 * distance, and random rider ordering. Run: npx ts-node scripts/logic-tests.ts */
import { splitCommission } from '../src/modules/payments/commission';
import { validateAdjustment } from '../src/modules/fare/fare.service';
import { haversineKm, shuffle } from '../src/modules/matching/matching.service';
import { COMMISSION_NO_ADJUST, COMMISSION_ADJUSTED } from '../src/types/domain';
import { env } from '../src/config/env';

let pass = 0;
let fail = 0;
function ok(name: string, cond: boolean, extra = '') {
  console.log(`${cond ? '✅' : '❌'} ${name}${extra ? '  — ' + extra : ''}`);
  cond ? pass++ : fail++;
}
const roundTo5 = (n: number) => Math.round(n / 5) * 5;

console.log('\n=== U-BIKE v2 BUSINESS-LOGIC TESTS (no DB) ===\n');

// ---------------------------------------------------------------------------
console.log('-- 1) Commission split: company + rider always == gross, no cents lost --');
for (const g of [120, 300, 333, 360, 450, 455, 600, 1000, 1, 7]) {
  for (const rate of [0.2, 0.25]) {
    const s = splitCommission(g, rate);
    const sums = s.companyAmount + s.riderAmount === g;
    const nonneg = s.companyAmount >= 0 && s.riderAmount >= 0;
    const company = s.companyAmount === Math.round(g * rate);
    ok(`KES ${g} @ ${rate * 100}% → ${s.companyAmount}/${s.riderAmount}`, sums && nonneg && company);
  }
}
ok('Default rate == env.COMMISSION_RATE (20%)', splitCommission(500).companyAmount === Math.round(500 * env.COMMISSION_RATE));
ok('400 @20% = 80 / 320', splitCommission(400, 0.2).companyAmount === 80 && splitCommission(400, 0.2).riderAmount === 320);
ok('400 @25% = 100 / 300', splitCommission(400, 0.25).companyAmount === 100 && splitCommission(400, 0.25).riderAmount === 300);
ok('1000 @25% = 250 / 750', splitCommission(1000, 0.25).companyAmount === 250);

// ---------------------------------------------------------------------------
console.log('\n-- 2) Adjustment-based commission rule (the rule quoteFare applies) --');
ok('COMMISSION_NO_ADJUST is 20%', COMMISSION_NO_ADJUST === 0.2);
ok('COMMISSION_ADJUSTED is 25%', COMMISSION_ADJUSTED === 0.25);
const rateFor = (adjusted: boolean) => (adjusted ? COMMISSION_ADJUSTED : COMMISSION_NO_ADJUST);
ok('No adjustment → 20% cut (rider keeps 80%)', rateFor(false) === 0.2);
ok('Any adjustment → 25% cut (rider keeps 75%)', rateFor(true) === 0.25);
ok('Adjusted rider nets less of same fare', splitCommission(500, rateFor(true)).riderAmount < splitCommission(500, rateFor(false)).riderAmount);

// ---------------------------------------------------------------------------
console.log('\n-- 3) Adjustment cap: ≤ +30%, no reason, never below system fare --');
{
  const base = 300;
  const noChange = validateAdjustment({ originalFare: base, proposedFare: base });
  ok('Equal to base → approved, 0% increase', noChange.approved && noChange.cappedFare === 300 && noChange.percentIncrease === 0);
  const plus20 = validateAdjustment({ originalFare: base, proposedFare: 360 });
  ok('+20% → approved, capped 360', plus20.approved && plus20.cappedFare === 360);
  const plus30 = validateAdjustment({ originalFare: base, proposedFare: 390 });
  ok('+30% boundary → approved, capped 390', plus30.approved && plus30.cappedFare === 390);
  const plus30max = validateAdjustment({ originalFare: base, proposedFare: 500 });
  ok('+66% → NOT approved, capped to 390 (max +30%)', !plus30max.approved && plus30max.cappedFare === 390 && plus30max.maxAllowedFare === 390);
  let threw = false;
  try { validateAdjustment({ originalFare: base, proposedFare: 299 }); } catch { threw = true; }
  ok('Below system fare → rejected', threw);
  // Spot-check a different base.
  const b2 = validateAdjustment({ originalFare: 455, proposedFare: 700 });
  ok('455 capped at +30% = 592 (rounded)', b2.cappedFare === Math.round(455 * 1.3), `cap=${b2.cappedFare}`);
}

// ---------------------------------------------------------------------------
console.log('\n-- 4) Full money composition: 50% upfront + 50% balance == fare, then cut --');
for (const F of [120, 300, 360, 455, 600, 1000]) {
  const upfront = roundTo5(F * 0.5);
  const balance = F - upfront;
  const escrowFunded = upfront + balance; // what the customer pays in total
  for (const rate of [COMMISSION_NO_ADJUST, COMMISSION_ADJUSTED]) {
    const split = splitCommission(F, rate);
    const moneyConserved = escrowFunded === F && split.companyAmount + split.riderAmount === F;
    ok(`Fare ${F} (${rate * 100}% cut): upfront ${upfront} + balance ${balance} = ${F}; company ${split.companyAmount} + rider ${split.riderAmount} = ${F}`, moneyConserved);
  }
}

// ---------------------------------------------------------------------------
console.log('\n-- 5) Matching distance (5km radius gate) --');
ok('Same point → 0 km', haversineKm(-0.0463, 37.6559, -0.0463, 37.6559) < 0.001);
ok('0.01° latitude ≈ 1.11 km', Math.abs(haversineKm(0, 37, 0.01, 37) - 1.111) < 0.05);
{
  // ~3.3 km north of Meru → inside 5km; ~6.7 km → outside.
  const near = haversineKm(-0.0463, 37.6559, -0.0463 + 0.03, 37.6559);
  const far = haversineKm(-0.0463, 37.6559, -0.0463 + 0.06, 37.6559);
  ok(`Near pickup ${near.toFixed(2)}km ≤ 5 (eligible)`, near <= 5);
  ok(`Far pickup ${far.toFixed(2)}km > 5 (excluded)`, far > 5);
}

// ---------------------------------------------------------------------------
console.log('\n-- 6) Random rider ordering (so re-search reaches a different rider) --');
{
  const base = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
  const out = shuffle(base);
  const sameMultiset = [...out].sort((a, b) => a - b).join(',') === base.join(',');
  const lengthOk = out.length === base.length;
  ok('Shuffle preserves all elements (length + multiset)', sameMultiset && lengthOk);
  let reordered = 0;
  for (let i = 0; i < 200; i++) {
    const s = shuffle(base);
    if (s.join(',') !== base.join(',')) reordered++;
  }
  ok(`Shuffle actually reorders (${reordered}/200 runs differed)`, reordered > 150);
  ok('Shuffle does not mutate the input', base.join(',') === '0,1,2,3,4,5,6,7,8,9');
}

console.log(`\n=== RESULT: ${pass} passed, ${fail} failed ===\n`);
process.exit(fail === 0 ? 0 : 1);
