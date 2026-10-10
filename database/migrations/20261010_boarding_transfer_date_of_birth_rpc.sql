begin;

create or replace function public.get_boarding_transfer_employee_details(p_user_id uuid, p_branch_id bigint)
returns jsonb language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'id', m.id, 'name_en', coalesce(m.name_en, ''), 'name_ar', coalesce(m.name_ar, ''),
    'whatsapp_number', coalesce(m.whatsapp_number, ''), 'email', coalesce(m.email, ''),
    'sponsorship_status', coalesce(m.sponsorship_status, false), 'sponsor_id', m.sponsor_id,
    'nationality_id', m.nationality_id, 'id_number', coalesce(m.id_number, ''),
    'id_expiry_date', m.id_expiry_date, 'date_of_birth', m.date_of_birth,
    'work_permit_expiry_date', m.work_permit_expiry_date, 'id_document_url', coalesce(m.id_document_url, ''),
    'health_card_number', coalesce(m.health_card_number, ''), 'health_card_expiry_date', m.health_card_expiry_date,
    'health_educational_renewal_date', m.health_educational_renewal_date,
    'health_card_document_url', coalesce(m.health_card_document_url, ''),
    'driving_licence_number', coalesce(m.driving_licence_number, ''), 'driving_licence_expiry_date', m.driving_licence_expiry_date,
    'driving_licence_document_url', coalesce(m.driving_licence_document_url, ''),
    'contract_expiry_date', m.contract_expiry_date, 'probation_period_expiry_date', m.probation_period_expiry_date,
    'join_date', m.join_date, 'contract_document_url', coalesce(m.contract_document_url, ''),
    'insurance_company_id', coalesce(m.insurance_company_id, ''), 'insurance_expiry_date', m.insurance_expiry_date,
    'bank_name', coalesce(m.bank_name, ''), 'iban', coalesce(m.iban, ''),
    'biometric_link', case when nullif(m.employee_id_mapping ->> p_branch_id::text, '') is null then null else jsonb_build_object('branch_id', b.id, 'branch_name', coalesce(b.name_en, b.name_ar, 'Branch ' || p_branch_id::text), 'biometric_id', m.employee_id_mapping ->> p_branch_id::text) end,
    'erp_user', case when erp.erp_user_id is null and erp.erp_username is null then null else jsonb_build_object('username', coalesce(erp.erp_username, ''), 'user_id', coalesce(erp.erp_user_id, '')) end
  ) from public.hr_employee_master m
  left join public.branches b on b.id = p_branch_id
  left join lateral (select c.erp_username::text, c.erp_user_id::text from public.user_erp_credentials c where c.user_id = p_user_id and c.aqura_branch_id = p_branch_id limit 1) erp on true
  where m.user_id = p_user_id limit 1;
$$;

create or replace function public.set_boarding_transfer_identity_details(
  p_employee_id text,
  p_nationality_id text,
  p_id_number text,
  p_id_expiry_date date,
  p_work_permit_expiry_date date,
  p_date_of_birth date
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public.aqura_current_user_id(); v_result public.hr_employee_master%rowtype; v_nationality_id text := nullif(trim(coalesce(p_nationality_id, '')), ''); v_id_number text := nullif(trim(coalesce(p_id_number, '')), '');
begin
  if v_actor is null or not exists (select 1 from public.users u where u.id = v_actor and u.status = 'active' and (coalesce(u.is_master_admin, false) or exists (select 1 from public.button_permissions bp where bp.user_id = u.id and bp.button_code = 'EMPLOYEE_MASTER' and bp.is_enabled = true))) then raise exception 'Employee Master permission required'; end if;
  if v_nationality_id is not null and not exists (select 1 from public.nationalities n where n.id::text = v_nationality_id) then raise exception 'Nationality not found'; end if;
  update public.hr_employee_master m
  set nationality_id = v_nationality_id, id_number = v_id_number, id_expiry_date = p_id_expiry_date,
      work_permit_expiry_date = case when v_nationality_id = 'SA' then null else p_work_permit_expiry_date end,
      date_of_birth = p_date_of_birth, updated_at = now()
  where m.id = p_employee_id returning m.* into v_result;
  if not found then raise exception 'Employee not found'; end if;
  return jsonb_build_object('employee_id', v_result.id, 'nationality_id', v_result.nationality_id,
    'id_number', coalesce(v_result.id_number, ''), 'id_expiry_date', v_result.id_expiry_date,
    'work_permit_expiry_date', v_result.work_permit_expiry_date, 'date_of_birth', v_result.date_of_birth);
end;
$$;

revoke all on function public.set_boarding_transfer_identity_details(text, text, text, date, date, date) from public, anon;
grant execute on function public.set_boarding_transfer_identity_details(text, text, text, date, date, date) to authenticated, service_role;

commit;
