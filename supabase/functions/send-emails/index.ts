// send-emails — delivers pending email_outbox rows via each tenant's own
// SMTP account (tenant_email_settings), and handles "send test email" from
// the tenant portal. Invoked every minute by pg_cron (via pg_net) whenever
// the outbox has pending rows; any authenticated JWT may invoke it — the
// real work happens with the service role and only touches queued rows.
//
// Body:
//   {}                                → process pending outbox rows
//   { "test": { "tenant_id": uuid } } → verify caller owns the tenant, then
//                                       send a test email to from_email.
import { createClient } from "npm:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type Settings = {
  tenant_id: string;
  enabled: boolean;
  smtp_host: string;
  smtp_port: number;
  smtp_username: string;
  smtp_password: string;
  use_tls: boolean;
  from_email: string;
  from_name: string;
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function smtpClient(s: Settings): SMTPClient {
  return new SMTPClient({
    connection: {
      hostname: s.smtp_host,
      port: s.smtp_port,
      tls: s.use_tls,
      auth: { username: s.smtp_username, password: s.smtp_password },
    },
  });
}

async function sendOne(
  s: Settings,
  to: string,
  toName: string | null,
  subject: string,
  html: string,
): Promise<void> {
  const client = smtpClient(s);
  try {
    await client.send({
      from: s.from_name ? `${s.from_name} <${s.from_email}>` : s.from_email,
      to: toName ? `${toName} <${to}>` : to,
      subject,
      content: "auto",
      html,
    });
  } finally {
    try {
      await client.close();
    } catch (_) {
      // closing failures don't matter once the message is out
    }
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let body: { test?: { tenant_id?: string } } = {};
  try {
    body = await req.json();
  } catch (_) {
    // empty body = process the outbox
  }

  // ── Test email from the tenant portal ──────────────────────────────────
  if (body?.test?.tenant_id) {
    const jwt = req.headers.get("Authorization")?.replace("Bearer ", "") ?? "";
    const { data: userData } = await admin.auth.getUser(jwt);
    const uid = userData?.user?.id;
    if (!uid) return json({ error: "Not authenticated" }, 401);

    const tenantId = body.test.tenant_id;
    const { data: tenant } = await admin
      .from("tenants")
      .select("id, owner_id, name")
      .eq("id", tenantId)
      .single();
    if (!tenant) return json({ error: "Venue not found" }, 404);
    if (tenant.owner_id !== uid) {
      const { data: prof } = await admin
        .from("profiles")
        .select("role")
        .eq("id", uid)
        .single();
      if (prof?.role !== "admin") return json({ error: "Not your venue" }, 403);
    }

    const { data: s } = await admin
      .from("tenant_email_settings")
      .select("*")
      .eq("tenant_id", tenantId)
      .single();
    if (!s || !s.smtp_host || !s.from_email) {
      return json({ error: "Save your SMTP settings first" }, 400);
    }
    try {
      await sendOne(
        s as Settings,
        s.from_email,
        s.from_name || null,
        "VenueVibe test email",
        `<div style="font-family:Arial,sans-serif;padding:16px">` +
          `<h2>It works!</h2><p>The SMTP settings for <b>${tenant.name}</b> ` +
          `are valid. Booking emails will be sent from this address.</p></div>`,
      );
      return json({ ok: true, sent_to: s.from_email });
    } catch (e) {
      return json({ error: `SMTP failed: ${String(e)}` }, 400);
    }
  }

  // ── Process the outbox ─────────────────────────────────────────────────
  // Requeue rows stuck in 'sending' (an earlier invocation died mid-flight).
  await admin
    .from("email_outbox")
    .update({ status: "pending" })
    .eq("status", "sending")
    .lt("created_at", new Date(Date.now() - 10 * 60_000).toISOString());

  const { data: pending, error: selErr } = await admin
    .from("email_outbox")
    .select("*")
    .eq("status", "pending")
    .order("created_at")
    .limit(25);
  if (selErr) return json({ error: selErr.message }, 500);
  if (!pending?.length) return json({ ok: true, sent: 0 });

  const ids = pending.map((r) => r.id);
  await admin.from("email_outbox").update({ status: "sending" }).in("id", ids);

  const tenantIds = [...new Set(pending.map((r) => r.tenant_id))];
  const { data: settingsRows } = await admin
    .from("tenant_email_settings")
    .select("*")
    .in("tenant_id", tenantIds);
  const settings = new Map(
    (settingsRows ?? []).map((s) => [s.tenant_id, s as Settings]),
  );

  let sent = 0;
  let failed = 0;
  for (const row of pending) {
    const s = settings.get(row.tenant_id);
    if (!s || !s.enabled || !s.smtp_host || !s.from_email) {
      await admin
        .from("email_outbox")
        .update({ status: "failed", error: "Email settings disabled/missing" })
        .eq("id", row.id);
      failed++;
      continue;
    }
    try {
      await sendOne(s, row.to_email, row.to_name, row.subject, row.html);
      await admin
        .from("email_outbox")
        .update({
          status: "sent",
          sent_at: new Date().toISOString(),
          attempts: row.attempts + 1,
          error: null,
        })
        .eq("id", row.id);
      sent++;
    } catch (e) {
      const attempts = row.attempts + 1;
      await admin
        .from("email_outbox")
        .update({
          // three strikes, then stop retrying
          status: attempts >= 3 ? "failed" : "pending",
          attempts,
          error: String(e).slice(0, 500),
        })
        .eq("id", row.id);
      failed++;
    }
  }
  return json({ ok: true, sent, failed });
});
