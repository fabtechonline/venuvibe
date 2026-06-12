-- ============================================================================
-- 0007 · Invoice generation (Phase 2 · 2d, gateway-independent)
-- ----------------------------------------------------------------------------
-- An admin-only RPC that creates one invoice per tenant for a billing period:
--   subscription_amount = tenant's plan price_monthly
--   commission_amount   = sum of platform commission on the tenant's bookings
--                         (confirmed/completed) whose start date is in-period
--   total_amount        = subscription + commission
-- Idempotent: a unique (tenant, period) index + ON CONFLICT DO NOTHING means
-- re-running only fills in missing invoices and never overwrites a paid one.
-- SAFE TO RE-RUN.
-- ============================================================================

create unique index if not exists invoices_tenant_period_uq
  on public.invoices (tenant_id, period_start, period_end);

create or replace function public.generate_invoices(
  p_period_start date,
  p_period_end date
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
begin
  if public.get_user_role() <> 'admin' then
    raise exception 'Only admins can generate invoices' using errcode = '42501';
  end if;

  insert into public.invoices (
    tenant_id, period_start, period_end,
    subscription_amount, commission_amount, total_amount, status
  )
  select
    t.id,
    p_period_start,
    p_period_end,
    coalesce(sp.price_monthly, 0),
    coalesce(comm.amount, 0),
    coalesce(sp.price_monthly, 0) + coalesce(comm.amount, 0),
    'pending'
  from public.tenants t
  left join public.subscription_plans sp on sp.id = t.subscription_plan_id
  left join lateral (
    select sum(b.commission_amount) as amount
    from public.bookings b
    join public.resources r on r.id = b.resource_id
    where r.tenant_id = t.id
      and b.status in ('confirmed', 'completed')
      and b.start_time::date between p_period_start and p_period_end
  ) comm on true
  on conflict (tenant_id, period_start, period_end) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.generate_invoices(date, date) to authenticated;
