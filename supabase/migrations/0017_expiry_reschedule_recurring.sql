-- ============================================================================
-- 0017 · Approval expiry + booking reschedule + recurring (weekly) bookings
-- ----------------------------------------------------------------------------
-- 1) Approval expiry: approving a custom request now stamps payment_due_at
--    (platform_settings.payment_window_hours, default 24h). Past the deadline
--    the hold is released: expire_stale_bookings() cancels approved-unpaid
--    bookings and rejects pending requests whose start time has passed.
--    Scheduled via pg_cron every 10 minutes (best effort — the app also calls
--    it lazily when loading My Bookings), and pay_booking_placeholder refuses
--    expired bookings as the race-proof guard.
-- 2) reschedule_booking(): a customer moves their upcoming confirmed slot
--    booking to a new time of the SAME length. Repriced from the new date's
--    pricing season (placeholder-pay world; a real gateway needs delta
--    handling here). The no-overlap constraint stays the hard gate.
-- 3) create_recurring_bookings(): weekly series (2–12 occurrences) of one
--    slot. Weekly only: every occurrence shares the first slot's weekday, so
--    the client-side trading-hours validation of occurrence 1 holds for all.
--    Each occurrence is priced by ITS date's season (tier matched by
--    minutes); conflicts/missing pricing across the series abort the whole
--    request with the offending dates listed. Rows share recurring_group_id.
-- SAFE TO RE-RUN (the whole batch runs in one transaction via the API).
-- ============================================================================

-- ── 1a) Columns ───────────────────────────────────────────────────────────────
alter table public.bookings
  add column if not exists payment_due_at timestamptz,
  add column if not exists recurring_group_id uuid;

create index if not exists bookings_recurring_group_idx
  on public.bookings (recurring_group_id)
  where recurring_group_id is not null;

alter table public.platform_settings
  add column if not exists payment_window_hours int not null default 24;

-- ── 1b) Approval stamps the payment deadline ─────────────────────────────────
create or replace function public.approve_custom_booking(
  p_booking_id uuid,
  p_final_total numeric default null,   -- new venue price (excl. add-ons & fee)
  p_hourly_rate numeric default null    -- or derive it from a new hourly rate
)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_b public.bookings%rowtype;
  v_minutes numeric;
  v_new_base numeric(10,2);
  v_base numeric(10,2);
  v_discount numeric(10,2) := 0;
  v_rate numeric;
  v_commission numeric(10,2);
  v_resource_name text;
  v_window int;
begin
  select * into v_b from public.bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Booking not found';
  end if;

  if public.get_user_role() <> 'admin' and not exists (
    select 1 from public.resources r
    join public.tenants t on t.id = r.tenant_id
    where r.id = v_b.resource_id and t.owner_id = auth.uid()
  ) then
    raise exception 'Only the venue owner can approve this booking';
  end if;

  if v_b.status <> 'pending_approval' then
    raise exception 'Booking is not awaiting approval (status: %)', v_b.status;
  end if;

  v_minutes := extract(epoch from (v_b.end_time - v_b.start_time)) / 60.0;
  if p_final_total is not null then
    v_new_base := round(p_final_total, 2);
  elsif p_hourly_rate is not null then
    v_new_base := round(p_hourly_rate * v_minutes / 60.0, 2);
  else
    v_new_base := v_b.base_price;
  end if;
  if v_new_base < 0 then
    raise exception 'Price cannot be negative';
  end if;

  if v_new_base < v_b.base_price then
    -- Reduction is shown to the customer as a discount off the requested price.
    v_base := v_b.base_price;
    v_discount := v_b.base_price - v_new_base;
  else
    v_base := v_new_base;
    v_discount := 0;
  end if;

  select coalesce(commission_rate, 10) into v_rate
    from public.platform_settings limit 1;
  v_rate := coalesce(v_rate, 10);
  v_commission := round((v_base - v_discount + v_b.addons_total) * v_rate / 100.0, 2);

  select coalesce(payment_window_hours, 24) into v_window
    from public.platform_settings limit 1;
  v_window := coalesce(v_window, 24);

  update public.bookings set
    base_price = v_base,
    discount_amount = v_discount,
    commission_amount = v_commission,
    total_price = v_base - v_discount + addons_total + v_commission,
    status = 'approved',
    payment_due_at = now() + make_interval(hours => v_window)
  where id = p_booking_id
  returning * into v_b;

  select name into v_resource_name from public.resources where id = v_b.resource_id;
  insert into public.notifications (user_id, title, message, type)
  values (
    v_b.user_id,
    'Booking approved',
    'Your booking request for ' || coalesce(v_resource_name, 'the venue') ||
      ' was approved. Pay within ' || v_window ||
      ' hours in My Bookings or the slot is released.',
    'booking_approved'
  );

  return v_b;
end;
$$;

grant execute on function public.approve_custom_booking(uuid, numeric, numeric)
  to authenticated;

-- ── 1c) Expiry sweep (cron + lazy app calls; idempotent) ─────────────────────
create or replace function public.expire_stale_bookings()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_b record;
begin
  -- Approved but unpaid past the deadline → release the slot.
  for v_b in
    update public.bookings
       set status = 'cancelled',
           cancellation_reason = 'Payment window expired'
     where status = 'approved'
       and payment_due_at is not null
       and payment_due_at < now()
    returning id, user_id, resource_id
  loop
    insert into public.notifications (user_id, title, message, type)
    select v_b.user_id,
           'Booking expired',
           'Your approved booking for ' || coalesce(r.name, 'the venue') ||
             ' was released because it was not paid in time.',
           'cancellation'
      from public.resources r where r.id = v_b.resource_id;
  end loop;

  -- Requests the venue never acted on before the start time → reject.
  for v_b in
    update public.bookings
       set status = 'rejected',
           cancellation_reason = 'Request expired (start time passed)'
     where status = 'pending_approval'
       and start_time <= now()
    returning id, user_id, resource_id
  loop
    insert into public.notifications (user_id, title, message, type)
    select v_b.user_id,
           'Request expired',
           'Your booking request for ' || coalesce(r.name, 'the venue') ||
             ' expired before the venue responded.',
           'booking_rejected'
      from public.resources r where r.id = v_b.resource_id;
  end loop;
end;
$$;

grant execute on function public.expire_stale_bookings() to authenticated;

-- Best effort: run the sweep every 10 minutes. If pg_cron is unavailable the
-- migration still succeeds — the lazy app call + payment guard keep things
-- correct, just less promptly.
do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule('expire-stale-bookings')
   where exists (select 1 from cron.job where jobname = 'expire-stale-bookings');
  perform cron.schedule(
    'expire-stale-bookings',
    '*/10 * * * *',
    'select public.expire_stale_bookings()'
  );
exception when others then
  raise notice 'pg_cron unavailable (%); relying on lazy expiry', sqlerrm;
end $$;

-- ── 1d) Paying an expired booking is refused (race-proof guard) ──────────────
create or replace function public.pay_booking_placeholder(p_booking_id uuid)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_b public.bookings%rowtype;
begin
  select * into v_b from public.bookings where id = p_booking_id for update;
  if not found or v_b.user_id <> auth.uid() then
    raise exception 'Booking not found';
  end if;
  if v_b.status <> 'approved' then
    raise exception 'Booking is not awaiting payment (status: %)', v_b.status;
  end if;
  if v_b.payment_due_at is not null and v_b.payment_due_at < now() then
    update public.bookings set
      status = 'cancelled',
      cancellation_reason = 'Payment window expired'
    where id = p_booking_id;
    raise exception 'The payment window has expired and the slot was released';
  end if;

  update public.bookings set
    status = 'confirmed',
    payment_status = 'paid'
  where id = p_booking_id
  returning * into v_b;

  insert into public.payments (booking_id, amount, currency, gateway, status)
  values (v_b.id, v_b.total_price, 'ZAR', 'placeholder', 'paid');

  return v_b;
end;
$$;

grant execute on function public.pay_booking_placeholder(uuid) to authenticated;

-- ── 2) Reschedule a confirmed slot booking ───────────────────────────────────
create or replace function public.reschedule_booking(
  p_booking_id uuid,
  p_new_start timestamptz,
  p_new_end timestamptz
)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_b public.bookings%rowtype;
  v_period public.pricing_periods%rowtype;
  v_dur public.durations%rowtype;
  v_minutes numeric;
  v_day date := (p_new_start at time zone 'utc')::date;
  v_rate numeric;
  v_commission numeric(10,2);
  v_window int;
  v_owner uuid;
  v_resource_name text;
begin
  select * into v_b from public.bookings where id = p_booking_id for update;
  if not found or v_b.user_id <> auth.uid() then
    raise exception 'Booking not found';
  end if;
  if v_b.status <> 'confirmed' or v_b.duration_id is null then
    raise exception 'Only confirmed slot bookings can be rescheduled';
  end if;

  select coalesce(cancellation_window_hours, 24) into v_window
    from public.platform_settings limit 1;
  v_window := coalesce(v_window, 24);
  if now() >= v_b.start_time - make_interval(hours => v_window) then
    raise exception
      'Rescheduling closes % hours before the booking starts', v_window;
  end if;

  if p_new_end <= p_new_start then
    raise exception 'End time must be after start time';
  end if;
  if p_new_start <= now() then
    raise exception 'The new time must be in the future';
  end if;
  v_minutes := extract(epoch from (p_new_end - p_new_start)) / 60.0;
  if v_minutes <> extract(epoch from (v_b.end_time - v_b.start_time)) / 60.0 then
    raise exception 'The new slot must have the same duration';
  end if;

  -- New date's season + the tier of the same length (prices may differ).
  select * into v_period from public.pricing_periods
   where resource_id = v_b.resource_id and is_active
     and v_day between start_date and end_date;
  if not found then
    raise exception 'No pricing has been set for this date. Please pick another date.';
  end if;
  select * into v_dur from public.durations
   where period_id = v_period.id and resource_id = v_b.resource_id
     and is_active and minutes = round(v_minutes)
   order by price limit 1;
  if not found then
    raise exception 'This duration is not offered on that date';
  end if;

  select coalesce(commission_rate, 10) into v_rate
    from public.platform_settings limit 1;
  v_rate := coalesce(v_rate, 10);
  v_commission := round((v_dur.price + v_b.addons_total) * v_rate / 100.0, 2);

  -- The exclusion constraint rejects overlaps on UPDATE too (23P01).
  update public.bookings set
    start_time = p_new_start,
    end_time = p_new_end,
    duration_id = v_dur.id,
    base_price = v_dur.price,
    discount_amount = 0,
    commission_amount = v_commission,
    total_price = v_dur.price + addons_total + v_commission
  where id = p_booking_id
  returning * into v_b;

  select t.owner_id, r.name into v_owner, v_resource_name
    from public.resources r
    join public.tenants t on t.id = r.tenant_id
   where r.id = v_b.resource_id;
  if v_owner is not null then
    insert into public.notifications (user_id, title, message, type)
    values (
      v_owner,
      'Booking rescheduled',
      'A customer moved their booking for ' ||
        coalesce(v_resource_name, 'your venue') || ' to ' ||
        to_char(v_b.start_time, 'DD Mon YYYY, HH24:MI') || ' (UTC).',
      'booking'
    );
  end if;

  return v_b;
end;
$$;

grant execute on function
  public.reschedule_booking(uuid, timestamptz, timestamptz) to authenticated;

-- ── 3) Weekly recurring series ───────────────────────────────────────────────
create or replace function public.create_recurring_bookings(
  p_resource_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_duration_id uuid,
  p_weeks int,
  p_split_payment boolean,
  p_addons jsonb default '[]'::jsonb
)
returns setof public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_res public.resources%rowtype;
  v_base_dur public.durations%rowtype;
  v_period public.pricing_periods%rowtype;
  v_dur_id uuid;
  v_group uuid := gen_random_uuid();
  v_s timestamptz;
  v_e timestamptz;
  v_day date;
  v_buffer int;
  v_problems text[] := '{}';
  v_dur_ids uuid[] := '{}';
  v_b public.bookings%rowtype;
  i int;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  if p_weeks is null or p_weeks < 2 or p_weeks > 12 then
    raise exception 'A series must repeat between 2 and 12 weeks';
  end if;

  select * into v_res from public.resources
   where id = p_resource_id and is_active;
  if not found then
    raise exception 'Resource not found or inactive';
  end if;
  v_buffer := coalesce(v_res.buffer_minutes, 0);

  select * into v_base_dur from public.durations
   where id = p_duration_id and resource_id = p_resource_id and is_active;
  if not found then
    raise exception 'Invalid duration for this resource';
  end if;

  -- Pre-flight every occurrence so the series is all-or-nothing with a
  -- readable error instead of failing midway on the constraint.
  for i in 0 .. p_weeks - 1 loop
    v_s := p_start + make_interval(days => 7 * i);
    v_e := p_end + make_interval(days => 7 * i);
    v_day := (v_s at time zone 'utc')::date;

    select * into v_period from public.pricing_periods
     where resource_id = p_resource_id and is_active
       and v_day between start_date and end_date;
    if not found then
      v_problems := v_problems ||
        (to_char(v_day, 'DD Mon YYYY') || ': no pricing for this date');
      v_dur_ids := v_dur_ids || null::uuid;
      continue;
    end if;

    -- Same-length tier in that date's season (the id differs per season).
    select id into v_dur_id from public.durations
     where period_id = v_period.id and resource_id = p_resource_id
       and is_active and minutes = v_base_dur.minutes
     order by price limit 1;
    if v_dur_id is null then
      v_problems := v_problems ||
        (to_char(v_day, 'DD Mon YYYY') || ': this duration is not offered');
    elsif exists (
      select 1 from public.bookings b
      where b.resource_id = p_resource_id
        and b.status in ('confirmed','pending','pending_approval','approved')
        and b.end_time + make_interval(mins => v_buffer) > v_s
        and b.start_time - make_interval(mins => v_buffer) < v_e
    ) or exists (
      select 1 from public.slot_blocks sb
      where sb.resource_id = p_resource_id
        and sb.end_time > v_s
        and sb.start_time < v_e
    ) then
      v_problems := v_problems ||
        (to_char(v_day, 'DD Mon YYYY') || ': time unavailable');
      v_dur_id := null;
    end if;
    v_dur_ids := v_dur_ids || v_dur_id;
  end loop;

  if array_length(v_problems, 1) > 0 then
    raise exception 'Cannot book the full series — %',
      array_to_string(v_problems, '; ');
  end if;

  -- Create through the standard server-priced path (atomic: any late
  -- conflict aborts the whole transaction).
  for i in 0 .. p_weeks - 1 loop
    v_s := p_start + make_interval(days => 7 * i);
    v_e := p_end + make_interval(days => 7 * i);
    v_b := public.create_booking_with_addons(
      p_resource_id, v_s, v_e, v_dur_ids[i + 1],
      false, p_split_payment, p_addons
    );
    update public.bookings
       set recurring_group_id = v_group
     where id = v_b.id
    returning * into v_b;
    return next v_b;
  end loop;
end;
$$;

grant execute on function
  public.create_recurring_bookings(uuid, timestamptz, timestamptz, uuid, int, boolean, jsonb)
  to authenticated;
