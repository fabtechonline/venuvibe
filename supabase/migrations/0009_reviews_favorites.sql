-- ============================================================================
-- 0009 · Reviews & favorites (Phase 3)
-- ----------------------------------------------------------------------------
-- reviews: one rating (1–5) + optional comment per user per resource. Public
--   read; a user may only write their own, and only for a resource they have a
--   confirmed/completed booking on (prevents fake reviews).
-- favorites: a user's saved resources. Private to the user.
-- SAFE TO RE-RUN.
-- ============================================================================

-- ── reviews ─────────────────────────────────────────────────────────────────
create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  resource_id uuid not null references public.resources(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (resource_id, user_id)
);
create index if not exists reviews_resource_idx on public.reviews (resource_id);

alter table public.reviews enable row level security;

drop policy if exists reviews_read on public.reviews;
create policy reviews_read on public.reviews
  for select to anon, authenticated using (true);

drop policy if exists reviews_write on public.reviews;
create policy reviews_write on public.reviews
  for all to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.bookings b
      where b.user_id = auth.uid()
        and b.resource_id = reviews.resource_id
        and b.status in ('confirmed', 'completed')
    )
  );

-- ── favorites ───────────────────────────────────────────────────────────────
create table if not exists public.favorites (
  user_id uuid not null references public.profiles(id) on delete cascade,
  resource_id uuid not null references public.resources(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, resource_id)
);

alter table public.favorites enable row level security;

drop policy if exists favorites_own on public.favorites;
create policy favorites_own on public.favorites
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
