import { paystack } from '../src/modules/payments/paystack.client';
(async () => {
  try {
    const r = await paystack.initializeTransaction({ email: 'customer@gmail.com', amountKes: 100, reference: 'ubk_probe_' + Date.now() });
    console.log('PAYSTACK_OK url=' + (r.authorization_url ? 'yes' : 'no'), 'ref=' + r.reference);
  } catch (e) {
    console.log('PAYSTACK_ERR', (e as Error).message);
  }
  process.exit(0);
})();
