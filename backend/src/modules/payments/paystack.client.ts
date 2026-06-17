import crypto from 'node:crypto';
import axios, { AxiosInstance } from 'axios';
import { env } from '../../config/env';
import { AppError } from '../../utils/http';

/**
 * Thin Paystack REST wrapper. Amounts are in KES *kobo* (x100) per Paystack convention.
 * NOTE: the configured key is a LIVE key. Initialize/charge calls move real money — only
 * invoke them in real customer flows, never in tests.
 */
class PaystackClient {
  private http: AxiosInstance;

  constructor() {
    this.http = axios.create({
      baseURL: 'https://api.paystack.co',
      headers: {
        Authorization: `Bearer ${env.PAYSTACK_SECRET_KEY}`,
        'Content-Type': 'application/json',
      },
      timeout: 20_000,
    });
  }

  /** Create a transaction and return the checkout URL + reference. */
  async initializeTransaction(params: {
    email: string;
    amountKes: number;
    reference?: string;
    metadata?: Record<string, unknown>;
    callbackUrl?: string;
  }) {
    try {
      const { data } = await this.http.post('/transaction/initialize', {
        email: params.email,
        amount: Math.round(params.amountKes * 100), // to kobo
        currency: 'KES',
        reference: params.reference,
        metadata: params.metadata,
        callback_url: params.callbackUrl,
      });
      return data.data as { authorization_url: string; access_code: string; reference: string };
    } catch (e) {
      throw wrap(e, 'Paystack initialize failed');
    }
  }

  /** Verify a transaction by reference; returns normalized result. */
  async verifyTransaction(reference: string) {
    try {
      const { data } = await this.http.get(`/transaction/verify/${encodeURIComponent(reference)}`);
      const d = data.data;
      return {
        status: d.status as string, // 'success' | 'failed' | ...
        amountKes: Math.round((d.amount ?? 0) / 100),
        reference: d.reference as string,
        paidAt: d.paid_at as string | null,
        raw: d,
      };
    } catch (e) {
      throw wrap(e, 'Paystack verify failed');
    }
  }

  /**
   * Validates a webhook payload against the x-paystack-signature header.
   * Paystack signs the raw body with HMAC-SHA512 using your secret key.
   */
  verifyWebhookSignature(rawBody: Buffer, signature: string | undefined): boolean {
    if (!signature) return false;
    const hash = crypto
      .createHmac('sha512', env.PAYSTACK_SECRET_KEY)
      .update(rawBody)
      .digest('hex');
    return crypto.timingSafeEqual(Buffer.from(hash), Buffer.from(signature));
  }
}

function wrap(e: unknown, msg: string): AppError {
  if (axios.isAxiosError(e)) {
    return new AppError(e.response?.status ?? 502, `${msg}: ${e.response?.data?.message ?? e.message}`, 'paystack_error');
  }
  return new AppError(502, msg, 'paystack_error');
}

export const paystack = new PaystackClient();
