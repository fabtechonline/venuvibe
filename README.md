# Venue Vibe

Multi-tenant venue & resource booking platform built with **Flutter** and
**Supabase**.

Three roles in one app:

- **Customers** — discover venues, check live availability, book time slots,
  review & favorite spaces, manage bookings.
- **Venue managers (tenants)** — onboard their venue, manage resources, photos,
  pricing tiers, operating hours, maintenance blocks, and see their bookings &
  earnings.
- **Platform admins** — categories, tenant approval, commission & currency
  settings, subscription plans, invoicing.

## Stack

| Layer | Tech |
|---|---|
| UI / state | Flutter, Riverpod, go_router |
| Backend | Supabase (Postgres + RLS, Auth, Storage, Edge Functions) |
| Integrity | Exclusion constraint (no double-bookings), `get_busy_slots` RPC, plan-limit trigger |

## Project layout

```
lib/src/
  features/      user / tenant / admin screens
  models/        plain Dart models
  repositories/  typed Supabase data access (Riverpod providers)
  routing/       go_router + role guards
supabase/
  migrations/    ordered SQL (constraints, RLS, storage, RPCs)
  functions/     gateway-agnostic payment Edge Functions (scaffold)
```

## Getting started

```bash
flutter pub get
flutter test
flutter run
```

Database setup: apply `supabase/migrations/` in order via the Supabase SQL
editor (each file is idempotent — see `supabase/migrations/README.md`).
