begin;

create or replace function public.get_boarding_transfer_logs()
returns table (
  id bigint,
  event_type text,
  employee_id text,
  employee_name_en text,
  employee_name_ar text,
  effective_date date,
  source_company_name text,
  source_branch_name text,
  destination_company_name text,
  destination_branch_name text,
  performed_by_name text,
  performed_at timestamptz,
  details jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_actor uuid := public.aqura_current_user_id();
begin
  if v_actor is null or not exists (
    select 1 from public.users u
    where u.id = v_actor
      and u.status = 'active'
      and (
        coalesce(u.is_master_admin, false)
        or exists (
          select 1 from public.button_permissions bp
          where bp.user_id = u.id
            and bp.button_code = 'EMPLOYEE_MASTER'
            and bp.is_enabled = true
        )
      )
  ) then
    raise exception 'Employee Master permission required';
  end if;

  return query
  select
    l.id,
    l.event_type,
    l.employee_id,
    coalesce(employee.name_en, '')::text,
    coalesce(employee.name_ar, '')::text,
    l.effective_date,
    coalesce(source_company.name_en, source_company.name_ar, '')::text,
    coalesce(source_branch.name_en, source_branch.name_ar, '')::text,
    coalesce(destination_company.name_en, destination_company.name_ar, '')::text,
    coalesce(destination_branch.name_en, destination_branch.name_ar, '')::text,
    coalesce(actor_employee.name_en, actor_employee.name_ar, actor.username, '')::text,
    l.performed_at,
    l.details
  from public.boarding_transfer_logs l
  join public.hr_employee_master employee on employee.id = l.employee_id
  left join public.company_master source_company on source_company.id = l.source_company_id
  left join public.branches source_branch on source_branch.id = l.source_branch_id
  left join public.company_master destination_company on destination_company.id = l.destination_company_id
  left join public.branches destination_branch on destination_branch.id = l.destination_branch_id
  left join public.users actor on actor.id = l.performed_by
  left join public.hr_employee_master actor_employee on actor_employee.user_id = actor.id
  order by l.performed_at desc, l.id desc
  limit 500;
end;
$$;

revoke all on function public.get_boarding_transfer_logs() from public, anon;
grant execute on function public.get_boarding_transfer_logs() to authenticated, service_role;

commit;
