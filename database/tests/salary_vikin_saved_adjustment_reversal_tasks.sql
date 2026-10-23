-- Run after 20261023_salary_vikin_saved_adjustment_reversal_tasks.sql.
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
  v_entries := jsonb_build_array(
    jsonb_build_object('employee_id', v_employee_ids[4], 'branch_id', v_branches[1], 'amount', '400.00'),
    jsonb_build_object('employee_id', v_employee_ids[2], 'branch_id', v_branches[1], 'amount', '200.25'),
    jsonb_build_object('employee_id', v_employee_ids[1], 'branch_id', v_branches[1], 'amount', '100.50'),
    jsonb_build_object('employee_id', v_employee_ids[3], 'branch_id', v_branches[2], 'amount', '300.00'));

  begin
    perform public.post_salary_vikin_adjustment_test_tasks(v_statement, '[]');
    raise exception 'Expected empty entries rejection';
  exception when raise_exception then if sqlerrm not like 'Generate the Vikin adjustment entries first%' then raise; end if; end;
  begin
    perform public.post_salary_vikin_adjustment_test_tasks(v_statement,
      (select jsonb_agg(v_entries->0) from generate_series(1, 1001)));
    raise exception 'Expected 2000-line cap';
  exception when raise_exception then if sqlerrm not like 'Generate the Vikin adjustment entries first%' then raise; end if; end;
  begin
    perform public.post_salary_vikin_adjustment_test_tasks(v_statement, v_entries || jsonb_build_array(v_entries->0));
    raise exception 'Expected duplicate employee rejection';
  exception when raise_exception then if sqlerrm <> 'Duplicate employee adjustment entries.' then raise; end if; end;
  begin
    perform public.post_salary_vikin_adjustment_test_tasks(v_statement, jsonb_set(v_entries, '{2,amount}', '"0.00"'));
    raise exception 'Expected invalid Net Bank rejection';
  exception when raise_exception then if sqlerrm <> 'Each Vikin adjustment needs a positive Net Bank amount.' then raise; end if; end;
  begin
    perform public.post_salary_vikin_adjustment_test_tasks(v_statement,
      jsonb_set(v_entries, '{2,branch_id}', to_jsonb(v_branches[2])));
    raise exception 'Expected statement branch membership rejection';
  exception when raise_exception then if sqlerrm not like 'Employee % is not in this statement branch.' then raise; end if; end;
  select entry_task_user_id into v_old_assignee from public.branch_default_positions where branch_id = v_branches[2];
  update public.branch_default_positions set entry_task_user_id = null where branch_id = v_branches[2];
  begin
    perform public.post_salary_vikin_adjustment_test_tasks(v_statement, v_entries);
    raise exception 'Expected missing branch assignee rejection';
  exception when raise_exception then if sqlerrm not like 'No active Entry Task user is configured%' then raise; end if; end;
  update public.branch_default_positions set entry_task_user_id = v_old_assignee where branch_id = v_branches[2];
  if exists(select 1 from public.assistant_workflow_tasks where source_record_id = v_statement) then
    raise exception 'Invalid input must not create a partial task set';
  end if;

  insert into public.assistant_workflow_tasks(task_type, title, branch_id, assigned_to, created_by, source_record_id, workflow_key, payload)
    values('salary_vikin_adjustment_test_jv', 'Legacy rollback fixture', v_branches[1], v_assignees[1], v_actor, v_statement,
      'salary-vikin-adjustment-test:' || v_statement || ':' || v_branches[1] || ':' || v_employee_ids[1],
      jsonb_build_object('version', 1, 'employee_id', v_employee_ids[1], 'test_mode', true, 'save_enabled', false)) returning id into v_legacy;
  begin
    perform public.post_salary_vikin_adjustment_test_tasks(v_statement, v_entries);
    raise exception 'Expected legacy-task cleanup requirement';
  exception when raise_exception then if sqlerrm <> 'Remove the previous no-save Vikin test tasks before creating adjustment and reversal JVs.' then raise; end if; end;
  begin
    update public.assistant_workflow_tasks set status = 'completed' where id = v_legacy;
    raise exception 'Expected legacy no-save completion rejection';
  exception when raise_exception then if sqlerrm <> 'Vikin JV test tasks cannot be completed: final Save is disabled.' then raise; end if; end;
  delete from public.assistant_workflow_tasks where id = v_legacy;

  v_result := public.post_salary_vikin_adjustment_test_tasks(v_statement, v_entries);
  if jsonb_array_length(v_result) <> 6 then raise exception 'Three branch/company groups must produce three original and three reversal tasks'; end if;
  select * into strict v_task from public.assistant_workflow_tasks where source_record_id = v_statement
    and branch_id = v_branches[1] and (payload->>'company_id')::bigint = v_company and payload->>'entry_kind' = 'adjustment';
  v_payload := v_task.payload;
  if v_task.assigned_to <> v_assignees[1] or v_payload->>'version' <> '3'
    or v_payload->>'posting_date' <> '2026-09-24' or v_payload->>'employee_count' <> '2'
    or v_payload->>'line_count' <> '4' or jsonb_array_length(v_payload->'lines') <> 4
    or v_payload->'employee_ids' <> to_jsonb(v_employee_ids[1:2])
    or v_payload->>'test_mode' <> 'false' or v_payload->>'save_enabled' <> 'true'
    or v_payload->>'entry_kind' <> 'adjustment' or v_task.task_type <> 'salary_vikin_adjustment_jv'
    or v_payload ? 'employee_id' then
    raise exception 'Combined original JV metadata, assignee, date or enabled-save flags are wrong';
  end if;
  if v_payload->'lines'->0->>'ledger_code' <> 'AL1' or v_payload->'lines'->1->>'ledger_code' <> 'EP1'
    or v_payload->'lines'->2->>'ledger_code' <> 'AL1' or v_payload->'lines'->3->>'ledger_code' <> 'EP2'
    or v_payload->'lines'->0->>'side' <> 'Debit' or v_payload->'lines'->1->>'side' <> 'Credit'
    or v_payload->'lines'->2->>'amount' <> '200.25'
    or position(v_employee_ids[1] in v_payload->'lines'->0->>'narration') = 0
    or position(v_employee_ids[2] in v_payload->'lines'->2->>'narration') = 0 then
    raise exception 'Each employee debit/credit pair, exact ledger code, amount and narration must be retained in order';
  end if;
  if exists(select 1 from public.assistant_workflow_tasks t where t.source_record_id = v_statement
    and (select sum(case when l->>'side' = 'Debit' then (l->>'amount')::numeric else -(l->>'amount')::numeric end)
      from jsonb_array_elements(t.payload->'lines') l) <> 0) then
    raise exception 'Every combined JV must balance';
  end if;
  if not exists(select 1 from jsonb_array_elements(v_result) t where t->>'id' = v_task.id::text
    and t->'employee_ids' = to_jsonb(v_employee_ids[1:2]) and t->>'employee_count' = '2' and t->>'line_count' = '4') then
    raise exception 'Task-status RPC must expose group membership/counts to the frontend';
  end if;
  -- Exact retry in a different input order returns the same task IDs.
  v_again := public.post_salary_vikin_adjustment_test_tasks(v_statement,
    (select jsonb_agg(value order by ordinality desc) from jsonb_array_elements(v_entries) with ordinality));
  if v_again <> v_result then raise exception 'Retry must be deterministic and idempotent'; end if;
  begin
    perform public.post_salary_vikin_adjustment_test_tasks(v_statement, v_entries - 0);
    raise exception 'Expected partial group-set retry rejection';
  exception when raise_exception then if sqlerrm not like 'Vikin adjustment and reversal tasks already exist%' then raise; end if; end;
  begin
    perform public.post_salary_vikin_adjustment_test_tasks(v_statement, v_entries - 1);
    raise exception 'Expected partial employee retry rejection';
  exception when raise_exception then if sqlerrm not like 'Vikin adjustment and reversal tasks already exist%' then raise; end if; end;
  begin
    perform public.post_salary_vikin_adjustment_test_tasks(v_statement, jsonb_set(v_entries, '{2,amount}', '"101.00"'));
    raise exception 'Expected changed amount retry rejection';
  exception when raise_exception then if sqlerrm not like 'Vikin adjustment and reversal tasks already exist%' then raise; end if; end;
  update public.vikin_ledgers set ledger_name = 'Updated employee one' where company_id = v_company and ledger_code = 'EP1';
  begin
    perform public.post_salary_vikin_adjustment_test_tasks(v_statement, v_entries);
    raise exception 'Expected changed ledger-name retry rejection';
  exception when raise_exception then if sqlerrm not like 'Vikin adjustment and reversal tasks already exist%' then raise; end if; end;
  select * into strict v_reversal from public.assistant_workflow_tasks
    where payload->>'depends_on_task_id' = v_task.id::text and task_type = 'salary_vikin_adjustment_jv';
  if v_reversal.payload->>'entry_kind' <> 'reversal' or v_reversal.branch_id <> v_task.branch_id
    or v_reversal.assigned_to <> v_task.assigned_to or v_reversal.source_record_id <> v_statement
    or v_reversal.payload->>'company_id' <> v_payload->>'company_id'
    or v_reversal.payload->>'posting_date' <> v_payload->>'posting_date'
    or v_reversal.payload->'employee_ids' <> v_payload->'employee_ids'
    or jsonb_array_length(v_reversal.payload->'lines') <> 4 then
    raise exception 'Reversal task must retain its original company, branch, assignee, date and employees';
  end if;
  for i in 0..3 loop
    v_line := v_reversal.payload->'lines'->i;
    if v_line->>'ledger_name' <> v_payload->'lines'->i->>'ledger_name'
      or v_line->>'ledger_code' <> v_payload->'lines'->i->>'ledger_code'
      or v_line->>'amount' <> v_payload->'lines'->i->>'amount'
      or v_line->>'side' <> (case v_payload->'lines'->i->>'side' when 'Debit' then 'Credit' else 'Debit' end)
      or v_line->>'narration' <> 'Reversal | ' || (v_payload->'lines'->i->>'narration') then
      raise exception 'Reversal must swap every side, retain every amount/ledger and prefix each narration';
    end if;
  end loop;
  begin
    update public.assistant_workflow_tasks set status = 'in_progress' where id = v_reversal.id;
    raise exception 'Expected early reversal claim rejection';
  exception when raise_exception then if sqlerrm <> 'Post and save the original Vikin adjustment before posting its reversal.' then raise; end if; end;
  begin
    update public.assistant_workflow_tasks set status = 'completed' where id = v_reversal.id;
    raise exception 'Expected early reversal completion rejection';
  exception when raise_exception then if sqlerrm <> 'Post and save the original Vikin adjustment before posting its reversal.' then raise; end if; end;
  -- A balanced but altered reversal must fail the exact-parent comparison.
  v_bad_payload := jsonb_set(jsonb_set(v_reversal.payload, '{lines,0,amount}', '"101.50"'), '{lines,1,amount}', '"101.50"');
  begin
    insert into public.assistant_workflow_tasks(task_type,title,branch_id,assigned_to,created_by,source_record_id,workflow_key,payload)
      values('salary_vikin_adjustment_jv','Invalid reversal fixture',v_task.branch_id,v_task.assigned_to,v_actor,v_statement,
        'vikin-invalid-reversal:' || gen_random_uuid(),v_bad_payload);
    raise exception 'Expected non-exact reversal rejection';
  exception when raise_exception then if sqlerrm <> 'The Vikin reversal must exactly reverse its original ledgers, amounts, date and narration.' then raise; end if; end;
  v_bad_payload := jsonb_set(v_reversal.payload, '{depends_on_task_id}', to_jsonb(gen_random_uuid()::text));
  begin
    insert into public.assistant_workflow_tasks(task_type,title,branch_id,assigned_to,created_by,source_record_id,workflow_key,payload)
      values('salary_vikin_adjustment_jv','Missing parent fixture',v_task.branch_id,v_task.assigned_to,v_actor,v_statement,
        'vikin-invalid-parent:' || gen_random_uuid(),v_bad_payload);
    raise exception 'Expected missing reversal parent rejection';
  exception when raise_exception then if sqlerrm <> 'The Vikin reversal must reference its matching original adjustment task.' then raise; end if; end;
  begin
    update public.assistant_workflow_tasks set payload = jsonb_set(payload,'{save_enabled}','false') where id = v_task.id;
    raise exception 'Expected original payload lock';
  exception when raise_exception then if sqlerrm <> 'Vikin adjustment and reversal task entries are locked after creation.' then raise; end if; end;
  begin
    delete from public.assistant_workflow_tasks where id = v_task.id;
    raise exception 'Expected pending original dependency lock';
  exception when raise_exception then if sqlerrm <> 'Remove the dependent pending Vikin reversal before removing its original task.' then raise; end if; end;
  -- These are temporary database fixtures only: no browser or ERP is touched.
  update public.assistant_workflow_tasks set status = 'in_progress' where id = v_task.id;
  update public.assistant_workflow_tasks set status = 'completed' where id = v_task.id;
  begin
    update public.assistant_workflow_tasks set status = 'pending' where id = v_task.id;
    raise exception 'Expected completed original status lock';
  exception when raise_exception then if sqlerrm <> 'Posted Vikin JV tasks cannot be reopened.' then raise; end if; end;
  v_again := public.get_salary_vikin_adjustment_test_tasks(v_statement);
  if not exists(select 1 from jsonb_array_elements(v_again) t
    where t->>'id' = v_reversal.id::text and t->>'depends_on_status' = 'completed' and t->>'entry_kind' = 'reversal') then
    raise exception 'Read RPC must expose the completed parent status for reversal posting';
  end if;
  update public.assistant_workflow_tasks set status = 'in_progress' where id = v_reversal.id;
  update public.assistant_workflow_tasks set status = 'completed' where id = v_reversal.id;
  begin
    delete from public.assistant_workflow_tasks where id = v_reversal.id;
    raise exception 'Expected posted reversal deletion lock';
  exception when raise_exception then if sqlerrm <> 'Posted Vikin JVs cannot be deleted; use their reversal task.' then raise; end if; end;
  select count(*) into v_count from public.assistant_workflow_tasks where source_record_id = v_statement;
  if v_count <> 6 then raise exception 'Failed or repeated requests must leave exactly three original/reversal pairs'; end if;
  if (select count(*) from public.assistant_workflow_tasks where source_record_id = v_statement and payload->>'entry_kind' = 'adjustment') <> 3
    or (select count(*) from public.assistant_workflow_tasks where source_record_id = v_statement and payload->>'entry_kind' = 'reversal') <> 3 then
    raise exception 'Every branch/company adjustment must have exactly one reversal task';
  end if;
  if exists(select 1 from public.salary_entry_batches where statement_id = v_statement)
    or exists(select 1 from public.salary_entry_vouchers where task_id = v_task.id) then
    raise exception 'Creating Vikin posting tasks must not itself save financial vouchers';
  end if;
  raise notice 'Vikin original/reversal grouping, isolation, ordering, dates, enabled-save contract, dependency and immutable exact-reversal guards, permissions and retry checks passed';
end;
$$;
rollback;
