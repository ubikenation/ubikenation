import { supabaseAdmin } from '../../config/supabase';
import { AppError } from '../../utils/http';

export type LedgerDirection = 'credit' | 'debit';

interface ApplyArgs {
  profileId: string;
  direction: LedgerDirection;
  amount: number;
  reason: string;
  tripId?: string;
  paymentId?: string;
}

/**
 * Atomically mutates a wallet and writes a ledger row via the `wallet_apply`
 * Postgres function (row-locked, overdraft-guarded). Returns the new balance.
 */
export async function applyWallet(args: ApplyArgs): Promise<number> {
  const { data, error } = await supabaseAdmin.rpc('wallet_apply', {
    p_profile: args.profileId,
    p_direction: args.direction,
    p_amount: args.amount,
    p_reason: args.reason,
    p_trip: args.tripId ?? null,
    p_payment: args.paymentId ?? null,
  });
  if (error) {
    const insufficient = error.message?.includes('insufficient');
    throw new AppError(insufficient ? 400 : 500, error.message, insufficient ? 'insufficient_funds' : 'wallet_error');
  }
  return data as number;
}

export async function getWallet(profileId: string) {
  const { data } = await supabaseAdmin
    .from('wallets')
    .select('balance, pending, updated_at')
    .eq('profile_id', profileId)
    .maybeSingle();
  return data ?? { balance: 0, pending: 0, updated_at: null };
}

export async function getLedger(profileId: string, limit = 50) {
  const { data } = await supabaseAdmin
    .from('wallet_ledger')
    .select('id, direction, amount, balance_after, reason, trip_id, created_at')
    .eq('profile_id', profileId)
    .order('created_at', { ascending: false })
    .limit(limit);
  return data ?? [];
}
