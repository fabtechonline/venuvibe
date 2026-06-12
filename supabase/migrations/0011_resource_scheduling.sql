-- ============================================================================
-- 0011 · Resource scheduling (booking-flow redesign, step 1/3)
-- ----------------------------------------------------------------------------
-- Per-resource: minimum booking duration, buffer/turnaround time between
-- bookings, custom-time-selector toggle + hourly rate, per-weekday trading
-- hours with an optional break window, and a 10-photo cap.
--
-- Resources WITHOUT resource_hours rows keep behaving exactly as today
-- (legacy single open_time/close_time window). SAFE TO RE-RUN.
-- ============================================================================

-- ── New scheduling/pricing columns on resources ──────────────────────────────
alter table public.resources
  add column if not exists min_booking_minutes int not null default 30,
  add column if not exists buffer_minutes int not null default 0,
  add column if not exists custom_selector_enabled boolean not null default false,
  add column if not exists hourly_rate numeric(10,2);

alter table public.resources drop constraint if exists resources_min_booking_valid;
alter table public.resources add constraint resources_min_booking_valid
  check (min_booking_minutes between 5 and 1440);

alter table public.resources drop constraint if exists resources_buffer_valid;
alter table public.resources add constraint resources_buffer_valid
  check (buffer_minutes between 0 and 240);

alter table public.resources drop constraint if exists resources_hourly_rate_valid;
alter table public.resources add constraint resources_hourly_rate_valid
  check (hourly_rate is null or hourly_rate >= 0);

-- ── Photo cap: max 10 images per resource ────────────────────────────────────
-- (verified before adding: no resource currently exceeds 10)
alter table public.resources drop constraint if exists resources_images_max10;
alter table public.resources add constraint resources_images_max10
  check (coalesce(array_length(images, 1), 0) <= 10);

-- ── Per-weekday trading hours ────────────────────────────────────────────────
-- weekday is ISO: 1 = Monday … 7 = Sunday (matches Dart DateTime.weekday).
-- A day either is_closed, or has open/close and optionally one break window
-- fully inside it (break splits the day into two bookable windows).
create table if not exists public.resource_hours (
  id          uuid primary key default gen_random_uuid(),
  resource_id uuid not null references public.resources(id) on delete cascade,
  weekday     smallint not null check (weekday between 1 and 7),
  is_closed   boolean not null default false,
  open_time   time not null default '07:00',
  close_time  time not null default '23:00',
  break_start time,
  break_end   time,
  created_at  timestamptz not null default now(),
  unique (resource_id, weekday),
  check (is_closed or close_time > open_time),
  check ((break_start is null) = (break_end is null)),
  check (
    break_start is null
    or (break_start >= open_time and break_end <= close_time and break_end > break_start)
  )
);

alter table public.resource_hours enable row level security;

drop policy if exists resource_hours_select on public.resource_hours;
create policy resource_hours_select on public.resource_hours
  for select to anon, authenticated using (true);

drop policy if exists resource_hours_write on public.resource_hours;
create policy resource_hours_write on public.resource_hours
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
