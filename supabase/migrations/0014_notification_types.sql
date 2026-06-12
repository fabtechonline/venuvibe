-- ============================================================================
-- 0014 · Widen notifications.type for the approval flow (hotfix)
-- ----------------------------------------------------------------------------
-- The pre-existing check only allowed booking/reminder/system/payment, which
-- made create_booking_with_addons' "booking_request" notification fail and
-- roll back every custom booking. SAFE TO RE-RUN.
-- ============================================================================

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in (
    'booking', 'reminder', 'system', 'payment', 'cancellation',
    'booking_request', 'booking_approved', 'booking_rejected'
  ));

-- Prove the approval-flow types insert cleanly (rolled back via exception).
do $$
declare
  v_user uuid;
begin
  select id into v_user from auth.users limit 1;
  insert into public.notifications (user_id, title, message, type)
  values (v_user, 'test', 'test', 'booking_request');
  raise exception 'ROLLBACK_TEST_OK';
exception
  when others then
    if sqlerrm <> 'ROLLBACK_TEST_OK' then raise; end if;
end $$;

select 'notifications_type_check widened' as result;
