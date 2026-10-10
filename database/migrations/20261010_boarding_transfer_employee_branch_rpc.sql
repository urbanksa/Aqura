begin;

create or replace function public.set_boarding_transfer_employee_branch(
  p_employee_id text,
  p_user_id uuid,
  p_destination_company_id bigint,
  p_destination_branch_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := public.aqura_current_user_id();
  v_previous_user_branch_id bigint;
  v_previous_employee_branch_id integer;
begin
  if v_actor is null or not exists (
    select 1
    from public.users u
    where u.id = v_actor
      and u.status = 'active'
      and (
        coalesce(u.is_master_admin, false)
        or exists (
          select 1
          from public.button_permissions bp
          where bp.user_id = u.id
            and bp.button_code = 'EMPLOYEE_MASTER'
            and bp.is_enabled = true
        )
      )
  ) then
    raise exception 'Employee Master permission required';
  end if;

  if coalesce(trim(p_employee_id), '') = '' or p_user_id is null then
    raise exception 'Employee and user are required';
  end if;

  if p_destination_company_id is null or p_destination_branch_id is null then
    raise exception 'Destination company and branch are required';
  end if;

  if not exists (
    select 1
    from public.branches b
    where b.id = p_destination_branch_id
      and b.company_id = p_destination_company_id
      and b.is_active = true
  ) then
    raise exception 'The selected active branch does not belong to the destination company';
  end if;

  select u.branch_id
  into v_previous_user_branch_id
  from public.users u
  where u.id = p_user_id
  for update;

  if not found then
    raise exception 'User not found';
  end if;

  select m.current_branch_id
  into v_previous_employee_branch_id
  from public.hr_employee_master m
  where m.id = p_employee_id
    and m.user_id = p_user_id
  for update;

  if not found then
    raise exception 'Employee is not linked to the selected user';
  end if;

  update public.users
  set branch_id = p_destination_branch_id,
      updated_at = now()
  where id = p_user_id;

  update public.hr_employee_master
  set current_branch_id = p_destination_branch_id::integer,
      updated_at = now()
  where id = p_employee_id
    and user_id = p_user_id;

  return jsonb_build_object(
    'employee_id', p_employee_id,
    'user_id', p_user_id,
    'previous_user_branch_id', v_previous_user_branch_id,
    'previous_employee_branch_id', v_previous_employee_branch_id,
    'destination_company_id', p_destination_company_id,
    'destination_branch_id', p_destination_branch_id
  );
end;
$$;

revoke all on function public.set_boarding_transfer_employee_branch(text, uuid, bigint, bigint) from public, anon;
grant execute on function public.set_boarding_transfer_employee_branch(text, uuid, bigint, bigint) to authenticated, service_role;

commit;
