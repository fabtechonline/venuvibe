-- ============================================================================
-- 0008 · Payments table (Phase 2 · gateway-agnostic scaffold)
-- ----------------------------------------------------------------------------
-- Tracks one payment attempt/transaction per booking, independent of which
-- gateway is chosen. The Edge Functions (service role) write here; users only
-- read the status of payments for their own bookings. SAFE TO RE-RUN.
-- ============================================================================

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid references public.bookings(id) on delete cascade,
  amount numeric not null,
  currency text not null default 'ZAR',
  gateway text,                              -- payfast | paystack | stripe | ...
  gateway_ref text,                          -- session/transaction id
  status text not null default 'pending',    -- pending | paid | failed | refunded
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists payments_booking_idx
  on public.payments (booking_id);

alter table public.payments enable row level security;

-- Users read payments for their own bookings; admins read all.
drop policy if exists payments_select on public.payments;
create policy payments_select on public.payments
  for select to authenticated
  using (
    booking_id in (select id from public.bookings where user_id = auth.uid())
    or public.get_user_role() = 'admin'
  );

-- No INSERT/UPDATE policy on purpose: only the service-role Edge Functions
-- write payments (the service key bypasses RLS), so clients can't forge them.
