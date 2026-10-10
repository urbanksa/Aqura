begin;

create or replace function public.get_boarding_transfer_employee_details(p_user_id uuid, p_branch_id bigint)
returns jsonb language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'id', m.id, 'name_en', coalesce(m.name_en, ''), 'name_ar', coalesce(m.name_ar, ''),
    'whatsapp_number', coalesce(m.whatsapp_number, ''), 'email', coalesce(m.email, ''),
    'sponsorship_status', coalesce(m.sponsorship_status, false), 'sponsor_id', m.sponsor_id,
    'nationality_id', m.nationality_id, 'id_number', coalesce(m.id_number, ''),
    'id_expiry_date', m.id_expiry_date, 'work_permit_expiry_date', m.work_permit_expiry_date,
    'id_document_url', coalesce(m.id_document_url, ''),
    'health_card_number', coalesce(m.health_card_number, ''), 'health_card_expiry_date', m.health_card_expiry_date,
    'health_educational_renewal_date', m.health_educational_renewal_date,
    'health_card_document_url', coalesce(m.health_card_document_url, ''),
    'driving_licence_number', coalesce(m.driving_licence_number, ''),
    'driving_licence_expiry_date', m.driving_licence_expiry_date,
    'driving_licence_document_url', coalesce(m.driving_licence_document_url, ''),
    'contract_expiry_date', m.contract_expiry_date,
    'contract_document_url', coalesce(m.contract_document_url, ''),
    'biometric_link', case when nullif(m.employee_id_mapping ->> p_branch_id::text, '') is null then null else jsonb_build_object('branch_id', b.id, 'branch_name', coalesce(b.name_en, b.name_ar, 'Branch ' || p_branch_id::text), 'biometric_id', m.employee_id_mapping ->> p_branch_id::text) end,
    'erp_user', case when erp.erp_user_id is null and erp.erp_username is null then null else jsonb_build_object('username', coalesce(erp.erp_username, ''), 'user_id', coalesce(erp.erp_user_id, '')) end
  ) from public.hr_employee_master m
  left join public.branches b on b.id = p_branch_id
  left join lateral (select c.erp_username::text, c.erp_user_id::text from public.user_erp_credentials c where c.user_id = p_user_id and c.aqura_branch_id = p_branch_id limit 1) erp on true
  where m.user_id = p_user_id limit 1;
$$;

create or replace function public.set_boarding_transfer_contract_details(p_employee_id text, p_contract_expiry_date date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public.aqura_current_user_id(); v_result public.hr_employee_master%rowtype;
begin
  if v_actor is null or not exists (select 1 from public.users u where u.id = v_actor and u.status = 'active' and (coalesce(u.is_master_admin, false) or exists (select 1 from public.button_permissions bp where bp.user_id = u.id and bp.button_code = 'EMPLOYEE_MASTER' and bp.is_enabled = true))) then raise exception 'Employee Master permission required'; end if;
  update public.hr_employee_master m set contract_expiry_date = p_contract_expiry_date, updated_at = now() where m.id = p_employee_id returning m.* into v_result;
  if not found then raise exception 'Employee not found'; end if;
  return jsonb_build_object('employee_id', v_result.id, 'contract_expiry_date', v_result.contract_expiry_date);
end;
$$;

create or replace function public.set_boarding_transfer_contract_document(p_employee_id text, p_contract_document_url text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public.aqura_current_user_id(); v_result public.hr_employee_master%rowtype; v_document_url text := nullif(trim(coalesce(p_contract_document_url, '')), '');
begin
  if v_actor is null or not exists (select 1 from public.users u where u.id = v_actor and u.status = 'active' and (coalesce(u.is_master_admin, false) or exists (select 1 from public.button_permissions bp where bp.user_id = u.id and bp.button_code = 'EMPLOYEE_MASTER' and bp.is_enabled = true))) then raise exception 'Employee Master permission required'; end if;
  if v_document_url is null then raise exception 'Contract document URL is required'; end if;
  update public.hr_employee_master m set contract_document_url = v_document_url, updated_at = now() where m.id = p_employee_id returning m.* into v_result;
  if not found then raise exception 'Employee not found'; end if;
  return jsonb_build_object('employee_id', v_result.id, 'contract_document_url', v_result.contract_document_url);
end;
$$;

revoke all on function public.set_boarding_transfer_contract_details(text, date) from public, anon;
revoke all on function public.set_boarding_transfer_contract_document(text, text) from public, anon;
grant execute on function public.set_boarding_transfer_contract_details(text, date) to authenticated, service_role;
grant execute on function public.set_boarding_transfer_contract_document(text, text) to authenticated, service_role;

commit;
