-- ============================================================================
-- 0018 · Tenant SMTP email settings + booking email outbox
-- ----------------------------------------------------------------------------
-- Each venue can configure its OWN SMTP account; customers then receive
-- branded emails from the venue for booking events:
--   booking_request / booking_confirmed (incl. price breakdown = receipt),
--   booking_approved (with pay-by deadline), booking_rejected,
--   booking_cancelled, booking_rescheduled, and receipt (on payment rows).
--
-- Architecture: AFTER triggers render the emails into email_outbox; the
-- 'send-emails' Edge Function (deployed separately) connects to the tenant's
-- SMTP and delivers pending rows. A pg_cron job invokes it via pg_net every
-- minute when the outbox has pending rows. Email failures NEVER break the
-- booking write (triggers swallow their own errors).
--
-- Times in emails are rendered in Africa/Johannesburg (the platform's
-- wall-clock convention; resources.timezone is still unused).
-- SMTP passwords live in this table guarded by owner/admin-only RLS — same
-- trust level as the rest of the tenant's data. SAFE TO RE-RUN.
-- ============================================================================

-- ── 1) Per-tenant SMTP settings ──────────────────────────────────────────────
create table if not exists public.tenant_email_settings (
  tenant_id     uuid primary key references public.tenants(id) on delete cascade,
  enabled       boolean not null default false,
  smtp_host     text not null default '',
  smtp_port     int not null default 587 check (smtp_port between 1 and 65535),
  smtp_username text not null default '',
  smtp_password text not null default '',
  -- true = implicit TLS (usually port 465); false = plain/STARTTLS (587).
  use_tls       boolean not null default false,
  from_email    text not null default '',
  from_name     text not null default '',
  notify_bookings boolean not null default true,  -- new bookings & requests
  notify_status   boolean not null default true,  -- approved/rejected/cancelled/moved
  send_receipts   boolean not null default true,  -- payment receipts/invoices
  updated_at    timestamptz not null default now()
);

alter table public.tenant_email_settings enable row level security;

drop policy if exists tenant_email_settings_rw on public.tenant_email_settings;
create policy tenant_email_settings_rw on public.tenant_email_settings
  for all to authenticated
  using (
    public.get_user_role() = 'admin'
    or tenant_id in (
      select t.id from public.tenants t where t.owner_id = auth.uid()
    )
  )
  with check (
    public.get_user_role() = 'admin'
    or tenant_id in (
      select t.id from public.tenants t where t.owner_id = auth.uid()
    )
  );

-- ── 2) Outbox (written by triggers, delivered by the Edge Function) ──────────
create table if not exists public.email_outbox (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenants(id) on delete cascade,
  booking_id uuid references public.bookings(id) on delete set null,
  kind       text not null,
  to_email   text not null,
  to_name    text,
  subject    text not null,
  html       text not null,
  status     text not null default 'pending'
             check (status in ('pending', 'sending', 'sent', 'failed')),
  error      text,
  attempts   int not null default 0,
  created_at timestamptz not null default now(),
  sent_at    timestamptz
);

create index if not exists email_outbox_pending_idx
  on public.email_outbox (created_at)
  where status = 'pending';

alter table public.email_outbox enable row level security;

-- Owners/admin can see their venue's email log; all writes happen via the
-- definer triggers and the service-role Edge Function.
drop policy if exists email_outbox_select on public.email_outbox;
create policy email_outbox_select on public.email_outbox
  for select to authenticated
  using (
    public.get_user_role() = 'admin'
    or tenant_id in (
      select t.id from public.tenants t where t.owner_id = auth.uid()
    )
  );

-- ── 3) Rendering helpers ─────────────────────────────────────────────────────
create or replace function public.vv_email_wrap(p_title text, p_body text)
returns text
language sql
immutable
as $fn$
  select '<div style="font-family:Arial,Helvetica,sans-serif;max-width:520px;'
      || 'margin:0 auto;padding:24px">'
      || '<h2 style="color:#1B2A4A;margin:0 0 16px">' || p_title || '</h2>'
      || p_body
      || '<p style="color:#999;font-size:12px;margin-top:24px">'
      || 'Sent via VenueVibe on behalf of the venue.</p></div>';
$fn$;

create or replace function public.vv_fmt_when(p_start timestamptz, p_end timestamptz)
returns text
language sql
stable
as $fn$
  select to_char(p_start at time zone 'Africa/Johannesburg',
                 'Dy DD Mon YYYY, HH24:MI')
      || ' – '
      || to_char(p_end at time zone 'Africa/Johannesburg', 'HH24:MI');
$fn$;

create or replace function public.vv_fmt_amount(p numeric)
returns text
language sql
immutable
as $fn$
  select 'R ' || trim(to_char(coalesce(p, 0), '999999990.00'));
$fn$;

-- ── 4) Booking events → outbox ───────────────────────────────────────────────
create or replace function public.queue_booking_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_s public.tenant_email_settings%rowtype;
  v_tenant_id uuid;
  v_resource text;
  v_email text;
  v_name text;
  v_kind text;
  v_subject text;
  v_body text;
  v_when text;
  v_ref text;
begin
  if tg_op = 'INSERT' then
    v_kind := case new.status
      when 'confirmed' then 'booking_confirmed'
      when 'pending_approval' then 'booking_request'
      else null end;
  else
    if new.status is distinct from old.status then
      v_kind := case new.status
        when 'approved'  then 'booking_approved'
        when 'rejected'  then 'booking_rejected'
        when 'cancelled' then 'booking_cancelled'
        when 'confirmed' then 'booking_confirmed'
        else null end;
    elsif new.start_time is distinct from old.start_time
          and new.status = 'confirmed' then
      v_kind := 'booking_rescheduled';
    end if;
  end if;
  if v_kind is null then
    return new;
  end if;

  select r.tenant_id, r.name into v_tenant_id, v_resource
    from public.resources r where r.id = new.resource_id;
  if v_tenant_id is null then
    return new;
  end if;

  select * into v_s from public.tenant_email_settings
   where tenant_id = v_tenant_id and enabled;
  if not found or v_s.smtp_host = '' or v_s.from_email = '' then
    return new;
  end if;
  if v_kind in ('booking_request', 'booking_confirmed')
     and not v_s.notify_bookings then
    return new;
  end if;
  if v_kind in ('booking_approved', 'booking_rejected',
                'booking_cancelled', 'booking_rescheduled')
     and not v_s.notify_status then
    return new;
  end if;

  select p.email, p.full_name into v_email, v_name
    from public.profiles p where p.id = new.user_id;
  if v_email is null or v_email = '' then
    return new;
  end if;

  v_when := public.vv_fmt_when(new.start_time, new.end_time);
  v_ref := upper(left(new.id::text, 8));

  if v_kind = 'booking_request' then
    v_subject := 'We received your booking request — ' || v_resource;
    v_body := '<p>Hi ' || coalesce(v_name, 'there') || ',</p>'
      || '<p>Your custom booking request for <b>' || v_resource
      || '</b> on <b>' || v_when || '</b> has been received. '
      || 'The venue will review it — you only pay once it is approved.</p>'
      || '<p>Requested total: <b>'
      || public.vv_fmt_amount(new.total_price) || '</b><br>Ref: ' || v_ref
      || '</p>';
  elsif v_kind = 'booking_confirmed' then
    v_subject := 'Booking confirmed — ' || v_resource;
    v_body := '<p>Hi ' || coalesce(v_name, 'there') || ',</p>'
      || '<p>Your booking for <b>' || v_resource || '</b> on <b>' || v_when
      || '</b> is confirmed.</p>'
      || '<table style="border-collapse:collapse;font-size:14px">'
      || '<tr><td style="padding:2px 16px 2px 0">Venue price</td><td>'
      || public.vv_fmt_amount(new.base_price) || '</td></tr>'
      || case when new.addons_total > 0 then
           '<tr><td style="padding:2px 16px 2px 0">Add-ons</td><td>'
           || public.vv_fmt_amount(new.addons_total) || '</td></tr>'
         else '' end
      || case when new.discount_amount > 0 then
           '<tr><td style="padding:2px 16px 2px 0">Discount</td><td>−'
           || public.vv_fmt_amount(new.discount_amount) || '</td></tr>'
         else '' end
      || '<tr><td style="padding:2px 16px 2px 0">Platform fee</td><td>'
      || public.vv_fmt_amount(new.commission_amount) || '</td></tr>'
      || '<tr><td style="padding:2px 16px 2px 0"><b>Total</b></td><td><b>'
      || public.vv_fmt_amount(new.total_price) || '</b></td></tr></table>'
      || '<p>Ref: ' || v_ref || '</p>';
  elsif v_kind = 'booking_approved' then
    v_subject := 'Approved — pay to confirm your booking at ' || v_resource;
    v_body := '<p>Hi ' || coalesce(v_name, 'there') || ',</p>'
      || '<p>Great news: the venue approved your request for <b>'
      || v_resource || '</b> on <b>' || v_when || '</b>.</p>'
      || '<p>Total to pay: <b>' || public.vv_fmt_amount(new.total_price)
      || '</b></p>'
      || case when new.payment_due_at is not null then
           '<p><b>Pay by '
           || to_char(new.payment_due_at at time zone 'Africa/Johannesburg',
                      'Dy DD Mon YYYY, HH24:MI')
           || '</b> in the app, or the slot is released.</p>'
         else '' end
      || '<p>Ref: ' || v_ref || '</p>';
  elsif v_kind = 'booking_rejected' then
    v_subject := 'Booking request declined — ' || v_resource;
    v_body := '<p>Hi ' || coalesce(v_name, 'there') || ',</p>'
      || '<p>Unfortunately the venue declined your request for <b>'
      || v_resource || '</b> on <b>' || v_when || '</b>.</p>'
      || case when new.cancellation_reason is not null then
           '<p>Reason: ' || new.cancellation_reason || '</p>' else '' end
      || '<p>You have not been charged.</p>';
  elsif v_kind = 'booking_cancelled' then
    v_subject := 'Booking cancelled — ' || v_resource;
    v_body := '<p>Hi ' || coalesce(v_name, 'there') || ',</p>'
      || '<p>Your booking for <b>' || v_resource || '</b> on <b>' || v_when
      || '</b> has been cancelled.</p>'
      || case when new.cancellation_reason is not null then
           '<p>Reason: ' || new.cancellation_reason || '</p>' else '' end
      || '<p>Ref: ' || v_ref || '</p>';
  else -- booking_rescheduled
    v_subject := 'Booking moved — ' || v_resource;
    v_body := '<p>Hi ' || coalesce(v_name, 'there') || ',</p>'
      || '<p>Your booking for <b>' || v_resource
      || '</b> now takes place on <b>' || v_when || '</b>.</p>'
      || '<p>Ref: ' || v_ref || '</p>';
  end if;

  insert into public.email_outbox
    (tenant_id, booking_id, kind, to_email, to_name, subject, html)
  values
    (v_tenant_id, new.id, v_kind, v_email, v_name, v_subject,
     public.vv_email_wrap(v_subject, v_body));
  return new;
exception when others then
  -- Email queueing must never break the booking write.
  raise warning 'queue_booking_email failed: %', sqlerrm;
  return new;
end;
$fn$;

drop trigger if exists bookings_queue_email on public.bookings;
create trigger bookings_queue_email
  after insert or update on public.bookings
  for each row execute function public.queue_booking_email();

-- ── 5) Payment rows → receipt email ──────────────────────────────────────────
create or replace function public.queue_receipt_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_s public.tenant_email_settings%rowtype;
  v_b public.bookings%rowtype;
  v_tenant_id uuid;
  v_resource text;
  v_email text;
  v_name text;
  v_subject text;
  v_body text;
begin
  if new.status <> 'paid' then
    return new;
  end if;
  select * into v_b from public.bookings where id = new.booking_id;
  if not found then
    return new;
  end if;
  select r.tenant_id, r.name into v_tenant_id, v_resource
    from public.resources r where r.id = v_b.resource_id;
  if v_tenant_id is null then
    return new;
  end if;
  select * into v_s from public.tenant_email_settings
   where tenant_id = v_tenant_id and enabled and send_receipts;
  if not found or v_s.smtp_host = '' or v_s.from_email = '' then
    return new;
  end if;
  select p.email, p.full_name into v_email, v_name
    from public.profiles p where p.id = v_b.user_id;
  if v_email is null or v_email = '' then
    return new;
  end if;

  v_subject := 'Receipt — ' || v_resource;
  v_body := '<p>Hi ' || coalesce(v_name, 'there') || ',</p>'
    || '<p>Thank you for your payment.</p>'
    || '<table style="border-collapse:collapse;font-size:14px">'
    || '<tr><td style="padding:2px 16px 2px 0">Booking</td><td>'
    || v_resource || '</td></tr>'
    || '<tr><td style="padding:2px 16px 2px 0">When</td><td>'
    || public.vv_fmt_when(v_b.start_time, v_b.end_time) || '</td></tr>'
    || '<tr><td style="padding:2px 16px 2px 0">Amount paid</td><td><b>'
    || public.vv_fmt_amount(new.amount) || '</b></td></tr>'
    || '<tr><td style="padding:2px 16px 2px 0">Date</td><td>'
    || to_char(now() at time zone 'Africa/Johannesburg', 'DD Mon YYYY, HH24:MI')
    || '</td></tr>'
    || '<tr><td style="padding:2px 16px 2px 0">Reference</td><td>'
    || upper(left(v_b.id::text, 8)) || '</td></tr></table>'
    || '<p>This serves as your proof of payment.</p>';

  insert into public.email_outbox
    (tenant_id, booking_id, kind, to_email, to_name, subject, html)
  values
    (v_tenant_id, v_b.id, 'receipt', v_email, v_name, v_subject,
     public.vv_email_wrap(v_subject, v_body));
  return new;
exception when others then
  raise warning 'queue_receipt_email failed: %', sqlerrm;
  return new;
end;
$fn$;

drop trigger if exists payments_queue_receipt on public.payments;
create trigger payments_queue_receipt
  after insert on public.payments
  for each row execute function public.queue_receipt_email();

-- ── 6) Deliver pending mail: pg_cron pings the Edge Function via pg_net ──────
-- The anon key below is the app's public publishable key (already shipped in
-- the client); the Edge Function does its real work with the service role.
do $do$
begin
  create extension if not exists pg_net;
  perform cron.unschedule('process-email-outbox')
   where exists (select 1 from cron.job where jobname = 'process-email-outbox');
  perform cron.schedule(
    'process-email-outbox',
    '* * * * *',
    $cmd$
    select net.http_post(
      url := 'https://tlzhxzhrhuxqmtsuaaiz.supabase.co/functions/v1/send-emails',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRsemh4emhyaHV4cW10c3VhYWl6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEyNTg3MzYsImV4cCI6MjA4NjgzNDczNn0.OCtkUnUzvksYS43fziutx7h496VDWmVgOPsdOBIschE'
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 30000
    )
    where exists (select 1 from public.email_outbox where status = 'pending');
    $cmd$
  );
exception when others then
  raise notice 'pg_net/pg_cron scheduling unavailable (%); invoke the '
    'send-emails function manually or from the app', sqlerrm;
end $do$;
