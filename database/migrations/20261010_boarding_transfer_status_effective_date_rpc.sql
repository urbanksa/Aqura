begin;

create or replace function public.set_boarding_transfer_employee_status(
  p_employee_id text,
  p_new_status text,
  p_effective_date date,
  p_reason text
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := public.aqura_current_user_id();
  v_current_status text;
  v_result record;
begin
  if v_actor is null or not exists (select 1 from public.users u where u.id = v_actor and u.status = 'active' and (coalesce(u.is_master_admin, false) or exists (select 1 from public.button_permissions bp where bp.user_id = u.id and bp.button_code = 'EMPLOYEE_MASTER' and bp.is_enabled = true))) then raise exception 'Employee Master permission required'; end if;
  if not exists (select 1 from public.hr_employee_master m where m.id = p_employee_id) then raise exception 'Employee not found'; end if;
  if p_new_status not in ('Job (With Finger)', 'Remote Job') then raise exception 'Onboarding status must be Job (With Finger) or Remote Job'; end if;
  if p_effective_date is null then raise exception 'Effective Date is required'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Reason is required'; end if;
  select h.status into v_current_status from public.hr_employee_status_history h where h.employee_id = p_employee_id and h.effective_to is null order by h.effective_from desc nulls last, h.id desc limit 1;
  if v_current_status = p_new_status then
    select * into v_result from public.update_current_status_effective_date(p_employee_id, p_effective_date, trim(p_reason)) limit 1;
  else
    select * into v_result from public.change_employee_status(p_employee_id, p_new_status, p_effective_date, trim(p_reason), v_actor) limit 1;
  end if;
  return jsonb_build_object('employee_id', p_employee_id, 'status', p_new_status, 'effective_from', p_effective_date, 'reason', trim(p_reason));
end;
$$;

revoke all on function public.set_boarding_transfer_employee_status(text, text, date, text) from public, anon;
grant execute on function public.set_boarding_transfer_employee_status(text, text, date, text) to authenticated, service_role;

commit;
