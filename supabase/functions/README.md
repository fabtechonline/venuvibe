# Payment backend (Edge Functions) — scaffold

Gateway-**agnostic** scaffold for Phase 2 booking payments. The flow and DB
writes are done; the only gap is the gateway-specific code in
[`_shared/gateway.ts`](./_shared/gateway.ts). Nothing here is deployed yet.

```
functions/
  _shared/
    cors.ts            CORS headers
    supabaseAdmin.ts   service-role client (bypasses RLS)
    gateway.ts         PaymentGateway interface + adapter switch  ← implement here
  create-checkout-session/index.ts   booking → pending payment → checkout URL
  payment-webhook/index.ts           gateway callback → mark paid + confirm booking
```

## The flow (once a gateway is implemented)
1. App creates a booking as **pending/unpaid** (today `checkout_screen` hardcodes
   `payment_status: 'paid'` — switch it to pending when wiring this).
2. App calls **`create-checkout-session`** with `{ bookingId }`; gets back a
   `{ url }` and redirects the user (in-app browser / external).
3. User pays on the gateway's page.
4. Gateway calls **`payment-webhook`**; it verifies the signature, marks the
   `payments` row `paid`, and flips the booking to `payment_status='paid',
   status='confirmed'`.
5. App returns and refreshes the booking (now confirmed).

`payments` table = migration `0008_payments_table.sql` (already applied).

## To go live
1. **Pick the gateway** and implement its adapter in `_shared/gateway.ts`
   (replace the matching `UnimplementedGateway`). TODO notes for PayFast /
   Paystack / Stripe are in that file.
2. **Set secrets:**
   ```bash
   supabase secrets set PAYMENT_GATEWAY=payfast CURRENCY=ZAR \
     PAYMENT_RETURN_URL=... PAYMENT_CANCEL_URL=... \
     # + the gateway's own keys, e.g. PAYFAST_MERCHANT_ID / PAYFAST_PASSPHRASE
   ```
   (`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.)
3. **Deploy:**
   ```bash
   supabase functions deploy create-checkout-session
   supabase functions deploy payment-webhook --no-verify-jwt
   ```
   `--no-verify-jwt` on the webhook because gateways don't send a Supabase JWT;
   it's authenticated by the gateway signature instead.
4. Register the webhook URL
   (`https://<ref>.functions.supabase.co/payment-webhook`) in the gateway dashboard.

## Local
```bash
supabase functions serve create-checkout-session
```
