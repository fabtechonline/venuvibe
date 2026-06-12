-- ============================================================================
-- 0004 · Align platform_settings with the app model (Phase 1 bugfix)
-- ----------------------------------------------------------------------------
-- The PlatformSettings model reads/writes `cancellation_window_hours` and reads
-- `updated_at`, but the table had neither (it had only currency / commission_*
-- / single_row_check). Result: admin "Save commission settings" failed at the
-- DB level (unknown column), and M7's cancellation window always fell back to
-- the 24h default. Adds the columns; default 24 preserves current behaviour.
-- SAFE TO RE-RUN.
-- ============================================================================

alter table public.platform_settings
  add column if not exists cancellation_window_hours integer not null default 24,
  add column if not exists updated_at timestamptz default now();
