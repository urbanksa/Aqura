begin;

create or replace function public.set_boarding_transfer_sponsorship(
  p_employee_id text,
  p_sponsorship_status boolean,
  p_sponsor_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := public.aqura_current_user_id();
  v_result public.hr_employee_master%rowtype;
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

  if p_sponsorship_status and p_sponsor_id is null then
    raise exception 'Sponsor company is required for a sponsored employee';
  end if;

  if p_sponsorship_status and not exists (
    select 1 from public.company_master c where c.id = p_sponsor_id
  ) then
    raise exception 'Sponsor company not found';
  end if;

  update public.hr_employee_master m
  set
    sponsorship_status = p_sponsorship_status,
    sponsor_id = case when p_sponsorship_status then p_sponsor_id else null end,
    updated_at = now()
  where m.id = p_employee_id
  returning m.* into v_result;

  if not found then
    raise exception 'Employee not found';
  end if;

  return jsonb_build_object(
    'employee_id', v_result.id,
    'sponsorship_status', coalesce(v_result.sponsorship_status, false),
    'sponsor_id', v_result.sponsor_id
  );
end;
$$;

revoke all on function public.set_boarding_transfer_sponsorship(text, boolean, bigint) from public, anon;
grant execute on function public.set_boarding_transfer_sponsorship(text, boolean, bigint) to authenticated, service_role;

commit;
