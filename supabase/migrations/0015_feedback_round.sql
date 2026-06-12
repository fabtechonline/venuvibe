-- ============================================================================
-- 0015 · Feedback round (2026-06-12 testing)
-- ----------------------------------------------------------------------------
-- 1) categories had ONLY a select policy — every admin create/edit/delete
--    silently failed under RLS. Add the missing admin write policy.
-- 2) Buffer between bookings: allow up to 48 hours (was 4h).
-- 3) Add-on max_qty: allow up to 999 per booking (was 99).
-- 4) Venues (tenants) get a contact person; address/phone already exist.
-- SAFE TO RE-RUN.
-- ============================================================================

-- ── 1) Categories: admin-only writes ────────────────────────────────────────
drop policy if exists categories_write on public.categories;
create policy categories_write on public.categories
  for all to authenticated
  using (public.get_user_role() = 'admin')
  with check (public.get_user_role() = 'admin');

-- ── 2) Buffer up to 48h ──────────────────────────────────────────────────────
alter table public.resources drop constraint if exists resources_buffer_valid;
alter table public.resources add constraint resources_buffer_valid
  check (buffer_minutes between 0 and 2880);

-- ── 3) Add-on quantities up to 3 digits ──────────────────────────────────────
alter table public.resource_addons drop constraint if exists resource_addons_max_qty_check;
alter table public.resource_addons add constraint resource_addons_max_qty_check
  check (max_qty between 1 and 999);

-- ── 4) Venue contact person ──────────────────────────────────────────────────
alter table public.tenants
  add column if not exists contact_person text;
