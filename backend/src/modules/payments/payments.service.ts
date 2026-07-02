import { randomUUID } from 'node:crypto';
import { supabaseAdmin } from '../../config/supabase';
import { AppError, badRequest } from '../../utils/http';
import { logger } from '../../utils/logger';
import { applyWallet } from '../wallet/wallet.service';
import { paystack } from './paystack.client';
import { holdEscrow, releaseEscrow } from './escrow.service';

export type PaymentPurpose = 'trip_upfront' | 'trip_balance' | 'wallet_topup' | 'rider_registration';

interface InitArgs {
  profileId: string;
  email: string;
  purpose: PaymentPurpose;
  amount: number;
  tripId?: string;
  callbackUrl?: string;
}

/**
 * Creates a pending payment row and a Paystack checkout session.
 * The actual money is only confirmed later via the verified webhook.
 */
export async function initiatePayment(args: InitArgs) {
  if (args.amount <= 0) throw badRequest('amount must be positive');
  const reference = `ubk_${args.purpose}_${randomUUID()}`;

  const { data: payment, error } = await supabaseAdmin
    .from('payments')
    .insert({
      profile_id: args.profileId,
      trip_id: args.tripId ?? null,
      purpose: args.purpose,
      amount: args.amount,
      status: 'pending',
      paystack_ref: reference,
    })
    .select('id')
    .single();
  if (error) throw new AppError(500, `could not create payment: ${error.message}`);

  const session = await paystack.initializeTransaction({
    email: args.email,
    amountKes: args.amount,
    reference,
    callbackUrl: args.callbackUrl,
    metadata: { paymentId: payment.id, purpose: args.purpose, tripId: args.tripId ?? null },
  });

  await supabaseAdmin
    .from('payments')
    .update({ authorization_url: session.authorization_url, paystack_access_code: session.access_code })
    .eq('id', payment.id);

  return { paymentId: payment.id, reference, authorizationUrl: session.authorization_url };
}

/**
 * Idempotently settles a payment after Paystack confirms success.
 * Routes the money according to its purpose (escrow, wallet, registration).
 */
export async function settlePayment(reference: string) {
  const { data: payment } = await supabaseAdmin
    .from('payments')
    .select('id, profile_id, trip_id, purpose, amount, status')
    .eq('paystack_ref', reference)
    .single();
  if (!payment) throw new AppError(404, 'payment not found');
  if (payment.status === 'success') return; // already settled

  const verified = await paystack.verifyTransaction(reference);
  if (verified.status !== 'success') {
    await supabaseAdmin.from('payments').update({ status: 'failed' }).eq('id', payment.id);
    throw new AppError(402, 'payment not successful');
  }
  if (verified.amountKes < payment.amount) {
    throw new AppError(402, 'paid amount is less than expected');
  }

  await supabaseAdmin
    .from('payments')
    .update({ status: 'success', raw_event: verified.raw })
    .eq('id', payment.id);

  switch (payment.purpose) {
    case 'trip_upfront':
      // Upfront 50% paid after the rider's quote was accepted → the rider is now
      // en route. (Matching already happened; payment confirms the booking.)
      if (payment.trip_id) {
        await holdEscrow(payment.trip_id, payment.amount);
        await supabaseAdmin.from('trips').update({ status: 'rider_assigned' }).eq('id', payment.trip_id);
      }
      break;
    case 'trip_balance':
      // Balance 50% paid once the customer reached the destination → the full fare
      // is now in escrow; release it (20/80 or 25/75) and complete the trip.
      if (payment.trip_id) {
        await holdEscrow(payment.trip_id, payment.amount);
        await supabaseAdmin
          .from('trips')
          .update({ status: 'completed', completed_at: new Date().toISOString() })
          .eq('id', payment.trip_id)
          .neq('status', 'completed');
        await releaseEscrow(payment.trip_id);
      }
      break;
    case 'wallet_topup':
      await applyWallet({
        profileId: payment.profile_id,
        direction: 'credit',
        amount: payment.amount,
        reason: 'Wallet top-up',
        paymentId: payment.id,
      });
      break;
    case 'rider_registration':
      await supabaseAdmin
        .from('riders')
        .update({ registration_paid: true, registration_payment_id: payment.id })
        .eq('profile_id', payment.profile_id);
      // The registration fee is company income → company wallet (then auto-swept to
      // the company M-Pesa on the same schedule as commission). rate 1.0 = 100% company.
      if (payment.amount > 0) {
        const { error: clErr } = await supabaseAdmin.from('company_ledger').insert({
          trip_id: null,
          amount: payment.amount,
          rate: 1.0,
          reason: `Rider registration fee (profile ${payment.profile_id})`,
        });
        if (clErr) logger.error({ err: clErr.message }, 'company_ledger registration credit failed');
      }
      break;
  }

  logger.info({ reference, purpose: payment.purpose }, 'payment settled');
}
