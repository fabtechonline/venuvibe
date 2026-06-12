# Supabase migrations — Phase 1

Reviewable SQL for the database half of Phase 1. **Run each file in the Supabase
SQL Editor** (Dashboard → SQL Editor → paste → Run), in order. All are
idempotent (safe to re-run).

| File | What it does | Phase 1 item |
|------|--------------|--------------|
| `0001_prevent_double_booking.sql` | Exclusion constraint so overlapping bookings are impossible; `get_busy_slots()` RPC for availability | **C4** |
| `0002_rls_policies.sql` | Row-Level Security on every table — the real auth boundary | **RLS** |
| `0003_resource_operating_hours.sql` | Per-resource `open_time`/`close_time` (defaults keep current behaviour) | **Hours** |

## Suggested order & why
1. **0001** first — pure integrity win, nothing depends on it, and it adds the
   `get_busy_slots` RPC that 0002 assumes for availability.
2. **0002** next — but read the two `HARDENING` notes first. After running,
   **test every role** (see below).
3. **0003** any time — defaults preserve behaviour, so it won't break anything
   before the client UI lands.

## Test after 0002 (RLS) — sign in as each role
- **Customer** (`user@venuevibe.test`): can browse resources, see **only their own**
  bookings, create/cancel their own. Cannot open another user's booking.
- **Tenant** (`tenant@venuevibe.test`): sees **only their** resources, durations,
  blocks, and bookings on their resources. Cannot edit another tenant's.
- **Admin**: full access to categories, tenants, settings, plans.

If a screen breaks, you can disable RLS on one table while you investigate:
```sql
alter table public.<table> disable row level security;
```

## Client follow-ups these migrations imply (not done yet)
- **0001 / 0002 — availability:** `availability_calendar.dart` currently reads
  other users' bookings via `getResourceBookings()`. Under RLS that returns only
  the viewer's own — so switch it to call the **`get_busy_slots`** RPC. (The
  exclusion constraint already prevents double-books even before this swap.)
- **0003 — hours:** add `openTime`/`closeTime` to the `Resource` model, a tenant
  editor field, and use them in `_generateTimeSlots()` instead of `7`/`23`.

## Rollback
- Constraint: `alter table public.bookings drop constraint bookings_no_overlap;`
- A policy: `drop policy <name> on public.<table>;`
- RLS off for a table: `alter table public.<table> disable row level security;`
