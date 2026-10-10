begin;

create or replace function public.get_boarding_transfer_destination_biometrics(
  p_employee_id text,
  p_branch_id bigint
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select jsonb_build_object(
    'current_biometric_id', nullif(m.employee_id_mapping ->> p_branch_id::text, ''),
    'candidates', coalesce((
      select jsonb_agg(
        jsonb_build_object('biometric_id', e.employee_id, 'name', e.name)
        order by e.name, e.employee_id
      )
      from public.hr_employees e
      where e.branch_id = p_branch_id
        and coalesce(e.status, 'active') = 'active'
        and not exists (
          select 1
          from public.hr_employee_master other_m
          where other_m.id <> p_employee_id
            and other_m.employee_id_mapping ->> p_branch_id::text = e.employee_id
        )
    ), '[]'::jsonb)
  )
  from public.hr_employee_master m
  where m.id = p_employee_id;
$$;

revoke all on function public.get_boarding_transfer_destination_biometrics(text, bigint) from public, anon;
grant execute on function public.get_boarding_transfer_destination_biometrics(text, bigint) to authenticated, service_role;

create or replace function public.set_boarding_transfer_employee_branch(
  p_employee_id text,
  p_user_id uuid,
  p_destination_company_id bigint,
  p_destination_branch_id bigint,
  p_biometric_id text
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
  v_existing_biometric_id text;
  v_biometric_id text := nullif(trim(p_biometric_id), '');
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

  if coalesce(trim(p_employee_id), '') = '' or p_user_id is null then
    raise exception 'Employee and user are required';
  end if;
  if p_destination_company_id is null or p_destination_branch_id is null then
    raise exception 'Destination company and branch are required';
  end if;
  if not exists (
    select 1 from public.branches b
    where b.id = p_destination_branch_id
      and b.company_id = p_destination_company_id
      and b.is_active = true
  ) then
    raise exception 'The selected active branch does not belong to the destination company';
  end if;

  select u.branch_id into v_previous_user_branch_id
  from public.users u where u.id = p_user_id for update;
  if not found then raise exception 'User not found'; end if;

  select m.current_branch_id,
         nullif(m.employee_id_mapping ->> p_destination_branch_id::text, '')
  into v_previous_employee_branch_id, v_existing_biometric_id
  from public.hr_employee_master m
  where m.id = p_employee_id and m.user_id = p_user_id
  for update;
  if not found then raise exception 'Employee is not linked to the selected user'; end if;

  v_biometric_id := coalesce(v_existing_biometric_id, v_biometric_id);
  if v_biometric_id is null then
    raise exception 'Select a biometric ID for the destination branch';
  end if;
  if not exists (
    select 1 from public.hr_employees e
    where e.branch_id = p_destination_branch_id
      and e.employee_id = v_biometric_id
      and coalesce(e.status, 'active') = 'active'
  ) then
    raise exception 'Biometric ID not found in the destination branch';
  end if;
  if exists (
    select 1 from public.hr_employee_master other_m
    where other_m.id <> p_employee_id
      and other_m.employee_id_mapping ->> p_destination_branch_id::text = v_biometric_id
  ) then
    raise exception 'Biometric ID is already linked to another employee';
  end if;

  update public.users
  set branch_id = p_destination_branch_id, updated_at = now()
  where id = p_user_id;

  update public.hr_employee_master
  set current_branch_id = p_destination_branch_id::integer,
      employee_id_mapping = jsonb_set(
        coalesce(employee_id_mapping, '{}'::jsonb),
        array[p_destination_branch_id::text],
        to_jsonb(v_biometric_id),
        true
      ),
      updated_at = now()
  where id = p_employee_id and user_id = p_user_id;

  return jsonb_build_object(
    'employee_id', p_employee_id,
    'user_id', p_user_id,
    'previous_user_branch_id', v_previous_user_branch_id,
    'previous_employee_branch_id', v_previous_employee_branch_id,
    'destination_company_id', p_destination_company_id,
    'destination_branch_id', p_destination_branch_id,
    'biometric_id', v_biometric_id
  );
end;
$$;

revoke all on function public.set_boarding_transfer_employee_branch(text, uuid, bigint, bigint, text) from public, anon;
grant execute on function public.set_boarding_transfer_employee_branch(text, uuid, bigint, bigint, text) to authenticated, service_role;

commit;
