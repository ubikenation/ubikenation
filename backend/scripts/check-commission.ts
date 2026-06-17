import { splitCommission } from '../src/modules/payments/commission';
const cases = [1000, 360, 120, 455, 333];
for (const g of cases) {
  const s = splitCommission(g);
  const okSum = s.companyAmount + s.riderAmount === g;
  console.log(`KES ${g} -> company ${s.companyAmount} (20%) + rider ${s.riderAmount} (80%) | sums=${okSum}`);
}
process.exit(0);
