begin;

create or replace function public.set_boarding_transfer_employee_position(
  p_employee_id text,
  p_user_id uuid,
  p_new_position_id uuid
)
returns jsonb
language plpgsql
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

  if p_new_position_id is null or not exists (
    select 1 from public.hr_positions p
    where p.id = p_new_position_id and p.is_active = true
  ) then
    raise exception 'Selected position is not active or does not exist';
  end if;

  if not exists (
    select 1 from public.hr_employee_master m
    where m.id = p_employee_id and m.user_id = p_user_id
  ) then
    raise exception 'Employee is not linked to the selected user';
  end if;

  update public.users
  set position_id = p_new_position_id, updated_at = now()
  where id = p_user_id;

  update public.hr_employee_master
  set current_position_id = p_new_position_id, updated_at = now()
  where id = p_employee_id and user_id = p_user_id;

  return jsonb_build_object(
    'employee_id', p_employee_id,
    'user_id', p_user_id,
    'position_id', p_new_position_id
  );
end;
$$;

revoke all on function public.set_boarding_transfer_employee_position(text, uuid, uuid) from public, anon;
grant execute on function public.set_boarding_transfer_employee_position(text, uuid, uuid) to authenticated, service_role;

commit;
