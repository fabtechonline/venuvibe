// POST { bookingId, returnUrl?, cancelUrl? }  ->  { url, paymentId }
//
// Creates a pending payment for an existing booking and returns the gateway
// checkout URL to redirect the user to. The amount is read from the booking in
// the DB (never trusted from the client).
import { corsHeaders } from "../_shared/cors.ts";
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";
import { getGateway } from "../_shared/gateway.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const { bookingId, returnUrl, cancelUrl } = await req.json();
    if (!bookingId) return json({ error: "bookingId is required" }, 400);

    const db = supabaseAdmin();

    const { data: booking, error } = await db
      .from("bookings")
      .select("id, total_price, status, profiles(email)")
      .eq("id", bookingId)
      .single();
    if (error || !booking) return json({ error: "booking not found" }, 404);

    const gateway = getGateway();
    const currency = Deno.env.get("CURRENCY") ?? "ZAR";

    const { data: payment, error: pErr } = await db
      .from("payments")
      .insert({
        booking_id: booking.id,
        amount: booking.total_price,
        currency,
        gateway: gateway.name,
        status: "pending",
      })
      .select("id")
      .single();
    if (pErr || !payment) return json({ error: "could not start payment" }, 500);

    const { url, gatewayRef } = await gateway.createCheckout({
      paymentId: payment.id,
      bookingId: booking.id,
      amount: Number(booking.total_price),
      currency,
      // deno-lint-ignore no-explicit-any
      customerEmail: (booking as any).profiles?.email,
      returnUrl: returnUrl ?? Deno.env.get("PAYMENT_RETURN_URL") ?? "",
      cancelUrl: cancelUrl ?? Deno.env.get("PAYMENT_CANCEL_URL") ?? "",
    });

    await db
      .from("payments")
      .update({ gateway_ref: gatewayRef })
      .eq("id", payment.id);

    return json({ url, paymentId: payment.id });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
