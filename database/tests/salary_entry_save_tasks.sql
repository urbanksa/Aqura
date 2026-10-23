begin;
do $$
declare v_actor uuid; v_statement uuid; v_batch jsonb; v_result jsonb; v_payload jsonb; v_lines jsonb; v_cash text;
  v_voucher uuid; v_task uuid; v_count integer; v_date date; v_cp2 uuid; v_assignee uuid;
begin
  perform set_config('request.jwt.claims','{}',true);
  begin
    perform public.get_saved_salary_entries('00000000-0000-0000-0000-000000000000'); raise exception 'Expected permission denial';
  exception when raise_exception then if sqlerrm<>'Salary Statement permission required.' then raise; end if; end;
  if has_function_privilege('anon','public.save_salary_entries(uuid,jsonb)','execute') then raise exception 'Anonymous save access must be denied'; end if;
  select id into strict v_actor from public.users where status='active' and is_master_admin limit 1;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor)::text,true);
  select ledger_name into strict v_cash from public.erp_posting_ledger_links where branch_id=1 and account_key='branch_cash';
  insert into public.hr_salary_statements(statement_name,start_date,end_date,data_json,created_by)
  values('Temporary salary workflow test','2026-08-25','2026-09-24',jsonb_build_object('analysisData',jsonb_build_array(
    jsonb_build_object('employeeId','EMP3','currentBranchId',1),jsonb_build_object('employeeId','EMP4','currentBranchId',1))),v_actor) returning id into v_statement;
  v_lines:=jsonb_build_array(jsonb_build_object('ledger_name','Test debit','ledger_code','1','amount','100.00','side','Debit','narration','Temporary test'),
    jsonb_build_object('ledger_name',v_cash,'ledger_code','2','amount','100.00','side','Credit','narration','Temporary test'));
  begin
    perform public.save_salary_entries(v_statement,jsonb_build_array(jsonb_build_object('category','bankVikin','branch_id',1,'lines',v_lines)));
    raise exception 'Expected malformed Vikin voucher rejection';
  exception when raise_exception then if sqlerrm<>'Vikin entries must be grouped JV vouchers by statement branch and company.' then raise; end if; end;
  v_payload:='[]'::jsonb;
  for v_count in 1..3 loop
    v_payload:=v_payload||jsonb_build_array(jsonb_build_object('category',(array['booking','adjustments','bankPolosys'])[v_count],'branch_id',1,'lines',v_lines));
  end loop;
  for v_count in 3..4 loop
    v_payload:=v_payload||jsonb_build_array(jsonb_build_object('category','cash','branch_id',1,'employee_id','EMP'||v_count,'employee_name','Employee '||v_count,
      'paid_from',jsonb_build_object('name',v_cash,'code','2'),'lines',v_lines));
  end loop;
  v_batch:=public.save_salary_entries(v_statement,v_payload);
  if jsonb_array_length(v_batch->'vouchers')<>5 then raise exception 'Save All must preserve three MJVs and two CPs'; end if;
  if exists(select 1 from public.assistant_workflow_tasks where payload->>'salary_statement_id'=v_statement::text) then raise exception 'Save must not create tasks'; end if;
  begin
    perform public.save_salary_entries(v_statement,v_payload); raise exception 'Expected duplicate save lock';
  exception when raise_exception then if sqlerrm<>'Salary entries are already saved and locked.' then raise; end if; end;
  begin
    update public.salary_entry_vouchers set lines='[]' where batch_id=(v_batch->>'id')::uuid; raise exception 'Expected immutable saved lines';
  exception when raise_exception then if sqlerrm<>'Saved salary entries are locked.' then raise; end if; end;
  select entry_task_user_id into strict v_assignee from public.branch_default_positions where branch_id=1;
  update public.branch_default_positions set entry_task_user_id=null where branch_id=1;
  begin
    perform public.post_salary_entry_tasks((v_batch->>'id')::uuid,'booking'); raise exception 'Expected missing assignee rejection';
  exception when raise_exception then if sqlerrm not like 'No active Entry Task user is configured%' then raise; end if; end;
  if exists(select 1 from public.assistant_workflow_tasks where payload->>'salary_statement_id'=v_statement::text) then raise exception 'Failed task assignment must not leave partial tasks'; end if;
  update public.branch_default_positions set entry_task_user_id=v_assignee where branch_id=1;
  foreach v_cash in array array['booking','adjustments','bankPolosys'] loop
    v_result:=public.post_salary_entry_tasks((v_batch->>'id')::uuid,v_cash);
    select task_id,voucher_date into strict v_task,v_date from public.salary_entry_vouchers where batch_id=(v_batch->>'id')::uuid and category=v_cash;
    if v_date is distinct from (case when v_cash='bankPolosys' then (now() at time zone 'Asia/Riyadh')::date else '2026-09-24'::date end) then raise exception 'Wrong category posting date'; end if;
    if not exists(select 1 from public.assistant_workflow_tasks t join public.branch_default_positions d on d.branch_id=t.branch_id
      where t.id=v_task and t.assigned_to=d.entry_task_user_id and t.task_type='cash_closing_mjv' and t.payload->>'posting_date'=v_date::text)
      then raise exception 'Wrong MJV task assignee or payload'; end if;
    perform public.post_salary_entry_tasks((v_batch->>'id')::uuid,v_cash);
  end loop;
  select id into strict v_voucher from public.salary_entry_vouchers where batch_id=(v_batch->>'id')::uuid and employee_id='EMP3';
  select id into strict v_cp2 from public.salary_entry_vouchers where batch_id=(v_batch->>'id')::uuid and employee_id='EMP4';
  perform public.post_salary_entry_tasks((v_batch->>'id')::uuid,'cash',v_voucher);
  select task_id into strict v_task from public.salary_entry_vouchers where id=v_voucher;
  if not exists(select 1 from public.assistant_workflow_tasks where id=v_task and task_type='salary_cash_payment'
    and payload->>'amount'='100.00' and payload->>'posting_date' is null) then raise exception 'CP contract must preserve current date behavior'; end if;
  if (select task_id from public.salary_entry_vouchers where id=v_cp2) is not null then raise exception 'CP task must be individual'; end if;
  perform public.post_salary_entry_tasks((v_batch->>'id')::uuid,'cash',v_voucher);
  select count(*) into v_count from public.assistant_workflow_tasks where payload->>'salary_statement_id'=v_statement::text;
  if v_count<>4 then raise exception 'Duplicate tasks must be prevented'; end if;
  update public.assistant_workflow_tasks set status='completed' where id=v_task;
  begin
    update public.assistant_workflow_tasks set status='pending' where id=v_task; raise exception 'Expected completed task lock';
  exception when raise_exception then if sqlerrm<>'Salary posting tasks are locked.' then raise; end if; end;
  v_result:=public.get_saved_salary_entries(v_statement);
  if not exists(select 1 from jsonb_array_elements(v_result->'vouchers') v where v->>'id'=v_voucher::text and v->>'task_status'='completed') then raise exception 'Completion must appear on saved CP'; end if;
end;
$$;
rollback;
