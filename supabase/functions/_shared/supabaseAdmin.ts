import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Service-role client — BYPASSES RLS. Only ever used inside Edge Functions.
// Never ship the service-role key to the app. `SUPABASE_URL` and
// `SUPABASE_SERVICE_ROLE_KEY` are injected automatically in deployed functions.
export function supabaseAdmin() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
}
