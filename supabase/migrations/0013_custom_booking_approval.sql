-- ============================================================================
-- 0013 · Custom bookings + tenant approval (booking-flow redesign, step 3/3)
-- ----------------------------------------------------------------------------
-- New booking lifecycle for customer-chosen time ranges:
--   pending_approval ──approve──► approved ──pay──► confirmed ──► completed
--          └──reject──► rejected            (cancel ──► cancelled at any point)
-- pending_approval + approved BLOCK the slot (constraint + get_busy_slots).
-- All prices are computed SERVER-SIDE in create_booking_with_addons.
-- SAFE TO RE-RUN (the whole batch runs in one transaction via the API).
-- ============================================================================

-- ── 1) Widen the allowed status values ───────────────────────────────────────
alter table public.bookings drop constraint if exists bookings_status_check;
alter table public.bookings add constraint bookings_status_check
  check (status in ('confirmed','cancelled','completed','pending',
                    'pending_approval','approved','rejected'));

-- ── 2) Blocking statuses in the no-overlap constraint ────────────────────────
alter table public.bookings drop constraint if exists bookings_no_overlap;
alter table public.bookings add constraint bookings_no_overlap
  exclude using gist (
    resource_id with =,
    tstzrange(start_time, end_time) with &&
  )
  where (status in ('confirmed','pending','pending_approval','approved'));

-- ── 3) get_busy_slots: include approval-pipeline holds as 'pending' ──────────
create or replace function public.get_busy_slots(
  p_resource_id uuid,
  p_from timestamptz,
  p_to   timestamptz
)
returns table (start_time timestamptz, end_time timestamptz, kind text)
language sql
stable
security definer
set search_path = public
as $$
  select b.start_time,
         b.end_time,
         case when b.status in ('pending_approval','approved')
                or b.payment_status = 'pending'
              then 'pending' else 'booked' end
  from public.bookings b
  where b.resource_id = p_resource_id
    and b.status in ('confirmed','pending','pending_approval','approved')
    and b.end_time > p_from
    and b.start_time < p_to
  union all
  select s.start_time, s.end_time, 'maintenance'
  from public.slot_blocks s
  where s.resource_id = p_resource_id
    and s.end_time > p_from
    and s.start_time < p_to;
$$;

grant execute on function public.get_busy_slots(uuid, timestamptz, timestamptz)
  to anon, authenticated;

-- ── 4) Atomic, server-priced booking creation ────────────────────────────────
-- p_addons: [{"addon_id":"<uuid>","qty":2}, …]
-- Slot bookings (p_is_custom=false): price from the duration tier;
--   status confirmed/paid (placeholder-pay world — a real gateway later flips
--   these to pending until its webhook confirms, no schema change needed).
-- Custom bookings: price = hourly_rate × minutes, status pending_approval.
--   Window/break validation stays client-side: timestamps here are UTC while
--   trading hours are venue wall-clock, and every custom request is human-
--   reviewed by the tenant anyway. The overlap constraint is the hard gate.
create or replace function public.create_booking_with_addons(
  p_resource_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_duration_id uuid,
  p_is_custom boolean,
  p_split_payment boolean,
  p_addons jsonb default '[]'::jsonb
)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_res public.resources%rowtype;
  v_dur public.durations%rowtype;
  v_minutes numeric;
  v_base numeric(10,2);
  v_addons_total numeric(10,2) := 0;
  v_rate numeric;
  v_commission numeric(10,2);
  v_booking public.bookings%rowtype;
  v_item jsonb;
  v_addon public.resource_addons%rowtype;
  v_qty int;
  v_owner uuid;
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_res from public.resources
   where id = p_resource_id and is_active;
  if not found then
    raise exception 'Resource not found or inactive';
  end if;

  if p_end <= p_start then
    raise exception 'End time must be after start time';
  end if;
  v_minutes := extract(epoch from (p_end - p_start)) / 60.0;

  if p_is_custom then
    if not v_res.custom_selector_enabled then
      raise exception 'Custom bookings are not enabled for this resource';
    end if;
    if v_res.hourly_rate is null then
      raise exception 'This resource has no hourly rate configured';
    end if;
    if v_minutes < v_res.min_booking_minutes then
      raise exception 'Booking is shorter than the minimum of % minutes',
        v_res.min_booking_minutes;
    end if;
    v_base := round(v_res.hourly_rate * v_minutes / 60.0, 2);
  else
    if p_duration_id is null then
      raise exception 'A duration is required for slot bookings';
    end if;
    select * into v_dur from public.durations
     where id = p_duration_id and resource_id = p_resource_id and is_active;
    if not found then
      raise exception 'Invalid duration for this resource';
    end if;
    v_base := v_dur.price;
  end if;

  -- Validate add-ons and total them up (snapshots inserted after the booking).
  for v_item in select * from jsonb_array_elements(coalesce(p_addons, '[]'::jsonb))
  loop
    select * into v_addon from public.resource_addons
     where id = (v_item->>'addon_id')::uuid
       and resource_id = p_resource_id
       and is_active;
    if not found then
      raise exception 'Invalid add-on for this resource';
    end if;
    v_qty := coalesce((v_item->>'qty')::int, 1);
    if v_qty < 1 or v_qty > v_addon.max_qty then
      raise exception 'Quantity for "%" must be between 1 and %',
        v_addon.name, v_addon.max_qty;
    end if;
    v_addons_total := v_addons_total + round(v_addon.price * v_qty, 2);
  end loop;

  select coalesce(commission_rate, 10) into v_rate
    from public.platform_settings limit 1;
  v_rate := coalesce(v_rate, 10);
  v_commission := round((v_base + v_addons_total) * v_rate / 100.0, 2);

  insert into public.bookings (
    user_id, resource_id, duration_id, start_time, end_time,
    base_price, addons_total, discount_amount,
    total_price, commission_amount,
    status, payment_status, split_payment
  ) values (
    v_user, p_resource_id, p_duration_id, p_start, p_end,
    v_base, v_addons_total, 0,
    v_base + v_addons_total + v_commission, v_commission,
    case when p_is_custom then 'pending_approval' else 'confirmed' end,
    case when p_is_custom then 'pending' else 'paid' end,
    coalesce(p_split_payment, false)
  )
  returning * into v_booking;

  for v_item in select * from jsonb_array_elements(coalesce(p_addons, '[]'::jsonb))
  loop
    select * into v_addon from public.resource_addons
     where id = (v_item->>'addon_id')::uuid;
    insert into public.booking_addons (booking_id, addon_id, name, unit_price, qty)
    values (v_booking.id, v_addon.id, v_addon.name, v_addon.price,
            coalesce((v_item->>'qty')::int, 1));
  end loop;

  if p_is_custom then
    select t.owner_id into v_owner
      from public.tenants t
      join public.resources r on r.tenant_id = t.id
     where r.id = p_resource_id;
    if v_owner is not null then
      insert into public.notifications (user_id, title, message, type)
      values (
        v_owner,
        'New booking request',
        'A customer requested a custom booking for ' || v_res.name ||
          '. Review it in Approvals.',
        'booking_request'
      );
    end if;
  end if;

  return v_booking;
end;
$$;

grant execute on function
  public.create_booking_with_addons(uuid, timestamptz, timestamptz, uuid, boolean, boolean, jsonb)
  to authenticated;

-- ── 5) Tenant approval (with optional repricing → customer-visible discount) ─
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

  update public.bookings set
    base_price = v_base,
    discount_amount = v_discount,
    commission_amount = v_commission,
    total_price = v_base - v_discount + addons_total + v_commission,
    status = 'approved'
  where id = p_booking_id
  returning * into v_b;

  select name into v_resource_name from public.resources where id = v_b.resource_id;
  insert into public.notifications (user_id, title, message, type)
  values (
    v_b.user_id,
    'Booking approved',
    'Your booking request for ' || coalesce(v_resource_name, 'the venue') ||
      ' was approved. Open My Bookings to pay and confirm.',
    'booking_approved'
  );

  return v_b;
end;
$$;

grant execute on function public.approve_custom_booking(uuid, numeric, numeric)
  to authenticated;

-- ── 6) Tenant rejection (frees the slot immediately) ─────────────────────────
create or replace function public.reject_custom_booking(
  p_booking_id uuid,
  p_reason text default null
)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_b public.bookings%rowtype;
  v_resource_name text;
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
    raise exception 'Only the venue owner can reject this booking';
  end if;

  if v_b.status <> 'pending_approval' then
    raise exception 'Booking is not awaiting approval (status: %)', v_b.status;
  end if;

  update public.bookings set
    status = 'rejected',
    cancellation_reason = coalesce(nullif(trim(p_reason), ''), 'Declined by venue')
  where id = p_booking_id
  returning * into v_b;

  select name into v_resource_name from public.resources where id = v_b.resource_id;
  insert into public.notifications (user_id, title, message, type)
  values (
    v_b.user_id,
    'Booking declined',
    'Your booking request for ' || coalesce(v_resource_name, 'the venue') ||
      ' was declined: ' || v_b.cancellation_reason,
    'booking_rejected'
  );

  return v_b;
end;
$$;

grant execute on function public.reject_custom_booking(uuid, text) to authenticated;

-- ── 7) Placeholder payment (real gateway replaces only the app call site) ────
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
