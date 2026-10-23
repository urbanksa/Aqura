-- Run with an administrative database connection. No companies or ledgers survive.
begin;
do $$
declare
  v_actor uuid;
  v_other_actor uuid;
  v_company bigint;
  v_company_two bigint;
  v_polosys_company bigint;
  v_fixture text := 'Vikin sync test ' || gen_random_uuid()::text;
  v_batch jsonb := '[{"ledger_name":" Murshid ","ledger_code":" EP16 ","account_group_name":" Salary Payable "},{"ledger_name":"Other income","ledger_code":"AL97","account_group_name":"Income"}]';
  v_result jsonb;
  v_before public.vikin_ledgers%rowtype;
  v_after public.vikin_ledgers%rowtype;
  v_invalid jsonb;
begin
  if has_function_privilege('anon', 'public.sync_vikin_ledgers(bigint,jsonb)', 'execute')
    or has_function_privilege('anon', 'public.list_vikin_ledger_companies()', 'execute') then
    raise exception 'Anonymous Vikin sync/company-list access must be denied';
  end if;
  if has_table_privilege('authenticated', 'public.vikin_ledgers', 'insert,update,delete') then
    raise exception 'Clients must not bypass the validated sync RPC';
  end if;
  perform set_config('request.jwt.claims', '{}', true);
  begin
    perform public.list_vikin_ledger_companies();
    raise exception 'Expected unauthenticated company-list rejection';
  exception when insufficient_privilege then null; end;
  begin
    perform public.sync_vikin_ledgers(null, v_batch);
    raise exception 'Expected unauthenticated sync rejection';
  exception when insufficient_privilege then null; end;

  select id into strict v_actor from public.users where status = 'active' and is_master_admin = true limit 1;
  select id into strict v_other_actor from public.users where status = 'active' and not coalesce(is_master_admin, false) limit 1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_other_actor)::text, true);
  begin
    perform public.list_vikin_ledger_companies();
    raise exception 'Expected non-admin company-list rejection';
  exception when insufficient_privilege then null; end;
  begin
    perform public.sync_vikin_ledgers(null, v_batch);
    raise exception 'Expected non-admin sync rejection';
  exception when insufficient_privilege then null; end;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor)::text, true);
  insert into public.company_master(name_ar, name_en, erp_provider)
  values (v_fixture, v_fixture, 'vikin') returning id into v_company;
  insert into public.company_master(name_ar, name_en, erp_provider)
  values (v_fixture || ' second', v_fixture || ' second', 'vikin') returning id into v_company_two;
  insert into public.company_master(name_ar, name_en, erp_provider)
  values (v_fixture || ' Polosys', v_fixture || ' Polosys', 'polosys') returning id into v_polosys_company;
  v_result := public.list_vikin_ledger_companies();
  if not exists (select 1 from jsonb_array_elements(v_result) c where (c->>'id')::bigint = v_company)
    or exists (select 1 from jsonb_array_elements(v_result) c where (c->>'id')::bigint = v_polosys_company) then
    raise exception 'Only Vikin companies must be selectable';
  end if;
  begin
    perform public.sync_vikin_ledgers(v_polosys_company, v_batch);
    raise exception 'Expected non-Vikin company rejection';
  exception when invalid_parameter_value then null; end;

  v_result := public.sync_vikin_ledgers(v_company, v_batch);
  if v_result <> jsonb_build_object('company_id', v_company, 'inserted', 2, 'updated', 0, 'unchanged', 0, 'total', 2) then
    raise exception 'Initial sync must insert the whole batch: %', v_result;
  end if;
  select * into strict v_before from public.vikin_ledgers where company_id = v_company and ledger_code = 'EP16';
  if v_before.ledger_name <> 'Murshid' or v_before.account_group_name <> 'Salary Payable'
    or v_before.created_by <> v_actor or v_before.updated_by <> v_actor then
    raise exception 'Ledger text must be trimmed and audit actor recorded';
  end if;

  v_result := public.sync_vikin_ledgers(v_company, v_batch);
  select * into strict v_after from public.vikin_ledgers where company_id = v_company and ledger_code = 'EP16';
  if (v_result->>'inserted')::integer <> 0 or (v_result->>'updated')::integer <> 0 or (v_result->>'unchanged')::integer <> 2
    or v_after.id <> v_before.id or v_after.updated_at <> v_before.updated_at
    or v_after.created_at <> v_before.created_at or v_after.last_synced_at < v_before.last_synced_at then
    raise exception 'Repeat sync must be idempotent and retain stable IDs/change timestamps';
  end if;

  v_result := public.sync_vikin_ledgers(v_company,
    '[{"ledger_name":"Murshid renamed","ledger_code":"EP16","account_group_name":"New salary group"},{"ledger_name":"Bank","ledger_code":"BANK1","account_group_name":"Bank Accounts"}]');
  select * into strict v_after from public.vikin_ledgers where company_id = v_company and ledger_code = 'EP16';
  if (v_result->>'inserted')::integer <> 1 or (v_result->>'updated')::integer <> 1 or (v_result->>'unchanged')::integer <> 0
    or v_after.id <> v_before.id or v_after.ledger_name <> 'Murshid renamed' or v_after.account_group_name <> 'New salary group'
    or v_after.created_at <> v_before.created_at or v_after.updated_at <= v_before.updated_at then
    raise exception 'Existing code must update name/group in place and new codes must insert';
  end if;
  if not exists (select 1 from public.vikin_ledgers where company_id = v_company and ledger_code = 'AL97') then
    raise exception 'Sync must retain codes absent from the latest batch';
  end if;
  v_result := public.sync_vikin_ledgers(v_company_two, v_batch);
  if (v_result->>'inserted')::integer <> 2 or
    (select id from public.vikin_ledgers where company_id = v_company_two and ledger_code = 'EP16') = v_before.id then
    raise exception 'The same code in another company must be a separate ledger';
  end if;
  v_result := public.sync_vikin_ledgers(v_company,
    '[{"ledger_name":"Case-distinct code","ledger_code":"ep16","account_group_name":"Salary Payable"}]');
  if (v_result->>'inserted')::integer <> 1 then raise exception 'Code comparison must preserve case'; end if;

  for v_invalid in select value from jsonb_array_elements('[
    null, {}, [], [null], ["not a ledger"],
    [{"ledger_name":"Name","ledger_code":"C1"}],
    [{"ledger_name":"Name","ledger_code":16,"account_group_name":"Group"}],
    [{"ledger_name":"Name","ledger_code":"C1","account_group_name":"Group","balance":1}],
    [{"ledger_name":"Name","ledger_code":" ","account_group_name":"Group"}],
    [{"ledger_name":"Name","ledger_code":"DUP","account_group_name":"Group"},{"ledger_name":"Duplicate","ledger_code":" DUP ","account_group_name":"Group"}]
  ]') loop
    begin
      perform public.sync_vikin_ledgers(v_company, v_invalid);
      raise exception 'Expected malformed or duplicate ledger batch rejection: %', v_invalid;
    exception when invalid_parameter_value then null; end;
  end loop;
  begin
    perform public.sync_vikin_ledgers(v_company, jsonb_build_array(jsonb_build_object(
      'ledger_name', repeat('x', 501), 'ledger_code', 'LONG', 'account_group_name', 'Group')));
    raise exception 'Expected overlength field rejection';
  exception when invalid_parameter_value then null; end;
  if exists (select 1 from public.vikin_ledgers where company_id = v_company and ledger_code in ('C1', 'DUP', 'LONG')) then
    raise exception 'Rejected batches must leave no partial inserts';
  end if;

  -- Test policy behavior as a real authenticated role, rather than the owner.
  set local role authenticated;
  if not exists (select 1 from public.vikin_ledgers where company_id = v_company) then
    raise exception 'Authenticated active master admin should read the catalogue';
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_other_actor)::text, true);
  if exists (select 1 from public.vikin_ledgers where company_id = v_company) then
    raise exception 'Non-admin catalogue reads must be hidden by RLS';
  end if;
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor)::text, true);
  update public.users set status = 'inactive' where id = v_actor;
  begin
    perform public.sync_vikin_ledgers(v_company, v_batch);
    raise exception 'Expected inactive master admin rejection';
  exception when insufficient_privilege then null; end;

  raise notice 'Vikin ledger sync auth, validation, stable-ID upsert, counts, company scope, RLS and retention checks passed';
end;
$$;
rollback;
