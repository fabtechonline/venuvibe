-- ============================================================================
-- 0005 · Schema-drift fixes (Phase 1)
-- ----------------------------------------------------------------------------
-- The Dart models write columns the tables were missing, so several writes
-- failed at the DB level:
--   • tenants.status        → createTenant / approve / suspend / M4 onboarding
--   • subscription_plans.features + is_popular → admin plan create/edit
-- Adds them with safe defaults and backfills existing tenants. SAFE TO RE-RUN.
-- ============================================================================

-- ── tenants.status (pending | approved | suspended) ──
alter table public.tenants
  add column if not exists status text not null default 'pending';

-- existing active tenants are treated as already approved
update public.tenants
  set status = 'approved'
  where is_active = true and status = 'pending';

-- ── subscription_plans.features (text[]) + is_popular ──
alter table public.subscription_plans
  add column if not exists features text[] not null default '{}',
  add column if not exists is_popular boolean not null default false;
