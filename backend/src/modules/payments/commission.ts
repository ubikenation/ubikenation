import { env } from '../../config/env';

export interface CommissionSplit {
  gross: number; // total fare in KES
  companyAmount: number; // 20%
  riderAmount: number; // 80%
  rate: number;
}

/**
 * Splits a completed trip/errand fare between company and rider.
 * Company takes COMMISSION_RATE (default 20%); rider receives the remainder.
 * Company share is rounded to the nearest shilling; rider gets the exact remainder
 * so the two always sum back to `gross` (no lost/created cents).
 */
export function splitCommission(gross: number): CommissionSplit {
  if (gross < 0) throw new Error('gross must be non-negative');
  const rate = env.COMMISSION_RATE;
  const companyAmount = Math.round(gross * rate);
  const riderAmount = gross - companyAmount;
  return { gross, companyAmount, riderAmount, rate };
}
