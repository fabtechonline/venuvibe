// ─────────────────────────────────────────────────────────────────────────
// Gateway-agnostic payment adapter.
//
// The rest of the backend talks only to the `PaymentGateway` interface, so
// choosing/swapping a provider is isolated to this file. When you pick a
// gateway, set the `PAYMENT_GATEWAY` secret and implement its adapter below
// (replace the matching `UnimplementedGateway`).
// ─────────────────────────────────────────────────────────────────────────

export interface CheckoutParams {
  paymentId: string; // our payments.id (use as the gateway's reference / m_payment_id)
  bookingId: string;
  amount: number; // major units, e.g. 38.50
  currency: string; // e.g. "ZAR"
  customerEmail?: string;
  returnUrl: string;
  cancelUrl: string;
}

export interface WebhookResult {
  paymentId: string | null; // our payments.id, resolved from the gateway payload
  gatewayRef: string | null; // the gateway's own transaction id
  paid: boolean;
}

export interface PaymentGateway {
  readonly name: string;
  /** Create a hosted checkout; return the URL to redirect the user to. */
  createCheckout(
    p: CheckoutParams,
  ): Promise<{ url: string; gatewayRef: string }>;
  /** Verify the signature of + parse an incoming webhook request. */
  parseWebhook(req: Request): Promise<WebhookResult>;
}

// Placeholder until a real adapter is written. Throws loudly if invoked.
class UnimplementedGateway implements PaymentGateway {
  constructor(readonly name: string) {}
  createCheckout(): Promise<{ url: string; gatewayRef: string }> {
    throw new Error(
      `Payment gateway "${this.name}" is not implemented yet. ` +
        `Implement it in supabase/functions/_shared/gateway.ts.`,
    );
  }
  parseWebhook(): Promise<WebhookResult> {
    throw new Error(
      `Webhook handling for "${this.name}" is not implemented yet.`,
    );
  }
}

// TODO(payments): implement the chosen adapter(s).
//
// PayFast (SA): createCheckout builds a signed redirect to
//   https://www.payfast.co.za/eng/process with m_payment_id = paymentId;
//   parseWebhook validates the ITN (source IP + signature + server confirm)
//   and maps pf_payment_id -> gatewayRef, m_payment_id -> paymentId.
//
// Paystack: createCheckout -> POST /transaction/initialize (returns
//   authorization_url); pass reference = paymentId; parseWebhook verifies the
//   x-paystack-signature HMAC and reads event "charge.success".
//
// Stripe: createCheckout -> Checkout Session with
//   metadata.payment_id = paymentId; parseWebhook verifies the
//   stripe-signature and handles "checkout.session.completed".

export function getGateway(): PaymentGateway {
  const name = (Deno.env.get("PAYMENT_GATEWAY") ?? "payfast").toLowerCase();
  switch (name) {
    case "payfast":
      return new UnimplementedGateway("payfast");
    case "paystack":
      return new UnimplementedGateway("paystack");
    case "stripe":
      return new UnimplementedGateway("stripe");
    default:
      return new UnimplementedGateway(name);
  }
}
