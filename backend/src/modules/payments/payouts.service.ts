import { randomUUID } from 'node:crypto';
import { supabaseAdmin } from '../../config/supabase';
import { badRequest, conflict, notFound } from '../../utils/http';
import { logger } from '../../utils/logger';
import { paystack } from './paystack.client';

/**
 * Processes a single pending rider payout via Paystack Transfer (M-Pesa). This
 * moves REAL money, so it is only ever invoked from the admin-guarded route — never
 * automatically. Marks the payout `processing` once Paystack accepts the transfer;
 * the final `completed`/`failed` state is confirmed by the transfer webhook.
 */
export async function processPayout(payoutId: string) {
  const { data: payout } = await supabaseAdmin
    .from('payouts')
    .select('id, rider_id, amount, mpesa_number, status')
    .eq('id', payoutId)
    .single();
  if (!payout) throw notFound('payout not found');
  if (payout.status !== 'pending') throw conflict(`payout is already ${payout.status}`);
  if (!payout.mpesa_number) throw badRequest('rider has no M-Pesa number on file');

  const { data: rider } = await supabaseAdmin.from('riders').select('profile_id').eq('id', payout.rider_id).single();
  const { data: prof } = await supabaseAdmin
    .from('profiles')
    .select('full_name')
    .eq('id', rider?.profile_id ?? '')
    .maybeSingle();

  const recipient = await paystack.createMpesaRecipient({
    name: prof?.full_name ?? 'U-Bike Rider',
    mpesaNumber: payout.mpesa_number,
  });
  const reference = `ubk_payout_${randomUUID()}`;
  const transfer = await paystack.initiateTransfer({
    amountKes: payout.amount,
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

  logger.info({ payoutId, amount: payout.amount, transferStatus: transfer.status }, 'payout processed');
  return { payoutId, amount: payout.amount, status: transfer.status, reference };
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
