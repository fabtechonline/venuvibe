-- ============================================================================
-- 0002 · Row-Level Security (Phase 1 · RLS — the real security boundary)
-- ----------------------------------------------------------------------------
-- Without these, the anon key + any logged-in user can read/write every table
-- directly; the app's role-based UI is only cosmetic. These policies are
-- derived from the Dart models + repository queries.
--
-- READ BEFORE RUNNING:
--  • SAFE TO RE-RUN (drops each policy before recreating).
--  • TEST AFTER APPLYING with each role (user / tenant / admin). If something
--    breaks, you can temporarily disable a table:  alter table X disable row level security;
--  • Two pragmatic tradeoffs are flagged "HARDENING" below (profiles read,
--    availability) — fine for launch, tighten later.
-- ============================================================================

-- Helper: caller's role, read with definer rights so policies on `profiles`
-- don't recurse. Returns null when not logged in.
create or replace function public.my_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;
grant execute on function public.my_role() to anon, authenticated;

-- ── profiles ────────────────────────────────────────────────────────────────
alter table public.profiles enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (true);
-- HARDENING: `using (true)` lets any signed-in user read every profile so the
-- booking joins (bookings -> profiles.full_name, tenant viewing customers) work.
-- This exposes email/phone. For production, expose only id+full_name via a view
-- (e.g. public_profiles) and join to that instead, then change this to:
--   using (auth.uid() = id or public.my_role() = 'admin')

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles
  for insert to authenticated
  with check (auth.uid() = id);

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (auth.uid() = id or public.my_role() = 'admin')
  with check (auth.uid() = id or public.my_role() = 'admin');

-- ── tenants ─────────────────────────────────────────────────────────────────
alter table public.tenants enable row level security;

drop policy if exists tenants_select on public.tenants;
create policy tenants_select on public.tenants
  for select to anon, authenticated
  using (true);  -- tenant names/addresses are shown on public resource cards

drop policy if exists tenants_insert on public.tenants;
create policy tenants_insert on public.tenants
  for insert to authenticated
  with check (auth.uid() = owner_id);  -- onboarding (M4) creates own tenant

drop policy if exists tenants_update on public.tenants;
create policy tenants_update on public.tenants
  for update to authenticated
  using (auth.uid() = owner_id or public.my_role() = 'admin')
  with check (auth.uid() = owner_id or public.my_role() = 'admin');
-- (admin approve/suspend goes through this update policy)

-- ── categories ──────────────────────────────────────────────────────────────
alter table public.categories enable row level security;

drop policy if exists categories_select on public.categories;
create policy categories_select on public.categories
  for select to anon, authenticated using (true);

drop policy if exists categories_admin_write on public.categories;
create policy categories_admin_write on public.categories
  for all to authenticated
  using (public.my_role() = 'admin')
  with check (public.my_role() = 'admin');

-- ── resources ───────────────────────────────────────────────────────────────
alter table public.resources enable row level security;

drop policy if exists resources_select on public.resources;
create policy resources_select on public.resources
  for select to anon, authenticated using (true);

drop policy if exists resources_write on public.resources;
create policy resources_write on public.resources
  for all to authenticated
  using (
    public.my_role() = 'admin'
    or tenant_id in (select id from public.tenants where owner_id = auth.uid())
  )
  with check (
    public.my_role() = 'admin'
    or tenant_id in (select id from public.tenants where owner_id = auth.uid())
  );

-- ── durations ───────────────────────────────────────────────────────────────
alter table public.durations enable row level security;

drop policy if exists durations_select on public.durations;
create policy durations_select on public.durations
  for select to anon, authenticated using (true);

drop policy if exists durations_write on public.durations;
create policy durations_write on public.durations
  for all to authenticated
  using (
    public.my_role() = 'admin'
    or resource_id in (
      select r.id from public.resources r
      join public.tenants t on t.id = r.tenant_id
      where t.owner_id = auth.uid()
    )
  )
  with check (
    public.my_role() = 'admin'
    or resource_id in (
      select r.id from public.resources r
      join public.tenants t on t.id = r.tenant_id
      where t.owner_id = auth.uid()
    )
  );

-- ── slot_blocks ─────────────────────────────────────────────────────────────
alter table public.slot_blocks enable row level security;

drop policy if exists slot_blocks_select on public.slot_blocks;
create policy slot_blocks_select on public.slot_blocks
  for select to anon, authenticated using (true);

drop policy if exists slot_blocks_write on public.slot_blocks;
create policy slot_blocks_write on public.slot_blocks
  for all to authenticated
  using (
    public.my_role() = 'admin'
    or resource_id in (
      select r.id from public.resources r
      join public.tenants t on t.id = r.tenant_id
      where t.owner_id = auth.uid()
    )
  )
  with check (
    public.my_role() = 'admin'
    or resource_id in (
      select r.id from public.resources r
      join public.tenants t on t.id = r.tenant_id
      where t.owner_id = auth.uid()
    )
  );

-- ── bookings ────────────────────────────────────────────────────────────────
alter table public.bookings enable row level security;

drop policy if exists bookings_select on public.bookings;
create policy bookings_select on public.bookings
  for select to authenticated
  using (
    auth.uid() = user_id
    or public.my_role() = 'admin'
    or resource_id in (
      select r.id from public.resources r
      join public.tenants t on t.id = r.tenant_id
      where t.owner_id = auth.uid()
    )
  );
-- HARDENING/AVAILABILITY: this (correctly) hides other users' bookings, which
-- means availability_calendar.getResourceBookings() will no longer see slots
-- booked by others. SWITCH that screen to the get_busy_slots() RPC from
-- migration 0001 (client follow-up). The 0001 exclusion constraint still makes
-- a double-book impossible even before that swap.

drop policy if exists bookings_insert on public.bookings;
create policy bookings_insert on public.bookings
  for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists bookings_update on public.bookings;
create policy bookings_update on public.bookings
  for update to authenticated
  using (
    auth.uid() = user_id
    or public.my_role() = 'admin'
    or resource_id in (
      select r.id from public.resources r
      join public.tenants t on t.id = r.tenant_id
      where t.owner_id = auth.uid()
    )
  )
  with check (
    auth.uid() = user_id
    or public.my_role() = 'admin'
    or resource_id in (
      select r.id from public.resources r
      join public.tenants t on t.id = r.tenant_id
      where t.owner_id = auth.uid()
    )
  );

-- ── platform_settings ───────────────────────────────────────────────────────
alter table public.platform_settings enable row level security;

drop policy if exists platform_settings_select on public.platform_settings;
create policy platform_settings_select on public.platform_settings
  for select to anon, authenticated using (true);  -- commission/currency are read app-wide

drop policy if exists platform_settings_admin_write on public.platform_settings;
create policy platform_settings_admin_write on public.platform_settings
  for all to authenticated
  using (public.my_role() = 'admin')
  with check (public.my_role() = 'admin');

-- ── subscription_plans ──────────────────────────────────────────────────────
alter table public.subscription_plans enable row level security;

drop policy if exists subscription_plans_select on public.subscription_plans;
create policy subscription_plans_select on public.subscription_plans
  for select to anon, authenticated using (true);

drop policy if exists subscription_plans_admin_write on public.subscription_plans;
create policy subscription_plans_admin_write on public.subscription_plans
  for all to authenticated
  using (public.my_role() = 'admin')
  with check (public.my_role() = 'admin');

-- NOTE: if you also have an `invoices` table, add equivalent policies
-- (tenant reads own via tenant_id; admin all). It isn't queried by the app yet.
