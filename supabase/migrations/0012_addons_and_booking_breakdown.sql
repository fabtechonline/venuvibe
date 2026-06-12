-- ============================================================================
-- 0012 · Add-ons + booking price breakdown (booking-flow redesign, step 2/3)
-- ----------------------------------------------------------------------------
-- Per-resource add-on catalog (racquet hire, tables, cutlery…) with max qty,
-- booking line items with name/price SNAPSHOTS (catalog edits never rewrite
-- history), and breakdown columns on bookings. total_price/commission_amount
-- remain the authoritative roll-ups, so generate_invoices and the payment
-- Edge Functions keep working untouched. SAFE TO RE-RUN.
-- ============================================================================

-- ── Add-on catalog (per resource) ────────────────────────────────────────────
create table if not exists public.resource_addons (
  id          uuid primary key default gen_random_uuid(),
  resource_id uuid not null references public.resources(id) on delete cascade,
  name        text not null,
  price       numeric(10,2) not null check (price >= 0),
  max_qty     int not null default 10 check (max_qty between 1 and 99),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

alter table public.resource_addons enable row level security;

drop policy if exists resource_addons_select on public.resource_addons;
create policy resource_addons_select on public.resource_addons
  for select to anon, authenticated using (true);

drop policy if exists resource_addons_write on public.resource_addons;
create policy resource_addons_write on public.resource_addons
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

-- ── Booking add-on line items (snapshots) ────────────────────────────────────
create table if not exists public.booking_addons (
  id         uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  addon_id   uuid references public.resource_addons(id) on delete set null,
  name       text not null,
  unit_price numeric(10,2) not null,
  qty        int not null check (qty > 0),
  created_at timestamptz not null default now()
);

alter table public.booking_addons enable row level security;

-- Read: the booking's customer, the resource's tenant owner, or admin.
drop policy if exists booking_addons_select on public.booking_addons;
create policy booking_addons_select on public.booking_addons
  for select to authenticated
  using (
    public.get_user_role() = 'admin'
    or booking_id in (select b.id from public.bookings b where b.user_id = auth.uid())
    or booking_id in (
      select b.id from public.bookings b
      join public.resources r on r.id = b.resource_id
      join public.tenants t on t.id = r.tenant_id
      where t.owner_id = auth.uid()
    )
  );
-- Writes happen only inside the create_booking_with_addons RPC (definer).

-- ── Price breakdown on bookings ──────────────────────────────────────────────
alter table public.bookings
  add column if not exists base_price      numeric(10,2),
  add column if not exists addons_total    numeric(10,2) not null default 0,
  add column if not exists discount_amount numeric(10,2) not null default 0;

-- Backfill breakdown for any pre-existing rows.
update public.bookings
   set base_price = total_price - coalesce(commission_amount, 0)
 where base_price is null;
