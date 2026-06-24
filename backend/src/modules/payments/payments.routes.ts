import { Router, type Request } from 'express';
import { z } from 'zod';
import { handler, ok, badRequest } from '../../utils/http';
import { requireAuth } from '../../middleware/auth';
import { logger } from '../../utils/logger';
import { initiatePayment, settlePayment } from './payments.service';
import { reconcileTransfer } from './payouts.service';
import { paystack } from './paystack.client';
import { getLedger, getWallet } from '../wallet/wallet.service';

export const paymentsRouter = Router();

const initSchema = z.object({
  purpose: z.enum(['trip_upfront', 'trip_balance', 'wallet_topup', 'rider_registration']),
  amount: z.number().positive(),
  tripId: z.string().uuid().optional(),
  callbackUrl: z.string().url().optional(),
});

// POST /api/payments/initiate — create a Paystack checkout for the authed user.
paymentsRouter.post(
  '/initiate',
  requireAuth,
  handler(async (req, res) => {
    const body = initSchema.parse(req.body);
    const email = req.user!.email;
    if (!email) throw badRequest('account has no email for payment');
    const result = await initiatePayment({
      profileId: req.user!.id,
      email,
      purpose: body.purpose,
      amount: body.amount,
      tripId: body.tripId,
      callbackUrl: body.callbackUrl,
    });
    ok(res, result, 201);
  }),
);

// GET /api/payments/wallet — balance + recent ledger.
paymentsRouter.get(
  '/wallet',
  requireAuth,
  handler(async (req, res) => {
    const [wallet, ledger] = await Promise.all([getWallet(req.user!.id), getLedger(req.user!.id)]);
    ok(res, { wallet, ledger });
  }),
);

// POST /api/payments/verify/:reference — client-driven confirmation fallback.
paymentsRouter.post(
  '/verify/:reference',
  requireAuth,
  handler(async (req, res) => {
    await settlePayment(req.params.reference);
    ok(res, { settled: true });
  }),
);

// POST /api/payments/webhook — Paystack server-to-server callback (no auth; HMAC-verified).
paymentsRouter.post(
  '/webhook',
  handler(async (req, res) => {
    const raw = (req as Request & { rawBody?: Buffer }).rawBody;
    const signature = req.headers['x-paystack-signature'] as string | undefined;
    if (!raw || !paystack.verifyWebhookSignature(raw, signature)) {
      return res.status(401).json({ success: false, error: { code: 'bad_signature' } });
    }
    const event = req.body;
    const ref = event?.data?.reference;
    try {
      if (event?.event === 'charge.success' && ref) {
        await settlePayment(ref);
      } else if (['transfer.success', 'transfer.failed', 'transfer.reversed'].includes(event?.event) && ref) {
        // Rider payout settlement (M-Pesa) — reconcile against the payouts table.
        await reconcileTransfer(ref, event.event);
      }
    } catch (e) {
      logger.error({ e, ref, event: event?.event }, 'webhook handling failed');
    }
    // Always 200 quickly so Paystack does not retry-storm.
    res.status(200).json({ received: true });
  }),
);
