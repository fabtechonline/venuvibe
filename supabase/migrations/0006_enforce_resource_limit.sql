-- ============================================================================
-- 0006 · Enforce subscription plan resource limit (Phase 2 · 2b)
-- ----------------------------------------------------------------------------
-- A BEFORE INSERT trigger on resources that blocks a tenant from creating more
-- resources than their plan's max_resources. Server-side backstop for the
-- client check in resource_editor_screen. SAFE TO RE-RUN.
-- ============================================================================

create or replace function public.enforce_resource_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit int;
  v_count int;
begin
  -- the tenant's plan limit, else the smallest active plan's limit, else 1
  select coalesce(
    (select sp.max_resources
       from public.tenants t
       join public.subscription_plans sp on sp.id = t.subscription_plan_id
      where t.id = NEW.tenant_id),
    (select min(max_resources) from public.subscription_plans where is_active),
    1
  ) into v_limit;

  select count(*) into v_count
    from public.resources
    where tenant_id = NEW.tenant_id;

  if v_count >= v_limit then
    raise exception 'Plan resource limit reached (% allowed)', v_limit
      using errcode = 'check_violation';
  end if;

  return NEW;
end;
$$;

drop trigger if exists resources_enforce_limit on public.resources;
create trigger resources_enforce_limit
  before insert on public.resources
  for each row
  execute function public.enforce_resource_limit();
