begin;

create or replace function public.get_boarding_transfer_insurance_companies()
returns table (id text, name_en text, name_ar text)
language sql stable security invoker set search_path = public as $$
  select c.id::text, c.name_en::text, c.name_ar::text
  from public.hr_insurance_companies c
  order by c.name_en, c.name_ar;
$$;

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
    'driving_licence_number', coalesce(m.driving_licence_number, ''), 'driving_licence_expiry_date', m.driving_licence_expiry_date,
    'driving_licence_document_url', coalesce(m.driving_licence_document_url, ''),
    'contract_expiry_date', m.contract_expiry_date, 'contract_document_url', coalesce(m.contract_document_url, ''),
    'insurance_company_id', coalesce(m.insurance_company_id, ''), 'insurance_expiry_date', m.insurance_expiry_date,
    'biometric_link', case when nullif(m.employee_id_mapping ->> p_branch_id::text, '') is null then null else jsonb_build_object('branch_id', b.id, 'branch_name', coalesce(b.name_en, b.name_ar, 'Branch ' || p_branch_id::text), 'biometric_id', m.employee_id_mapping ->> p_branch_id::text) end,
    'erp_user', case when erp.erp_user_id is null and erp.erp_username is null then null else jsonb_build_object('username', coalesce(erp.erp_username, ''), 'user_id', coalesce(erp.erp_user_id, '')) end
  ) from public.hr_employee_master m
  left join public.branches b on b.id = p_branch_id
  left join lateral (select c.erp_username::text, c.erp_user_id::text from public.user_erp_credentials c where c.user_id = p_user_id and c.aqura_branch_id = p_branch_id limit 1) erp on true
  where m.user_id = p_user_id limit 1;
$$;

create or replace function public.set_boarding_transfer_health_insurance(p_employee_id text, p_insurance_company_id text, p_insurance_expiry_date date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public.aqura_current_user_id(); v_result public.hr_employee_master%rowtype; v_company_id text := nullif(trim(coalesce(p_insurance_company_id, '')), '');
begin
  if v_actor is null or not exists (select 1 from public.users u where u.id = v_actor and u.status = 'active' and (coalesce(u.is_master_admin, false) or exists (select 1 from public.button_permissions bp where bp.user_id = u.id and bp.button_code = 'EMPLOYEE_MASTER' and bp.is_enabled = true))) then raise exception 'Employee Master permission required'; end if;
  if v_company_id is not null and not exists (select 1 from public.hr_insurance_companies c where c.id = v_company_id) then raise exception 'Insurance company not found'; end if;
  update public.hr_employee_master m set insurance_company_id = v_company_id, insurance_expiry_date = p_insurance_expiry_date, updated_at = now() where m.id = p_employee_id returning m.* into v_result;
  if not found then raise exception 'Employee not found'; end if;
  return jsonb_build_object('employee_id', v_result.id, 'insurance_company_id', coalesce(v_result.insurance_company_id, ''), 'insurance_expiry_date', v_result.insurance_expiry_date);
end;
$$;

create or replace function public.create_boarding_transfer_insurance_company(p_name_en text, p_name_ar text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public.aqura_current_user_id(); v_result public.hr_insurance_companies%rowtype; v_name_en text := trim(coalesce(p_name_en, '')); v_name_ar text := trim(coalesce(p_name_ar, ''));
begin
  if v_actor is null or not exists (select 1 from public.users u where u.id = v_actor and u.status = 'active' and (coalesce(u.is_master_admin, false) or exists (select 1 from public.button_permissions bp where bp.user_id = u.id and bp.button_code = 'EMPLOYEE_MASTER' and bp.is_enabled = true))) then raise exception 'Employee Master permission required'; end if;
  if v_name_en = '' or v_name_ar = '' then raise exception 'English and Arabic company names are required'; end if;
  if exists (select 1 from public.hr_insurance_companies c where lower(c.name_en) = lower(v_name_en) or c.name_ar = v_name_ar) then raise exception 'Insurance company already exists'; end if;
  insert into public.hr_insurance_companies (name_en, name_ar) values (v_name_en, v_name_ar) returning * into v_result;
  return jsonb_build_object('id', v_result.id, 'name_en', v_result.name_en, 'name_ar', v_result.name_ar);
end;
$$;

revoke all on function public.get_boarding_transfer_insurance_companies() from public, anon;
revoke all on function public.set_boarding_transfer_health_insurance(text, text, date) from public, anon;
revoke all on function public.create_boarding_transfer_insurance_company(text, text) from public, anon;
grant execute on function public.get_boarding_transfer_insurance_companies() to authenticated, service_role;
grant execute on function public.set_boarding_transfer_health_insurance(text, text, date) to authenticated, service_role;
grant execute on function public.create_boarding_transfer_insurance_company(text, text) to authenticated, service_role;

commit;
