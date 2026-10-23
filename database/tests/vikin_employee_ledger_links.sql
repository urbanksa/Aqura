-- Run after the Vikin employee-link migration. All fixtures and mappings roll back.
begin;

do $$
declare
  v_admin uuid;
  v_actor uuid;
  v_denied uuid;
  v_target_user uuid;
  v_employee text := 'VIKIN_LINK_TEST_' || gen_random_uuid()::text;
  v_company bigint;
  v_company_two bigint;
  v_polosys_company bigint;
  v_branch bigint;
  v_ledger uuid;
  v_second_ledger uuid;
  v_foreign_ledger uuid;
  v_result jsonb;
  v_before public.vikin_employee_ledger_links%rowtype;
  v_after public.vikin_employee_ledger_links%rowtype;
  v_polosys jsonb := '{"1":987654,"3":123456}'::jsonb;
begin
  if has_function_privilege('anon', 'public.get_vikin_employee_link_context(text)', 'execute')
    or has_function_privilege('anon', 'public.set_vikin_employee_ledger_link(text,uuid)', 'execute')
    or has_function_privilege('anon', 'public.vikin_employee_links_can_access()', 'execute') then
    raise exception 'Anonymous employee ledger RPC access must be denied';
  end if;
  if has_table_privilege('authenticated', 'public.vikin_employee_ledger_links', 'select,insert,update,delete') then
    raise exception 'Link mappings must only be accessed through validated RPCs';
  end if;
  perform set_config('request.jwt.claims', '{}', true);
  begin
    perform public.get_vikin_employee_link_context(v_employee);
    raise exception 'Expected unauthenticated read rejection';
  exception when insufficient_privilege then null; end;
  begin
    perform public.set_vikin_employee_ledger_link(v_employee, null);
    raise exception 'Expected unauthenticated write rejection';
  exception when insufficient_privilege then null; end;

  select id into strict v_admin from public.users
  where status = 'active' and is_master_admin = true limit 1;
  select id into strict v_branch from public.branches where is_active limit 1;
  insert into public.users(username, password_hash, salt, quick_access_code, quick_access_salt, user_type)
  values ('vikin_link_' || gen_random_uuid()::text, 'test-only', 'test-only', gen_random_uuid()::text, 'test-only', 'global')
  returning id into v_actor;
  insert into public.users(username, password_hash, salt, quick_access_code, quick_access_salt, user_type)
  values ('vikin_deny_' || gen_random_uuid()::text, 'test-only', 'test-only', gen_random_uuid()::text, 'test-only', 'global')
  returning id into v_denied;
  insert into public.users(username, password_hash, salt, quick_access_code, quick_access_salt, user_type, status)
  values ('vikin_emp_' || gen_random_uuid()::text, 'test-only', 'test-only', gen_random_uuid()::text, 'test-only', 'global', 'inactive')
  returning id into v_target_user;
  insert into public.button_permissions(user_id, button_code, is_enabled) values (v_actor, 'LINK_ID', true);
  insert into public.company_master(name_en, name_ar, erp_provider)
  values (v_employee, v_employee, 'vikin') returning id into v_company;
  insert into public.company_master(name_en, name_ar, erp_provider)
  values (v_employee || ' second', v_employee || ' second', 'vikin') returning id into v_company_two;
  insert into public.company_master(name_en, name_ar, erp_provider)
  values (v_employee || ' Polosys', v_employee || ' Polosys', 'polosys') returning id into v_polosys_company;
  insert into public.hr_employee_master(id, user_id, current_branch_id, name_en, sponsor_id, erp_employee_id_mapping)
  values (v_employee, v_target_user, v_branch, 'Test employee', v_company, v_polosys);

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_denied)::text, true);
  begin
    perform public.get_vikin_employee_link_context(v_employee);
    raise exception 'Expected missing Link ID permission read rejection';
  exception when insufficient_privilege then null; end;
  begin
    perform public.set_vikin_employee_ledger_link(v_employee, null);
    raise exception 'Expected missing Link ID permission write rejection';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor)::text, true);
  v_result := public.get_vikin_employee_link_context(v_employee);
  if v_result->'ledgers' is distinct from '[]'::jsonb or v_result->'link' is distinct from 'null'::jsonb
    or (v_result->'company'->>'id')::bigint is distinct from v_company then
    raise exception 'Unsynced company must return its name, an empty catalogue and no link';
  end if;
  begin
    perform public.sync_vikin_ledgers(v_company, '[]'::jsonb);
    raise exception 'Link ID permission must not confer master-admin catalogue sync permission';
  exception when insufficient_privilege then null; end;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin)::text, true);
  perform public.sync_vikin_ledgers(v_company,
    '[{"ledger_name":"Employee account","ledger_code":"EP1","account_group_name":"Salary Payable"},
      {"ledger_name":"Other account","ledger_code":"EP2","account_group_name":"Salary Payable"}]');
  perform public.sync_vikin_ledgers(v_company_two,
    '[{"ledger_name":"Other company employee","ledger_code":"EP1","account_group_name":"Salary Payable"}]');
  select id into strict v_ledger from public.vikin_ledgers where company_id = v_company and ledger_code = 'EP1';
  select id into strict v_second_ledger from public.vikin_ledgers where company_id = v_company and ledger_code = 'EP2';
  select id into strict v_foreign_ledger from public.vikin_ledgers where company_id = v_company_two and ledger_code = 'EP1';
  v_result := public.get_vikin_employee_link_context(v_employee);
  if jsonb_array_length(v_result->'ledgers') <> 2 then
    raise exception 'Master admin may read the same scoped employee context';
  end if;

  -- Exercise the narrow RPCs as authenticated, with the normal Aqura metadata mapping.
  perform set_config('request.jwt.claims', jsonb_build_object('sub', gen_random_uuid(),
    'user_metadata', jsonb_build_object('aqura_user_id', v_actor))::text, true);
  set local role authenticated;
  if exists (select 1 from public.vikin_ledgers where company_id = v_company) then
    raise exception 'Link ID permission must not widen direct catalogue RLS';
  end if;
  begin
    perform count(*) from public.vikin_employee_ledger_links;
    raise exception 'Direct mapping reads must be denied';
  exception when insufficient_privilege then null; end;
  v_result := public.get_vikin_employee_link_context(v_employee);
  if jsonb_array_length(v_result->'ledgers') <> 2
    or exists (select 1 from jsonb_array_elements(v_result->'ledgers') l where (l->>'id')::uuid = v_foreign_ledger) then
    raise exception 'Only the employee sponsor company catalogue may be exposed';
  end if;
  begin
    perform public.set_vikin_employee_ledger_link(v_employee, v_foreign_ledger);
    raise exception 'Expected cross-company ledger rejection';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.set_vikin_employee_ledger_link(v_employee, gen_random_uuid());
    raise exception 'Expected missing ledger rejection';
  exception when invalid_parameter_value then null; end;
  v_result := public.set_vikin_employee_ledger_link(v_employee, v_ledger);
  if (v_result->'link'->>'ledger_id')::uuid is distinct from v_ledger then
    raise exception 'Inactive target employee must be linkable by the active authorized caller';
  end if;
  reset role;

  select * into strict v_before from public.vikin_employee_ledger_links where employee_id = v_employee;
  v_result := public.set_vikin_employee_ledger_link(v_employee, v_ledger);
  select * into strict v_after from public.vikin_employee_ledger_links where employee_id = v_employee;
  if v_after.updated_at <> v_before.updated_at or v_after.created_at <> v_before.created_at
    or v_after.created_by <> v_actor or v_after.updated_by <> v_actor then
    raise exception 'Repeat mapping must retain its timestamps and record the correct actor';
  end if;
  v_result := public.set_vikin_employee_ledger_link(v_employee, v_second_ledger);
  select * into strict v_after from public.vikin_employee_ledger_links where employee_id = v_employee;
  if v_after.vikin_ledger_id <> v_second_ledger or v_after.updated_at <= v_before.updated_at
    or v_after.created_at <> v_before.created_at
    or (select count(*) from public.vikin_employee_ledger_links where employee_id = v_employee) <> 1 then
    raise exception 'Relinking must replace the single current mapping';
  end if;
  begin
    update public.vikin_employee_ledger_links set vikin_ledger_id = v_foreign_ledger where employee_id = v_employee;
    raise exception 'Composite foreign key must prevent cross-company mappings even for privileged writes';
  exception when foreign_key_violation then null; end;

  -- A code-based catalogue rename keeps the mapping UUID and reads the fresh name/group.
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin)::text, true);
  perform public.sync_vikin_ledgers(v_company,
    '[{"ledger_name":"Renamed employee account","ledger_code":"EP2","account_group_name":"Updated group"}]');
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor)::text, true);
  v_result := public.get_vikin_employee_link_context(v_employee);
  if (v_result->'link'->>'ledger_id')::uuid is distinct from v_second_ledger
    or v_result->'link'->>'ledger_name' is distinct from 'Renamed employee account'
    or v_result->'link'->>'account_group_name' is distinct from 'Updated group' then
    raise exception 'Catalogue updates must preserve links and display current names/groups';
  end if;

  update public.hr_employee_master set sponsor_id = v_company_two where id = v_employee;
  v_result := public.get_vikin_employee_link_context(v_employee);
  if v_result->'link' is distinct from 'null'::jsonb or jsonb_array_length(v_result->'ledgers') <> 1 then
    raise exception 'Sponsor changes must hide stale mappings and switch the catalogue';
  end if;
  begin
    perform public.set_vikin_employee_ledger_link(v_employee, v_second_ledger);
    raise exception 'Expected stale sponsor company ledger rejection';
  exception when invalid_parameter_value then null; end;
  v_result := public.set_vikin_employee_ledger_link(v_employee, v_foreign_ledger);
  if (v_result->'link'->>'company_id')::bigint is distinct from v_company_two then
    raise exception 'Changed sponsor must be linkable to its own catalogue';
  end if;
  v_result := public.set_vikin_employee_ledger_link(v_employee, null);
  if v_result->'link' is distinct from 'null'::jsonb
    or exists (select 1 from public.vikin_employee_ledger_links where employee_id = v_employee) then
    raise exception 'Unlink must remove only the Vikin mapping';
  end if;
  if (select erp_employee_id_mapping from public.hr_employee_master where id = v_employee) <> v_polosys then
    raise exception 'Vikin linking must never alter existing Polosys employee mappings';
  end if;
  update public.hr_employee_master set sponsor_id = v_polosys_company where id = v_employee;
  begin
    perform public.get_vikin_employee_link_context(v_employee);
    raise exception 'Expected non-Vikin employee context rejection';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.set_vikin_employee_ledger_link(v_employee, v_foreign_ledger);
    raise exception 'Expected non-Vikin employee link rejection';
  exception when invalid_parameter_value then null; end;
  update public.hr_employee_master set sponsor_id = null where id = v_employee;
  begin
    perform public.get_vikin_employee_link_context(v_employee);
    raise exception 'Expected unsponsored employee context rejection';
  exception when invalid_parameter_value then null; end;
  update public.hr_employee_master set sponsor_id = v_company, is_removed = true where id = v_employee;
  begin
    perform public.get_vikin_employee_link_context(v_employee);
    raise exception 'Expected removed employee read rejection';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.set_vikin_employee_ledger_link(v_employee, v_ledger);
    raise exception 'Expected removed employee link rejection';
  exception when invalid_parameter_value then null; end;
  update public.users set status = 'inactive' where id = v_actor;
  begin
    perform public.get_vikin_employee_link_context(v_employee);
    raise exception 'Expected inactive caller rejection';
  exception when insufficient_privilege then null; end;

  raise notice 'Vikin employee link authorization, company scope, stable IDs, relinking, unlinking, RLS and Polosys isolation checks passed';
end;
$$;

rollback;
