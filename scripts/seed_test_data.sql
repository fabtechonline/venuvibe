-- ============================================================================
-- Seed data for extensive testing (2026-06-12) — run via scripts/sbsql.py.
-- Fills every resource with seasons, season-scoped tiers, custom-booking
-- rates, add-ons, weekly hours (incl. breaks and a closed day), photos and a
-- spread of bookings for Sarah (every status, incl. a weekly series).
-- Leaves the user's hand-made Tennis Court A seasons untouched (adds tiers
-- inside them) and deliberately leaves pricing gaps to exercise the
-- "no price" flag and the tenant gap warning:
--   · Meditation Room: 1–14 Sep 2026 uncovered (internal gap)
--   · Tennis Court A: 11 Dec 2026 onwards uncovered
--   · everything else: coverage ends 31 May 2027
-- Re-running duplicates bookings; everything else is guarded.
-- ============================================================================

-- ── Resources: custom-booking rates, buffers, photos ─────────────────────────
update public.resources set custom_selector_enabled = true, hourly_rate = 45
 where id = 'cccccccc-1111-4000-8000-000000000003';   -- Padel
update public.resources set custom_selector_enabled = true, hourly_rate = 380
 where id = 'cccccccc-1111-4000-8000-000000000001';   -- Tennis
update public.resources set custom_selector_enabled = true, hourly_rate = 150
 where id = 'cccccccc-2222-4000-8000-000000000001';   -- Yoga
-- Meditation Room stays custom-disabled on purpose (tests that path).

update public.resources set images = array[
  'https://picsum.photos/seed/vv-basketball-1/1200/800',
  'https://picsum.photos/seed/vv-basketball-2/1200/800',
  'https://picsum.photos/seed/vv-basketball-3/1200/800']
 where id = 'cccccccc-1111-4000-8000-000000000002'
   and coalesce(array_length(images, 1), 0) = 0;
update public.resources set images = array[
  'https://picsum.photos/seed/vv-padel-1/1200/800',
  'https://picsum.photos/seed/vv-padel-2/1200/800',
  'https://picsum.photos/seed/vv-padel-3/1200/800']
 where id = 'cccccccc-1111-4000-8000-000000000003'
   and coalesce(array_length(images, 1), 0) = 0;
update public.resources set images = array[
  'https://picsum.photos/seed/vv-tennis-1/1200/800',
  'https://picsum.photos/seed/vv-tennis-2/1200/800',
  'https://picsum.photos/seed/vv-tennis-3/1200/800',
  'https://picsum.photos/seed/vv-tennis-4/1200/800']
 where id = 'cccccccc-1111-4000-8000-000000000001'
   and coalesce(array_length(images, 1), 0) = 0;
update public.resources set images = array[
  'https://picsum.photos/seed/vv-hall-1/1200/800',
  'https://picsum.photos/seed/vv-hall-2/1200/800',
  'https://picsum.photos/seed/vv-hall-3/1200/800',
  'https://picsum.photos/seed/vv-hall-4/1200/800']
 where id = '16d42294-b555-4ffd-b1b7-0d377178d4b3'
   and coalesce(array_length(images, 1), 0) = 0;
update public.resources set images = array[
  'https://picsum.photos/seed/vv-meditation-1/1200/800',
  'https://picsum.photos/seed/vv-meditation-2/1200/800']
 where id = 'cccccccc-2222-4000-8000-000000000002'
   and coalesce(array_length(images, 1), 0) = 0;
update public.resources set images = array[
  'https://picsum.photos/seed/vv-yoga-1/1200/800',
  'https://picsum.photos/seed/vv-yoga-2/1200/800',
  'https://picsum.photos/seed/vv-yoga-3/1200/800']
 where id = 'cccccccc-2222-4000-8000-000000000001'
   and coalesce(array_length(images, 1), 0) = 0;

-- ── Fix Padel's odd legacy tier prices + add a 2-hour tier ───────────────────
update public.durations set price = 300
 where period_id = 'e993d0ec-8e51-418e-b145-cc2743158ac1' and label = '1 Hour';
update public.durations set price = 420
 where period_id = 'e993d0ec-8e51-418e-b145-cc2743158ac1'
   and label = '1.5 Hours';
insert into public.durations (resource_id, period_id, label, minutes, price)
select 'cccccccc-1111-4000-8000-000000000003',
       'e993d0ec-8e51-418e-b145-cc2743158ac1', '2 Hours', 120, 520
 where not exists (select 1 from public.durations
   where period_id = 'e993d0ec-8e51-418e-b145-cc2743158ac1'
     and label = '2 Hours');

-- Basketball gets a 30-minute tier in Standard (min booking is 30).
insert into public.durations (resource_id, period_id, label, minutes, price)
select 'cccccccc-1111-4000-8000-000000000002',
       'c11967cc-7917-41e0-b92b-2a01306281db', '30 Minutes', 30, 25
 where not exists (select 1 from public.durations
   where period_id = 'c11967cc-7917-41e0-b92b-2a01306281db'
     and label = '30 Minutes');

-- ── Seasons: shrink each Standard, add seasonal periods, copy tiers ──────────
-- Helper pattern: insert season RETURNING id, then copy the Standard tiers
-- with a price multiplier. Guarded by season-name existence checks.

-- Basketball (Standard c11967cc…)
update public.pricing_periods set end_date = '2026-08-31'
 where id = 'c11967cc-7917-41e0-b92b-2a01306281db';
do $seed$
declare
  v_std uuid := 'c11967cc-7917-41e0-b92b-2a01306281db';
  v_res uuid := 'cccccccc-1111-4000-8000-000000000002';
  v_id uuid;
begin
  if not exists (select 1 from public.pricing_periods
                  where resource_id = v_res and name = 'Spring 2026') then
    insert into public.pricing_periods (resource_id, name, start_date, end_date)
    values (v_res, 'Spring 2026', '2026-09-01', '2026-11-30')
    returning id into v_id;
    insert into public.durations (resource_id, period_id, label, minutes, price)
    select resource_id, v_id, label, minutes, round(price * 1.10, 2)
      from public.durations where period_id = v_std and is_active;

    insert into public.pricing_periods
      (resource_id, name, start_date, end_date, hourly_rate)
    values (v_res, 'Summer Peak', '2026-12-01', '2027-02-28', 55)
    returning id into v_id;
    insert into public.durations (resource_id, period_id, label, minutes, price)
    select resource_id, v_id, label, minutes, round(price * 1.25, 2)
      from public.durations where period_id = v_std and is_active;

    insert into public.pricing_periods (resource_id, name, start_date, end_date)
    values (v_res, 'Autumn 2027', '2027-03-01', '2027-05-31')
    returning id into v_id;
    insert into public.durations (resource_id, period_id, label, minutes, price)
    select resource_id, v_id, label, minutes, price
      from public.durations where period_id = v_std and is_active;
  end if;
end $seed$;

-- Padel (Standard e993d0ec…)
update public.pricing_periods set end_date = '2026-09-30'
 where id = 'e993d0ec-8e51-418e-b145-cc2743158ac1';
do $seed$
declare
  v_std uuid := 'e993d0ec-8e51-418e-b145-cc2743158ac1';
  v_res uuid := 'cccccccc-1111-4000-8000-000000000003';
  v_id uuid;
begin
  if not exists (select 1 from public.pricing_periods
                  where resource_id = v_res and name = 'Summer Series') then
    insert into public.pricing_periods
      (resource_id, name, start_date, end_date, hourly_rate)
    values (v_res, 'Summer Series', '2026-10-01', '2027-01-31', 60)
    returning id into v_id;
    insert into public.durations (resource_id, period_id, label, minutes, price)
    select resource_id, v_id, label, minutes, round(price * 1.20, 2)
      from public.durations where period_id = v_std and is_active;

    insert into public.pricing_periods (resource_id, name, start_date, end_date)
    values (v_res, 'Late Season', '2027-02-01', '2027-05-31')
    returning id into v_id;
    insert into public.durations (resource_id, period_id, label, minutes, price)
    select resource_id, v_id, label, minutes, price
      from public.durations where period_id = v_std and is_active;
  end if;
end $seed$;

-- Sunlark Hall (Standard 2be1b88c…)
update public.pricing_periods set end_date = '2026-10-31'
 where id = '2be1b88c-bec6-4659-900c-a8c1d98e5e53';
do $seed$
declare
  v_std uuid := '2be1b88c-bec6-4659-900c-a8c1d98e5e53';
  v_res uuid := '16d42294-b555-4ffd-b1b7-0d377178d4b3';
  v_id uuid;
begin
  if not exists (select 1 from public.pricing_periods
                  where resource_id = v_res and name = 'Festive Events') then
    insert into public.pricing_periods
      (resource_id, name, start_date, end_date, hourly_rate)
    values (v_res, 'Festive Events', '2026-11-01', '2027-01-15', 650)
    returning id into v_id;
    insert into public.durations (resource_id, period_id, label, minutes, price)
    select resource_id, v_id, label, minutes, round(price * 1.30, 2)
      from public.durations where period_id = v_std and is_active;

    insert into public.pricing_periods (resource_id, name, start_date, end_date)
    values (v_res, 'Standard 2027', '2027-01-16', '2027-05-31')
    returning id into v_id;
    insert into public.durations (resource_id, period_id, label, minutes, price)
    select resource_id, v_id, label, minutes, price
      from public.durations where period_id = v_std and is_active;
  end if;
end $seed$;

-- Meditation Room (Standard 415fbceb…) — INTENTIONAL GAP 1–14 Sep 2026
update public.pricing_periods set end_date = '2026-08-31'
 where id = '415fbceb-0d8f-41a5-aacb-48671c5f3970';
do $seed$
declare
  v_std uuid := '415fbceb-0d8f-41a5-aacb-48671c5f3970';
  v_res uuid := 'cccccccc-2222-4000-8000-000000000002';
  v_id uuid;
begin
  if not exists (select 1 from public.pricing_periods
                  where resource_id = v_res and name = 'Spring Calm') then
    insert into public.pricing_periods (resource_id, name, start_date, end_date)
    values (v_res, 'Spring Calm', '2026-09-15', '2026-11-30')
    returning id into v_id;
    insert into public.durations (resource_id, period_id, label, minutes, price)
    select resource_id, v_id, label, minutes, round(price * 1.10, 2)
      from public.durations where period_id = v_std and is_active;

    insert into public.pricing_periods (resource_id, name, start_date, end_date)
    values (v_res, 'Holiday Season', '2026-12-01', '2027-01-31')
    returning id into v_id;
    insert into public.durations (resource_id, period_id, label, minutes, price)
    select resource_id, v_id, label, minutes, round(price * 1.20, 2)
      from public.durations where period_id = v_std and is_active;

    insert into public.pricing_periods (resource_id, name, start_date, end_date)
    values (v_res, 'Autumn 2027', '2027-02-01', '2027-05-31')
    returning id into v_id;
    insert into public.durations (resource_id, period_id, label, minutes, price)
    select resource_id, v_id, label, minutes, price
      from public.durations where period_id = v_std and is_active;
  end if;
end $seed$;

-- Yoga Studio (Standard b4df7397…)
update public.pricing_periods set end_date = '2026-11-30'
 where id = 'b4df7397-1e23-4b35-b6b1-c5e14471fbf8';
do $seed$
declare
  v_std uuid := 'b4df7397-1e23-4b35-b6b1-c5e14471fbf8';
  v_res uuid := 'cccccccc-2222-4000-8000-000000000001';
  v_id uuid;
begin
  if not exists (select 1 from public.pricing_periods
                  where resource_id = v_res and name = 'Summer Wellness') then
    insert into public.pricing_periods
      (resource_id, name, start_date, end_date, hourly_rate)
    values (v_res, 'Summer Wellness', '2026-12-01', '2027-02-28', 180)
    returning id into v_id;
    insert into public.durations (resource_id, period_id, label, minutes, price)
    select resource_id, v_id, label, minutes, round(price * 1.15, 2)
      from public.durations where period_id = v_std and is_active;

    insert into public.pricing_periods (resource_id, name, start_date, end_date)
    values (v_res, 'Autumn 2027', '2027-03-01', '2027-05-31')
    returning id into v_id;
    insert into public.durations (resource_id, period_id, label, minutes, price)
    select resource_id, v_id, label, minutes, price
      from public.durations where period_id = v_std and is_active;
  end if;
end $seed$;

-- Tennis Court A — tiers inside the user's hand-made seasons (kept as-is).
insert into public.durations (resource_id, period_id, label, minutes, price)
select 'cccccccc-1111-4000-8000-000000000001', x.period_id, x.label, x.minutes, x.price
from (values
  ('2582ed85-c401-4d3a-9a57-58daa0a8409d'::uuid, '1 Hour',    60, 450.00),
  ('2582ed85-c401-4d3a-9a57-58daa0a8409d'::uuid, '1.5 Hours', 90, 650.00),
  ('2582ed85-c401-4d3a-9a57-58daa0a8409d'::uuid, '2 Hours',  120, 850.00),
  ('d8a22224-dfa1-4dff-8696-fc644e483227'::uuid, '1 Hour',    60, 400.00),
  ('d8a22224-dfa1-4dff-8696-fc644e483227'::uuid, '1.5 Hours', 90, 580.00),
  ('d8a22224-dfa1-4dff-8696-fc644e483227'::uuid, '2 Hours',  120, 760.00),
  ('bc97fd49-6307-4fda-b451-b4a1b33b4b16'::uuid, '1 Hour',    60, 350.00),
  ('bc97fd49-6307-4fda-b451-b4a1b33b4b16'::uuid, '1.5 Hours', 90, 500.00),
  ('bc97fd49-6307-4fda-b451-b4a1b33b4b16'::uuid, '2 Hours',  120, 660.00),
  ('fb4c31ce-c819-47bd-966f-baeb1a7bca6a'::uuid, '1 Hour',    60, 400.00),
  ('fb4c31ce-c819-47bd-966f-baeb1a7bca6a'::uuid, '1.5 Hours', 90, 580.00),
  ('fb4c31ce-c819-47bd-966f-baeb1a7bca6a'::uuid, '2 Hours',  120, 760.00)
) as x(period_id, label, minutes, price)
where not exists (select 1 from public.durations d
  where d.period_id = x.period_id and d.label = x.label and d.is_active);

-- ── Add-ons (insert only when the name is new for the resource) ──────────────
insert into public.resource_addons (resource_id, name, price, max_qty)
select x.rid::uuid, x.name, x.price, x.qty
from (values
  ('cccccccc-1111-4000-8000-000000000002', 'Ball Rental',          20.00,  5),
  ('cccccccc-1111-4000-8000-000000000002', 'Bibs Set (10)',        50.00,  2),
  ('cccccccc-1111-4000-8000-000000000002', 'Scoreboard Operator', 150.00,  1),
  ('cccccccc-1111-4000-8000-000000000003', 'Ball Tin',             45.00,  3),
  ('cccccccc-1111-4000-8000-000000000001', 'Ball Machine',        120.00,  1),
  ('cccccccc-1111-4000-8000-000000000001', 'New Ball Tin',         60.00,  3),
  ('16d42294-b555-4ffd-b1b7-0d377178d4b3', 'Projector & Screen',  200.00,  1),
  ('16d42294-b555-4ffd-b1b7-0d377178d4b3', 'Cleaning Service',    400.00,  1),
  ('cccccccc-2222-4000-8000-000000000002', 'Aromatherapy Set',     35.00,  2),
  ('cccccccc-2222-4000-8000-000000000002', 'Guided Audio Session', 50.00,  1),
  ('cccccccc-2222-4000-8000-000000000002', 'Meditation Cushion',   15.00,  6),
  ('cccccccc-2222-4000-8000-000000000001', 'Yoga Mat Hire',        25.00, 12),
  ('cccccccc-2222-4000-8000-000000000001', 'Towel Service',        20.00, 12),
  ('cccccccc-2222-4000-8000-000000000001', 'Blocks & Straps Set',  30.00, 12)
) as x(rid, name, price, qty)
where not exists (select 1 from public.resource_addons a
  where a.resource_id = x.rid::uuid and a.name = x.name);

-- ── Weekly hours for the resources that have none ────────────────────────────
-- Basketball: long weekdays, shorter weekends.
insert into public.resource_hours
  (resource_id, weekday, open_time, close_time, is_closed)
select 'cccccccc-1111-4000-8000-000000000002', w,
       case when w <= 5 then '06:00'::time when w = 6 then '07:00' else '08:00' end,
       case when w <= 5 then '22:00'::time when w = 6 then '20:00' else '18:00' end,
       false
  from generate_series(1, 7) w
on conflict (resource_id, weekday) do nothing;

-- Padel: 07:00–21:00 daily, weekday maintenance break 12:00–13:00.
insert into public.resource_hours
  (resource_id, weekday, open_time, close_time, break_start, break_end, is_closed)
select 'cccccccc-1111-4000-8000-000000000003', w, '07:00', '21:00',
       case when w <= 5 then '12:00'::time end,
       case when w <= 5 then '13:00'::time end,
       false
  from generate_series(1, 7) w
on conflict (resource_id, weekday) do nothing;

-- Meditation: weekday lunch break, short Saturday, CLOSED Sunday.
insert into public.resource_hours
  (resource_id, weekday, open_time, close_time, break_start, break_end, is_closed)
select 'cccccccc-2222-4000-8000-000000000002', w,
       case when w <= 5 then '08:00'::time else '08:00' end,
       case when w <= 5 then '20:00'::time else '14:00' end,
       case when w <= 5 then '13:00'::time end,
       case when w <= 5 then '14:00'::time end,
       w = 7
  from generate_series(1, 7) w
on conflict (resource_id, weekday) do nothing;

-- Yoga: early weekdays/Saturday, Sunday morning only.
insert into public.resource_hours
  (resource_id, weekday, open_time, close_time, is_closed)
select 'cccccccc-2222-4000-8000-000000000001', w,
       case when w <= 6 then '06:00'::time else '08:00' end,
       case when w <= 6 then '21:00'::time else '12:00' end,
       false
  from generate_series(1, 7) w
on conflict (resource_id, weekday) do nothing;

-- ── Bookings for Sarah (every state; times in UTC = SAST − 2h) ───────────────
-- 1) Past, completed (Basketball, Standard 1 Hour R40 + 5% fee).
insert into public.bookings
  (user_id, resource_id, duration_id, start_time, end_time,
   base_price, addons_total, discount_amount, total_price, commission_amount,
   status, payment_status)
select 'aaaaaaaa-2222-4000-8000-000000000002', d.resource_id, d.id,
       '2026-06-05 08:00:00+00', '2026-06-05 09:00:00+00',
       d.price, 0, 0, round(d.price * 1.05, 2), round(d.price * 0.05, 2),
       'completed', 'paid'
  from public.durations d
 where d.period_id = 'c11967cc-7917-41e0-b92b-2a01306281db'
   and d.minutes = 60 and d.is_active limit 1;

-- 2) Past, cancelled (Padel 1 Hour).
insert into public.bookings
  (user_id, resource_id, duration_id, start_time, end_time,
   base_price, addons_total, discount_amount, total_price, commission_amount,
   status, payment_status, cancellation_reason)
select 'aaaaaaaa-2222-4000-8000-000000000002', d.resource_id, d.id,
       '2026-06-08 09:00:00+00', '2026-06-08 10:00:00+00',
       d.price, 0, 0, round(d.price * 1.05, 2), round(d.price * 0.05, 2),
       'cancelled', 'pending', 'User cancelled'
  from public.durations d
 where d.period_id = 'e993d0ec-8e51-418e-b145-cc2743158ac1'
   and d.minutes = 60 and d.is_active limit 1;

-- 3) Upcoming, confirmed (Tennis Off Peak 1 Hour R350).
insert into public.bookings
  (user_id, resource_id, duration_id, start_time, end_time,
   base_price, addons_total, discount_amount, total_price, commission_amount,
   status, payment_status)
select 'aaaaaaaa-2222-4000-8000-000000000002', d.resource_id, d.id,
       '2026-06-20 07:00:00+00', '2026-06-20 08:00:00+00',
       d.price, 0, 0, round(d.price * 1.05, 2), round(d.price * 0.05, 2),
       'confirmed', 'paid'
  from public.durations d
 where d.period_id = 'bc97fd49-6307-4fda-b451-b4a1b33b4b16'
   and d.minutes = 60 and d.is_active limit 1;

-- 4) Weekly series ×3 (Yoga, largest Standard tier), shared group id.
with t as (
  select d.id, d.resource_id, d.minutes, d.price
    from public.durations d
   where d.period_id = 'b4df7397-1e23-4b35-b6b1-c5e14471fbf8'
     and d.is_active
   order by d.minutes desc limit 1
), g as (select gen_random_uuid() as gid)
insert into public.bookings
  (user_id, resource_id, duration_id, start_time, end_time,
   base_price, addons_total, discount_amount, total_price, commission_amount,
   status, payment_status, recurring_group_id)
select 'aaaaaaaa-2222-4000-8000-000000000002', t.resource_id, t.id,
       v.ts, v.ts + make_interval(mins => t.minutes),
       t.price, 0, 0, round(t.price * 1.05, 2), round(t.price * 0.05, 2),
       'confirmed', 'paid', g.gid
  from t, g, (values
    ('2026-06-17 15:00:00+00'::timestamptz),
    ('2026-06-24 15:00:00+00'::timestamptz),
    ('2026-07-01 15:00:00+00'::timestamptz)
  ) v(ts);

-- 5) Custom request awaiting tenant approval (Sunlark Hall, 4h × R500).
insert into public.bookings
  (user_id, resource_id, duration_id, start_time, end_time,
   base_price, addons_total, discount_amount, total_price, commission_amount,
   status, payment_status)
values
  ('aaaaaaaa-2222-4000-8000-000000000002',
   '16d42294-b555-4ffd-b1b7-0d377178d4b3', null,
   '2026-07-11 12:00:00+00', '2026-07-11 16:00:00+00',
   2000, 0, 0, 2100, 100, 'pending_approval', 'pending');

-- 6) Approved custom awaiting payment, 24h deadline (Basketball 2h × R40).
insert into public.bookings
  (user_id, resource_id, duration_id, start_time, end_time,
   base_price, addons_total, discount_amount, total_price, commission_amount,
   status, payment_status, payment_due_at)
values
  ('aaaaaaaa-2222-4000-8000-000000000002',
   'cccccccc-1111-4000-8000-000000000002', null,
   '2026-06-28 16:00:00+00', '2026-06-28 18:00:00+00',
   80, 0, 0, 84, 4, 'approved', 'pending', now() + interval '24 hours');

select 'seeded' as result;
