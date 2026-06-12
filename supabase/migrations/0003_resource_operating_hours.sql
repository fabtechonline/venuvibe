-- ============================================================================
-- 0003 · Per-resource operating hours (Phase 1)
-- ----------------------------------------------------------------------------
-- Replaces the hard-coded 07:00–23:00 slot window in the availability screen
-- with per-resource hours. Defaults preserve today's behaviour, so this is
-- safe to apply before the client/UI changes land.
--
-- Times are LOCAL wall-clock in the resource's own `timezone` column.
-- SAFE TO RE-RUN.
-- ============================================================================

alter table public.resources
  add column if not exists open_time  time not null default '07:00',
  add column if not exists close_time time not null default '23:00';

-- Optional sanity check: close must be after open.
alter table public.resources
  drop constraint if exists resources_hours_valid;
alter table public.resources
  add constraint resources_hours_valid check (close_time > open_time);

-- Client follow-up:
--  • Resource model: add openTime/closeTime.
--  • resource_editor_screen: let tenants set hours.
--  • availability_calendar._generateTimeSlots(): use the resource's
--    open_time/close_time instead of the hard-coded 7 and 23.
