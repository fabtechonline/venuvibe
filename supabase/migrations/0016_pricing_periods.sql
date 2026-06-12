-- ============================================================================
-- 0016 · Seasonal pricing — pricing periods per resource date range
-- ----------------------------------------------------------------------------
-- A resource's pricing now lives inside named, NON-OVERLAPPING date ranges
-- ("seasons"): every duration tier belongs to a period, and a period may
-- override the resource's default hourly rate for custom bookings.
-- A booking whose start date is not covered by an active period is REJECTED
-- ("no price set for this date") — both slot and custom modes.
--
-- Date convention: the covering period is resolved from the booking's start
-- timestamp as a UTC date. Trading hours are 07:00–23:00 venue wall-clock
-- (SAST = UTC+2), so the UTC date equals the local date for every legal
-- booking. Same wall-clock convention as the rest of the app.
--
-- Backfill: each resource that already has tiers gets a 'Standard' period
-- (today → +12 months) owning them; durations.period_id then becomes NOT NULL.
-- SAFE TO RE-RUN (the whole batch runs in one transaction via the API).
-- ============================================================================

-- ── 1) Periods table, no-overlap enforced in the database ────────────────────
create extension if not exists btree_gist;  -- installed by 0001; defensive

create table if not exists public.pricing_periods (
  id          uuid primary key default gen_random_uuid(),
  resource_id uuid not null references public.resources(id) on delete cascade,
  name        text not null,
  start_date  date not null,
  end_date    date not null,
  hourly_rate numeric(10,2) check (hourly_rate is null or hourly_rate >= 0),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  constraint pricing_periods_dates_valid check (start_date <= end_date),
  -- Partial on is_active: a soft-deactivated period (kept because its tiers
  -- are referenced by booking history) must not block a replacement range.
  constraint pricing_periods_no_overlap exclude using gist (
    resource_id with =,
    daterange(start_date, end_date, '[]') with &&
  ) where (is_active)
);

alter table public.pricing_periods enable row level security;

drop policy if exists pricing_periods_select on public.pricing_periods;
create policy pricing_periods_select on public.pricing_periods
  for select to anon, authenticated using (true);

drop policy if exists pricing_periods_write on public.pricing_periods;
create policy pricing_periods_write on public.pricing_periods
  for all to authenticated
  using (
    public.get_user_role() = 'admin'
    or resource_id in (
      select r.id from public.resources r
      join public.tenants t on t.id = r.tenant_id
      where t.owner_id = auth.uid()
    )
  )
  with check (
    public.get_user_role() = 'admin'
    or resource_id in (
      select r.id from public.resources r
      join public.tenants t on t.id = r.tenant_id
      where t.owner_id = auth.uid()
    )
  );

-- ── 2) Every tier belongs to a period ────────────────────────────────────────
alter table public.durations
  add column if not exists period_id uuid
    references public.pricing_periods(id) on delete cascade;

-- One 'Standard' period per resource that already has tiers (active or not —
-- inactive tiers still need a home before the NOT NULL below).
insert into public.pricing_periods (resource_id, name, start_date, end_date)
select distinct d.resource_id, 'Standard', current_date,
       (current_date + interval '12 months')::date
from public.durations d
where not exists (
  select 1 from public.pricing_periods p where p.resource_id = d.resource_id
);

update public.durations d
   set period_id = p.id
  from public.pricing_periods p
 where p.resource_id = d.resource_id
   and d.period_id is null;

alter table public.durations alter column period_id set not null;

-- ── 3) Booking creation prices from the covering period ──────────────────────
-- Same signature as 0013 (PostgREST resolution depends on it). Changes:
--   · resolve the active period covering the booking's UTC start date;
--     none → reject with a customer-facing message,
--   · slot tiers must belong to that period,
--   · custom rate = period override, else the resource default.
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
  v_period public.pricing_periods%rowtype;
  v_day date := (p_start at time zone 'utc')::date;
  v_hourly numeric;
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

  select * into v_period from public.pricing_periods
   where resource_id = p_resource_id
     and is_active
     and v_day between start_date and end_date;
  if not found then
    raise exception 'No pricing has been set for this date. Please pick another date.';
  end if;

  if p_is_custom then
    if not v_res.custom_selector_enabled then
      raise exception 'Custom bookings are not enabled for this resource';
    end if;
    v_hourly := coalesce(v_period.hourly_rate, v_res.hourly_rate);
    if v_hourly is null then
      raise exception 'This resource has no hourly rate configured';
    end if;
    if v_minutes < v_res.min_booking_minutes then
      raise exception 'Booking is shorter than the minimum of % minutes',
        v_res.min_booking_minutes;
    end if;
    v_base := round(v_hourly * v_minutes / 60.0, 2);
  else
    if p_duration_id is null then
      raise exception 'A duration is required for slot bookings';
    end if;
    select * into v_dur from public.durations
     where id = p_duration_id and resource_id = p_resource_id
       and is_active and period_id = v_period.id;
    if not found then
      raise exception 'Invalid duration for this resource on this date';
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
