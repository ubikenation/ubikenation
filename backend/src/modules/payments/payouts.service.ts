import { randomUUID } from 'node:crypto';
import { env } from '../../config/env';
import { supabaseAdmin } from '../../config/supabase';
import { badRequest, conflict, notFound } from '../../utils/http';
import { logger } from '../../utils/logger';
import { applyWallet } from '../wallet/wallet.service';
import { paystack } from './paystack.client';

/**
 * Processes a single pending rider payout via Paystack Transfer (M-Pesa). Moves REAL
 * money, so it's hardened for both the admin route AND the automatic scheduler:
 *  1) atomically CLAIM the payout (pending → processing) so two runners can't both
 *     process it (the update only matches a still-`pending` row);
 *  2) RESERVE the funds by debiting the rider's in-app wallet;
 *  3) transfer to M-Pesa. On any failure we credit the wallet back and release the
 *     claim (→ pending) so it retries on the next tick — money is never lost or
 *     double-sent.
 */
export async function processPayout(payoutId: string) {
  // 1) Atomic claim — only one runner wins.
  const { data: claimed } = await supabaseAdmin
    .from('payouts')
    .update({ status: 'processing' })
    .eq('id', payoutId)
    .eq('status', 'pending')
    .select('id, rider_id, amount, mpesa_number, trip_id')
    .maybeSingle();
  if (!claimed) {
    const { data: cur } = await supabaseAdmin.from('payouts').select('status').eq('id', payoutId).maybeSingle();
    throw conflict(`payout is already ${cur?.status ?? 'missing'}`);
  }

  const release = () => supabaseAdmin.from('payouts').update({ status: 'pending' }).eq('id', payoutId);

  if (!claimed.mpesa_number) {
    await release();
    throw badRequest('rider has no M-Pesa number on file');
  }

  const { data: rider } = await supabaseAdmin.from('riders').select('profile_id').eq('id', claimed.rider_id).single();
  const { data: prof } = await supabaseAdmin
    .from('profiles')
    .select('full_name')
    .eq('id', rider?.profile_id ?? '')
    .maybeSingle();

  // 2) Reserve funds from the rider's wallet before sending real money.
  if (rider?.profile_id) {
    try {
      await applyWallet({
        profileId: rider.profile_id,
        direction: 'debit',
        amount: claimed.amount,
        reason: `Payout to M-Pesa${claimed.trip_id ? ` for trip ${claimed.trip_id}` : ''}`,
        tripId: claimed.trip_id ?? undefined,
      });
    } catch (e) {
      await release();
      throw badRequest(`cannot pay out: ${(e as Error).message}`);
    }
  }

  // 3) Transfer to M-Pesa. Credit the wallet back + release on failure.
  try {
    const recipient = await paystack.createMpesaRecipient({
      name: prof?.full_name ?? 'U-Bike Rider',
      mpesaNumber: claimed.mpesa_number,
    });
    const reference = `ubk_payout_${randomUUID()}`;
    const transfer = await paystack.initiateTransfer({
      amountKes: claimed.amount,
      recipientCode: recipient.recipient_code,
      reason: 'U-Bike rider earnings',
      reference,
    });

    await supabaseAdmin
      .from('payouts')
      .update({
        status: transfer.status === 'success' ? 'completed' : 'processing',
        reference,
        processed_at: new Date().toISOString(),
      })
      .eq('id', payoutId);

    logger.info({ payoutId, amount: claimed.amount, transferStatus: transfer.status }, 'payout processed');
    return { payoutId, amount: claimed.amount, status: transfer.status, reference };
  } catch (e) {
    if (rider?.profile_id) {
      await applyWallet({
        profileId: rider.profile_id,
        direction: 'credit',
        amount: claimed.amount,
        reason: `Payout reversed (transfer failed)${claimed.trip_id ? ` for trip ${claimed.trip_id}` : ''}`,
        tripId: claimed.trip_id ?? undefined,
      }).catch((err) => logger.error({ payoutId, err: (err as Error).message }, 'wallet credit-back failed'));
    }
    await release();
    logger.error({ payoutId, err: (e as Error).message }, 'payout transfer failed; reverted to pending');
    throw e;
  }
}

/**
 * Automatic payout run: sends every rider payout that has been pending for at least
 * AUTO_PAYOUT_DELAY_HOURS (default 48h after the trip completed). Called by the
 * in-process scheduler and by POST /api/plans/run-due. No-op unless
 * AUTO_PAYOUT_ENABLED=true (real money is off by default until Paystack is verified).
 */
export async function runDuePayouts() {
  if (!env.AUTO_PAYOUT_ENABLED) return { processed: 0, failed: 0, disabled: true };
  const cutoff = new Date(Date.now() - env.AUTO_PAYOUT_DELAY_HOURS * 3_600_000).toISOString();
  const { data: due } = await supabaseAdmin
    .from('payouts')
    .select('id')
    .eq('status', 'pending')
    .lte('created_at', cutoff)
    .limit(50);

  let processed = 0;
  let failed = 0;
  for (const p of due ?? []) {
    try {
      await processPayout(p.id);
      processed++;
    } catch (e) {
      failed++;
      logger.warn({ payoutId: p.id, err: (e as Error).message }, 'due payout failed (will retry)');
    }
  }
  if (processed || failed) logger.info({ processed, failed }, 'auto-payouts run');
  return { processed, failed };
}

/**
 * Reconciles a payout from a Paystack transfer webhook event. `transfer.success`
 * marks it completed; `transfer.failed`/`transfer.reversed` flips it back to pending
 * so it can be retried. Matched by the transfer reference we set at initiation.
 */
export async function reconcileTransfer(reference: string, event: string) {
  const status = event === 'transfer.success' ? 'completed' : 'pending';
  const { data } = await supabaseAdmin
    .from('payouts')
    .update({ status, processed_at: status === 'completed' ? new Date().toISOString() : null })
    .eq('reference', reference)
    .select('id')
    .maybeSingle();
  if (data) logger.info({ payoutId: data.id, event, status }, 'payout transfer reconciled');
  return { matched: !!data, status };
}

/** Admin "mark as paid manually" — for payouts settled out-of-band (e.g. direct M-Pesa). */
export async function markPayoutPaid(payoutId: string) {
  const { data: payout } = await supabaseAdmin.from('payouts').select('id, status').eq('id', payoutId).single();
  if (!payout) throw notFound('payout not found');
  if (payout.status === 'completed') return { ok: true, alreadyPaid: true };
  await supabaseAdmin
    .from('payouts')
    .update({ status: 'completed', processed_at: new Date().toISOString() })
    .eq('id', payoutId);
  return { ok: true };
}
