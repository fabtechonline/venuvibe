-- ============================================================================
-- 0001 · Prevent double-booking (Phase 1 · C4)
-- ----------------------------------------------------------------------------
-- Makes overlapping bookings for the same resource IMPOSSIBLE at the database
-- level (race-proof), and adds a privacy-safe RPC the availability screen can
-- use to fetch busy slots without reading other users' booking rows.
--
-- SAFE TO RE-RUN. If the ALTER fails with "conflicting key value violates
-- exclusion constraint", you already have overlapping active bookings — run the
-- diagnostic at the bottom, resolve them, then re-run.
-- ============================================================================

-- Needed to combine "=" (resource_id) with "&&" (time range) in one constraint.
create extension if not exists btree_gist;

-- ── Exclusion constraint: no two active bookings on a resource may overlap ──
-- tstzrange(start,end) with '&&' = "ranges overlap". Filtered to active statuses
-- so cancelled/completed bookings don't block new ones.
alter table public.bookings
  drop constraint if exists bookings_no_overlap;

alter table public.bookings
  add constraint bookings_no_overlap
  exclude using gist (
    resource_id with =,
    tstzrange(start_time, end_time) with &&
  )
  where (status in ('confirmed', 'pending'));

-- The client (checkout_screen) catches Postgres error code 23P01
-- (exclusion_violation) and shows "that slot was just taken".

-- ── Availability RPC: returns only busy ranges + kind, never PII ──
-- Lets any user compute availability without SELECT access to others' bookings,
-- which keeps the bookings RLS policy (migration 0002) strict.
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
         case when b.payment_status = 'pending' then 'pending' else 'booked' end
  from public.bookings b
  where b.resource_id = p_resource_id
    and b.status in ('confirmed', 'pending')
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

-- ── Diagnostic (run manually if the ALTER above fails) ──
-- Lists existing overlapping active bookings you'd need to resolve first:
--
-- select a.id, b.id, a.resource_id, a.start_time, a.end_time
-- from public.bookings a
-- join public.bookings b
--   on a.resource_id = b.resource_id
--  and a.id < b.id
--  and a.status in ('confirmed','pending')
--  and b.status in ('confirmed','pending')
--  and tstzrange(a.start_time, a.end_time) && tstzrange(b.start_time, b.end_time);
