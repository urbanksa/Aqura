begin;

create or replace function public.set_boarding_transfer_identity_details(
  p_employee_id text,
  p_nationality_id text,
  p_id_number text,
  p_id_expiry_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := public.aqura_current_user_id();
  v_result public.hr_employee_master%rowtype;
  v_nationality_id text := nullif(trim(coalesce(p_nationality_id, '')), '');
  v_id_number text := nullif(trim(coalesce(p_id_number, '')), '');
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

  if coalesce(trim(p_employee_id), '') = '' then
    raise exception 'Employee ID is required';
  end if;

  if v_nationality_id is not null and not exists (
    select 1 from public.nationalities n where n.id::text = v_nationality_id
  ) then
    raise exception 'Nationality not found';
  end if;

  update public.hr_employee_master m
  set
    nationality_id = v_nationality_id,
    id_number = v_id_number,
    id_expiry_date = p_id_expiry_date,
    updated_at = now()
  where m.id = p_employee_id
  returning m.* into v_result;

  if not found then
    raise exception 'Employee not found';
  end if;

  return jsonb_build_object(
    'employee_id', v_result.id,
    'nationality_id', v_result.nationality_id,
    'id_number', coalesce(v_result.id_number, ''),
    'id_expiry_date', v_result.id_expiry_date
  );
end;
$$;

revoke all on function public.set_boarding_transfer_identity_details(text, text, text, date) from public, anon;
grant execute on function public.set_boarding_transfer_identity_details(text, text, text, date) to authenticated, service_role;

commit;
