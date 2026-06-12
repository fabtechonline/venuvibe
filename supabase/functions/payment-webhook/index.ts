// Public endpoint the gateway calls after a payment. It MUST verify the
// signature (inside gateway.parseWebhook) before trusting the payload. On a
// confirmed payment it flips the payment + booking to paid/confirmed.
//
// NOTE: deploy this function with --no-verify-jwt (gateways don't send a
// Supabase JWT). Verification happens via the gateway signature instead.
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";
import { getGateway } from "../_shared/gateway.ts";

Deno.serve(async (req) => {
  try {
    const gateway = getGateway();
    const result = await gateway.parseWebhook(req);

    // Unverifiable / irrelevant event — acknowledge so the gateway stops retrying.
    if (!result.paymentId) return new Response("ignored", { status: 200 });

    const db = supabaseAdmin();

    if (result.paid) {
      const { data: payment } = await db
        .from("payments")
        .update({
          status: "paid",
          gateway_ref: result.gatewayRef,
          updated_at: new Date().toISOString(),
        })
        .eq("id", result.paymentId)
        .select("booking_id")
        .single();

      if (payment?.booking_id) {
        await db
          .from("bookings")
          .update({ payment_status: "paid", status: "confirmed" })
          .eq("id", payment.booking_id);
      }
    } else {
      await db
        .from("payments")
        .update({ status: "failed", updated_at: new Date().toISOString() })
        .eq("id", result.paymentId);
    }

    return new Response("ok", { status: 200 });
  } catch (e) {
    return new Response(String(e), { status: 400 });
  }
});
