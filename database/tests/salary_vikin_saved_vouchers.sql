-- Run after 20261023_salary_vikin_saved_vouchers.sql.
-- Uses temporary statement/company/employee fixtures; every change rolls back.
begin;
do $$
declare
  v_actor uuid;
  v_branches bigint[];
  v_assignees uuid[];
  v_company bigint;
  v_company_two bigint;
  v_statement uuid;
  v_prefix text := 'VG_' || replace(gen_random_uuid()::text, '-', '');
  v_employee_ids text[];
  v_users uuid[] := '{}';
  v_user uuid;
  v_ledger uuid;
  v_legacy uuid;
  v_task public.assistant_workflow_tasks%rowtype;
  v_reversal public.assistant_workflow_tasks%rowtype;
  v_bad_payload jsonb;
  v_line jsonb;
  v_result jsonb;
  v_again jsonb;
  v_entries jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_payload jsonb;
  v_old_assignee uuid;
  v_count integer;
  v_category text; v_group record; v_vouchers jsonb:='[]'::jsonb; v_all jsonb; v_lines jsonb;
  v_ids jsonb; v_employee_entries jsonb; v_amount numeric; v_narration text; v_branch_name text;
  v_emp_ledger public.vikin_ledgers%rowtype; v_other public.vikin_ledgers%rowtype;
  v_bank uuid; v_bundle jsonb; v_plain jsonb; v_plain_lines jsonb; v_batch uuid; v_legacy_statement uuid;
  v_legacy_batch uuid; v_plain_id uuid; v_before jsonb; v_before_task jsonb; v_empty_statement uuid; v_empty_batch uuid;
  v_date date; v_task_id uuid;
  i integer;
begin
  if has_function_privilege('anon', 'public.get_salary_vikin_adjustment_test_tasks(uuid)', 'execute')
    or has_function_privilege('anon', 'public.post_salary_vikin_adjustment_test_tasks(uuid,jsonb)', 'execute') then
    raise exception 'Anonymous Vikin test-task RPC access must be denied';
  end if;
  perform set_config('request.jwt.claims', '{}', true);
  begin
    perform public.get_salary_vikin_adjustment_test_tasks(gen_random_uuid());
    raise exception 'Expected unauthenticated read rejection';
  exception when insufficient_privilege then null; end;
  begin
    perform public.post_salary_vikin_adjustment_test_tasks(gen_random_uuid(), '[]');
    raise exception 'Expected unauthenticated write rejection';
  exception when insufficient_privilege then null; end;
  select id into strict v_actor from public.users where status = 'active' and is_master_admin limit 1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor)::text, true);

  select array_agg(branch_id order by branch_id), array_agg(entry_task_user_id order by branch_id)
    into v_branches, v_assignees from (
      select d.branch_id, d.entry_task_user_id from public.branch_default_positions d
      join public.users u on u.id = d.entry_task_user_id and u.status = 'active'
      where exists(select 1 from public.hr_employee_master e where e.user_id = u.id
        and e.current_branch_id = d.branch_id and not e.is_removed)
      order by d.branch_id limit 2) configured;
  if coalesce(cardinality(v_branches), 0) <> 2 then
    raise exception 'This rollback test requires two branches with active Entry Task assignees';
  end if;
  insert into public.company_master(name_en, name_ar, erp_provider)
    values(v_prefix, v_prefix, 'vikin') returning id into v_company;
  insert into public.company_master(name_en, name_ar, erp_provider)
    values(v_prefix || '_TWO', v_prefix || '_TWO', 'vikin') returning id into v_company_two;
  perform public.sync_vikin_ledgers(v_company,
    '[{"ledger_name":"Branch one adjustment","ledger_code":"AL1","account_group_name":"Branch Payable"},
      {"ledger_name":"Branch two adjustment","ledger_code":"AL2","account_group_name":"Branch Payable"},
      {"ledger_name":"Employee one","ledger_code":"EP1","account_group_name":"Salary Payable"},
      {"ledger_name":"Employee two","ledger_code":"EP2","account_group_name":"Salary Payable"},
      {"ledger_name":"Employee three","ledger_code":"EP3","account_group_name":"Salary Payable"}]');
  perform public.sync_vikin_ledgers(v_company_two,
    '[{"ledger_name":"Other company adjustment","ledger_code":"AL1","account_group_name":"Branch Payable"},
      {"ledger_name":"Employee four","ledger_code":"EP4","account_group_name":"Salary Payable"}]');
  for i in 1..4 loop
    insert into public.users(username, password_hash, salt, quick_access_code, quick_access_salt, user_type)
      values(v_prefix || '_' || i, 'test-only', 'test-only', gen_random_uuid()::text, 'test-only', 'global')
      returning id into v_user;
    v_users := array_append(v_users, v_user);
    v_employee_ids := array_append(v_employee_ids, v_prefix || '_' || i);
    insert into public.hr_employee_master(id, user_id, current_branch_id, name_en, sponsor_id)
      values(v_employee_ids[i], v_user, case when i = 3 then v_branches[2] else v_branches[1] end,
        'Test employee ' || i, case when i = 4 then v_company_two else v_company end);
    select id into strict v_ledger from public.vikin_ledgers
      where company_id = case when i = 4 then v_company_two else v_company end and ledger_code = 'EP' || i;
    insert into public.vikin_employee_ledger_links(employee_id, company_id, vikin_ledger_id, created_by, updated_by)
      values(v_employee_ids[i], case when i = 4 then v_company_two else v_company end, v_ledger, v_actor, v_actor);
    v_rows := v_rows || jsonb_build_array(jsonb_build_object('employeeId', v_employee_ids[i],
      'currentBranchId', case when i = 3 then v_branches[2] else v_branches[1] end));
  end loop;
  insert into public.salary_vikin_branch_adjustment_accounts(company_id, branch_id, ledger_id, updated_by)
    select v_company, v_branches[1], id, v_actor from public.vikin_ledgers where company_id = v_company and ledger_code = 'AL1';
  insert into public.salary_vikin_branch_adjustment_accounts(company_id, branch_id, ledger_id, updated_by)
    select v_company, v_branches[2], id, v_actor from public.vikin_ledgers where company_id = v_company and ledger_code = 'AL2';
  insert into public.salary_vikin_branch_adjustment_accounts(company_id, branch_id, ledger_id, updated_by)
    select v_company_two, v_branches[1], id, v_actor from public.vikin_ledgers where company_id = v_company_two and ledger_code = 'AL1';
  insert into public.hr_salary_statements(statement_name, start_date, end_date, data_json, created_by)
    values(v_prefix, '2026-08-25', '2026-09-24', jsonb_build_object('analysisData', v_rows), v_actor) returning id into v_statement;

  -- Add a salary bank in each company; the employee work branches remain the
  -- existing Polosys branches, independent from their Vikin sponsor company.
  perform public.sync_vikin_ledgers(v_company,
    '[{"ledger_name":"Company one salary bank","ledger_code":"BK1","account_group_name":"Banks"}]');
  perform public.sync_vikin_ledgers(v_company_two,
    '[{"ledger_name":"Company two salary bank","ledger_code":"BK1","account_group_name":"Banks"}]');
  insert into public.salary_vikin_bank_accounts(company_id,ledger_id,updated_by)
    select company_id,id,v_actor from public.vikin_ledgers where company_id in(v_company,v_company_two) and ledger_code='BK1';
  for v_group in select distinct branch_id,company_id from (values
    (v_branches[1],v_company),(v_branches[2],v_company),(v_branches[1],v_company_two)) g(branch_id,company_id)
    order by branch_id,company_id loop
    select coalesce(name_en,name_ar) into v_branch_name from public.branches where id=v_group.branch_id;
    foreach v_category in array array['adjustmentsVikin','bankVikin'] loop
      v_lines:='[]'; v_ids:='[]'; v_employee_entries:='[]';
      for i in 1..4 loop
        if (case when i=3 then v_branches[2] else v_branches[1] end)<>v_group.branch_id
          or (case when i=4 then v_company_two else v_company end)<>v_group.company_id then continue; end if;
        v_amount:=(array[100.50,200.25,300.00,400.00])[i];
        select * into strict v_emp_ledger from public.vikin_ledgers where company_id=v_group.company_id and ledger_code='EP'||i;
        select l.* into strict v_other from public.vikin_ledgers l where l.company_id=v_group.company_id
          and l.ledger_code=(case when v_category='bankVikin' then 'BK1' when v_group.branch_id=v_branches[1] then 'AL1' else 'AL2' end);
        v_narration:='Salary '||(case when v_category='adjustmentsVikin' then 'branch adjustment' else 'bank payment' end)
          ||' 2026-08-25 to 2026-09-24 | '||v_employee_ids[i]||' - Test employee '||i||' | '||v_branch_name;
        v_lines:=v_lines||jsonb_build_array(
          jsonb_build_object('ledger_name',(case when v_category='adjustmentsVikin' then v_other.ledger_name else v_emp_ledger.ledger_name end),
            'ledger_code',(case when v_category='adjustmentsVikin' then v_other.ledger_code else v_emp_ledger.ledger_code end),
            'amount',to_char(v_amount,'FM9999999999999990.00'),'side','Debit','narration',v_narration),
          jsonb_build_object('ledger_name',(case when v_category='adjustmentsVikin' then v_emp_ledger.ledger_name else v_other.ledger_name end),
            'ledger_code',(case when v_category='adjustmentsVikin' then v_emp_ledger.ledger_code else v_other.ledger_code end),
            'amount',to_char(v_amount,'FM9999999999999990.00'),'side','Credit','narration',v_narration));
        v_ids:=v_ids||jsonb_build_array(v_employee_ids[i]);
        v_employee_entries:=v_employee_entries||jsonb_build_array(jsonb_build_object('employee_id',v_employee_ids[i],'amount',v_amount));
      end loop;
      v_vouchers:=v_vouchers||jsonb_build_array(jsonb_build_object('category',v_category,'voucher_type','JV',
        'branch_id',v_group.branch_id,'company_id',v_group.company_id,'company_name','Untrusted client name',
        'employee_id','','employee_ids',v_ids,'employee_entries',v_employee_entries,'lines',v_lines));
    end loop;
  end loop;
  v_plain_lines:=jsonb_build_array(jsonb_build_object('ledger_name','Test debit','ledger_code','1','amount','100.00','side','Debit','narration','Temporary salary booking'),
    jsonb_build_object('ledger_name','Test credit','ledger_code','2','amount','100.00','side','Credit','narration','Temporary salary booking'));
  v_plain:=jsonb_build_object('category','booking','branch_id',v_branches[1],'lines',v_plain_lines);
  v_all:=v_vouchers||jsonb_build_array(v_plain);
  if has_function_privilege('authenticated','public.validate_salary_vikin_voucher(uuid,jsonb)','execute') then
    raise exception 'Internal Vikin validation helper must not be callable directly by clients';
  end if;
  begin
    perform public.post_salary_vikin_adjustment_test_tasks(v_statement,'[]');
    raise exception 'Expected deprecated unsaved-task endpoint rejection';
  exception when raise_exception then if sqlerrm<>'Save salary entries first, then use Post Task for the saved Vikin category.' then raise; end if; end;
  begin
    perform public.save_salary_entries(v_statement,jsonb_set(v_all,'{0,company_id}','-1'));
    raise exception 'Expected missing Vikin sponsor rejection';
  exception when raise_exception then if sqlerrm<>'Select the employee sponsor company linked to Vikin.' then raise; end if; end;
  begin
    perform public.save_salary_entries(v_statement,jsonb_set(v_all,'{0,lines,0,ledger_code}','"WRONG"'));
    raise exception 'Expected stale/incorrect linked ledger rejection';
  exception when raise_exception then if sqlerrm<>'Vikin employee ledger pairs must use the current linked ledgers, sides and Net Bank amounts.' then raise; end if; end;
  begin
    perform public.save_salary_entries(v_statement,jsonb_set(v_all,'{0,employee_entries,0,amount}','"0.00"'));
    raise exception 'Expected invalid employee amount rejection';
  exception when raise_exception then if sqlerrm<>'Each Vikin employee entry requires a positive Net Bank amount.' then raise; end if; end;
  begin
    perform public.save_salary_entries(v_statement,jsonb_set(v_all,'{0,employee_ids}','[]'));
    raise exception 'Expected metadata/line employee correspondence rejection';
  exception when raise_exception then if sqlerrm<>'Vikin voucher employee IDs must match its unique ordered employee entries.' then raise; end if; end;
  begin
    perform public.save_salary_entries(v_statement,v_all||jsonb_build_array(v_all->0));
    raise exception 'Expected duplicate branch/company category rejection';
  exception when unique_violation then null; end;
  select ledger_id into strict v_bank from public.salary_vikin_bank_accounts where company_id=v_company;
  delete from public.salary_vikin_bank_accounts where company_id=v_company;
  begin
    perform public.save_salary_entries(v_statement,v_all);
    raise exception 'Expected missing company salary bank rejection';
  exception when raise_exception then if sqlerrm<>'Link the Vikin company salary bank ledger before saving.' then raise; end if; end;
  insert into public.salary_vikin_bank_accounts(company_id,ledger_id,updated_by) values(v_company,v_bank,v_actor);
  if exists(select 1 from public.salary_entry_batches where statement_id=v_statement) then
    raise exception 'Any invalid Save All request must roll back its entire batch';
  end if;
  v_bundle:=public.save_salary_entries(v_statement,v_all);
  v_batch:=(v_bundle->>'id')::uuid;
  if v_bundle->>'vikin_entries_saved'<>'true' or jsonb_array_length(v_bundle->'vouchers')<>7
    or (select count(*) from public.salary_entry_vouchers where batch_id=v_batch and voucher_type='JV')<>6 then
    raise exception 'Save All must lock six grouped Vikin JVs plus the unchanged Polosys voucher';
  end if;
  if exists(select 1 from public.salary_entry_vouchers where batch_id=v_batch and company_id is not null
    and (company_name='Untrusted client name' or employee_ids='[]' or employee_entries='[]'
      or (category='bankVikin' and voucher_date is not null)
      or (category='adjustmentsVikin' and voucher_date is distinct from '2026-09-24'::date))) then
    raise exception 'Save must use authoritative company metadata, employee pairs and category dates';
  end if;
  if exists(select 1 from public.assistant_workflow_tasks where payload->>'salary_statement_id'=v_statement::text) then
    raise exception 'Save All must not create posting tasks';
  end if;
  begin
    perform public.save_salary_entries(v_statement,v_all);
    raise exception 'Expected locked repeat Save All rejection';
  exception when raise_exception then if sqlerrm<>'Salary entries are already saved and locked.' then raise; end if; end;
  foreach v_category in array array['adjustmentsVikin','bankVikin','booking'] loop
    perform public.post_salary_entry_tasks(v_batch,v_category);
    perform public.post_salary_entry_tasks(v_batch,v_category);
  end loop;
  if (select count(*) from public.assistant_workflow_tasks where payload->>'salary_statement_id'=v_statement::text)<>7
    or (select count(*) from public.assistant_workflow_tasks where payload->>'salary_statement_id'=v_statement::text and task_type='salary_vikin_saved_jv')<>6
    or exists(select 1 from public.assistant_workflow_tasks where payload->>'salary_statement_id'=v_statement::text
      and (payload->>'entry_kind'='reversal' or payload ? 'depends_on_task_id')) then
    raise exception 'Post Task must create one original per frozen group/category, never duplicates or reversals';
  end if;
  for v_task in select * from public.assistant_workflow_tasks
    where payload->>'salary_statement_id'=v_statement::text and task_type='salary_vikin_saved_jv' loop
    select voucher_date into strict v_date from public.salary_entry_vouchers where task_id=v_task.id;
    if v_task.payload->>'version'<>'4' or v_task.payload->>'test_mode'<>'false' or v_task.payload->>'save_enabled'<>'true'
      or v_task.payload->>'salary_entry_voucher_id'<>v_task.source_record_id::text
      or v_task.payload->>'posting_date'<>v_date::text
      or v_date is distinct from (case when v_task.payload->>'salary_category'='bankVikin' then (now() at time zone 'Asia/Riyadh')::date else '2026-09-24'::date end)
      or v_task.payload->>'entry_kind'<>(case when v_task.payload->>'salary_category'='bankVikin' then 'bank_payment' else 'adjustment' end)
      or not exists(select 1 from public.branch_default_positions d where d.branch_id=v_task.branch_id and d.entry_task_user_id=v_task.assigned_to) then
      raise exception 'Vikin task version, identity, entry kind, branch assignee or frozen category date is wrong';
    end if;
  end loop;
  select id into strict v_task_id from public.assistant_workflow_tasks where payload->>'salary_statement_id'=v_statement::text
    and task_type='salary_vikin_saved_jv' order by id limit 1;
  update public.assistant_workflow_tasks set status='completed' where id=v_task_id;
  begin
    update public.assistant_workflow_tasks set status='pending' where id=v_task_id;
    raise exception 'Expected completed saved-task lock';
  exception when raise_exception then if sqlerrm<>'Salary posting tasks are locked.' then raise; end if; end;

  -- Recreate an old Polosys-only batch and posted voucher, then append only the
  -- Vikin supplement. No old voucher or posting-task row may change.
  insert into public.hr_salary_statements(statement_name,start_date,end_date,data_json,created_by)
    values(v_prefix||'_legacy','2026-08-25','2026-09-24',jsonb_build_object('analysisData',v_rows),v_actor) returning id into v_legacy_statement;
  insert into public.salary_entry_batches(statement_id,statement_end_date,source_snapshot_hash,created_by)
    select id,end_date,md5(data_json::text),v_actor from public.hr_salary_statements where id=v_legacy_statement returning id into v_legacy_batch;
  insert into public.salary_entry_vouchers(batch_id,category,branch_id,branch_name,voucher_type,lines,debit_total,credit_total,voucher_date)
    select v_legacy_batch,'booking',v_branches[1],name_en,'MJV',v_plain_lines,100,100,'2026-09-24' from public.branches where id=v_branches[1]
    returning id into v_plain_id;
  perform public.post_salary_entry_tasks(v_legacy_batch,'booking');
  update public.assistant_workflow_tasks set status='completed' where id=(select task_id from public.salary_entry_vouchers where id=v_plain_id);
  select to_jsonb(v) into v_before from public.salary_entry_vouchers v where id=v_plain_id;
  select to_jsonb(t) into v_before_task from public.assistant_workflow_tasks t where id=(v_before->>'task_id')::uuid;
  begin
    perform public.save_salary_entries(v_legacy_statement,v_all);
    raise exception 'Expected append-only Vikin scope rejection';
  exception when raise_exception then if sqlerrm<>'Only Vikin entries may be appended to an existing saved salary batch.' then raise; end if; end;
  v_bundle:=public.save_salary_entries(v_legacy_statement,v_vouchers);
  if v_bundle->>'vikin_entries_saved'<>'true' or jsonb_array_length(v_bundle->'vouchers')<>7
    or (select to_jsonb(v) from public.salary_entry_vouchers v where id=v_plain_id) is distinct from v_before
    or (select to_jsonb(t) from public.assistant_workflow_tasks t where id=(v_before->>'task_id')::uuid) is distinct from v_before_task then
    raise exception 'Legacy append must lock Vikin while preserving all frozen Polosys voucher/task data';
  end if;
  begin
    perform public.save_salary_entries(v_legacy_statement,v_vouchers);
    raise exception 'Expected repeat legacy Vikin append lock';
  exception when raise_exception then if sqlerrm<>'Salary entries are already saved and locked.' then raise; end if; end;
  insert into public.hr_salary_statements(statement_name,start_date,end_date,data_json,created_by)
    values(v_prefix||'_empty','2026-08-25','2026-09-24','{"analysisData":[]}',v_actor) returning id into v_empty_statement;
  insert into public.salary_entry_batches(statement_id,statement_end_date,source_snapshot_hash,created_by)
    select id,end_date,'wrong-snapshot',v_actor from public.hr_salary_statements where id=v_empty_statement returning id into v_empty_batch;
  begin
    perform public.save_salary_entries(v_empty_statement,'[]');
    raise exception 'Expected frozen snapshot mismatch rejection';
  exception when raise_exception then if sqlerrm<>'The statement changed after saving; Vikin entries cannot be appended to a different snapshot.' then raise; end if; end;
  -- A separate matching legacy snapshot may close an empty Vikin supplement.
  insert into public.hr_salary_statements(statement_name,start_date,end_date,data_json,created_by)
    values(v_prefix||'_empty_ok','2026-08-25','2026-09-24','{"analysisData":[]}',v_actor) returning id into v_empty_statement;
  insert into public.salary_entry_batches(statement_id,statement_end_date,source_snapshot_hash,created_by)
    select id,end_date,md5(data_json::text),v_actor from public.hr_salary_statements where id=v_empty_statement returning id into v_empty_batch;
  v_bundle:=public.save_salary_entries(v_empty_statement,'[]');
  if v_bundle->>'vikin_entries_saved'<>'true' or jsonb_array_length(v_bundle->'vouchers')<>0 then
    raise exception 'A legacy empty Vikin supplement must close exactly once without generating vouchers';
  end if;
  begin
    perform public.save_salary_entries(v_empty_statement,'[]');
    raise exception 'Expected empty supplement repeat lock';
  exception when raise_exception then if sqlerrm<>'Salary entries are already saved and locked.' then raise; end if; end;
  raise notice 'Vikin Save All/current-ledger validation, grouped original-only tasks/dates, atomicity, deduplication and legacy append preservation checks passed';
end;
$$;
rollback;
