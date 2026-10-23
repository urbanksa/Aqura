begin;

-- One no-save JV per statement branch and Vikin company. Different company
-- books cannot share a voucher, even when employees work at the same branch.
create or replace function public.get_salary_vikin_adjustment_test_tasks(p_statement_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.salary_company_adjustment_can_access() then
    raise exception 'Salary Statement permission required.' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', t.id, 'status', t.status, 'branch_id', t.branch_id,
    'company_id', t.payload->'company_id', 'company_name', t.payload->>'company_name',
    'employee_id', t.payload->>'employee_id',
    'employee_ids', coalesce(t.payload->'employee_ids',
      case when nullif(t.payload->>'employee_id', '') is not null
        then jsonb_build_array(t.payload->>'employee_id') else '[]'::jsonb end),
    'employee_count', coalesce(t.payload->'employee_count',
      to_jsonb(case when nullif(t.payload->>'employee_id', '') is not null then 1 else 0 end)),
    'line_count', jsonb_array_length(t.payload->'lines')) order by t.branch_id, t.created_at, t.id)
    from public.assistant_workflow_tasks t
    where t.task_type = 'salary_vikin_adjustment_test_jv' and t.source_record_id = p_statement_id), '[]'::jsonb);
end;
$$;

create or replace function public.post_salary_vikin_adjustment_test_tasks(p_statement_id uuid, p_entries jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := public.aqura_current_user_id();
  v_statement public.hr_salary_statements%rowtype;
  v_item jsonb;
  v_employee public.hr_employee_master%rowtype;
  v_company public.company_master%rowtype;
  v_branch public.branches%rowtype;
  v_employee_ledger public.vikin_ledgers%rowtype;
  v_adjustment_ledger public.vikin_ledgers%rowtype;
  v_existing public.assistant_workflow_tasks%rowtype;
  v_assignee uuid;
  v_amount numeric(18,2);
  v_narration text;
  v_validated jsonb := '[]'::jsonb;
  v_groups jsonb := '[]'::jsonb;
  v_group record;
  v_first jsonb;
  v_lines jsonb;
  v_employee_ids jsonb;
  v_payload jsonb;
  v_workflow text;
  v_existing_count integer;
begin
  if not public.salary_company_adjustment_can_access() then
    raise exception 'Salary Statement permission required.' using errcode = '42501';
  end if;
  -- Serialize double-clicks and retries for the entire statement, not just a
  -- single employee. All validation/insertion remains one atomic transaction.
  select * into v_statement from public.hr_salary_statements where id = p_statement_id for update;
  if not found then raise exception 'Saved salary statement not found.'; end if;
  if jsonb_typeof(p_entries) is distinct from 'array' or jsonb_array_length(p_entries) not between 1 and 1000 then
    raise exception 'Generate the Vikin adjustment entries first (up to 1000 employees).';
  end if;
  if exists(select 1 from jsonb_array_elements(p_entries) e
    group by e->>'employee_id', (e->>'branch_id')::bigint having count(*) > 1) then
    raise exception 'Duplicate employee adjustment entries.';
  end if;

  for v_item in select value from jsonb_array_elements(p_entries)
    order by value->>'employee_id', value->>'branch_id' loop
    if coalesce(v_item->>'amount', '') !~ '^[0-9]{1,16}(\.[0-9]{1,2})?$'
      or (v_item->>'amount')::numeric <= 0 then
      raise exception 'Each Vikin adjustment needs a positive Net Bank amount.';
    end if;
    v_amount := (v_item->>'amount')::numeric;
    select * into v_employee from public.hr_employee_master where id = v_item->>'employee_id' for share;
    if not found then raise exception 'Employee not found.'; end if;
    select * into v_branch from public.branches where id = (v_item->>'branch_id')::bigint for share;
    if not found or not exists(select 1 from jsonb_array_elements(v_statement.data_json->'analysisData') r
      where r->>'employeeId' = v_employee.id and (r->>'currentBranchId')::bigint = v_branch.id) then
      raise exception 'Employee % is not in this statement branch.', v_employee.id;
    end if;
    select * into v_company from public.company_master
      where id = v_employee.sponsor_id and erp_provider = 'vikin' for share;
    if not found then raise exception 'Employee % is not sponsored by a Vikin company.', v_employee.id; end if;
    select l.* into v_employee_ledger from public.vikin_employee_ledger_links a
      join public.vikin_ledgers l on l.id = a.vikin_ledger_id and l.company_id = a.company_id
      where a.employee_id = v_employee.id and a.company_id = v_company.id for share of a, l;
    if not found then raise exception 'Employee % has no linked Vikin ledger.', v_employee.id; end if;
    select l.* into v_adjustment_ledger from public.salary_vikin_branch_adjustment_accounts a
      join public.vikin_ledgers l on l.id = a.ledger_id and l.company_id = a.company_id
      where a.company_id = v_company.id and a.branch_id = v_branch.id for share of a, l;
    if not found then raise exception 'Link the Vikin branch adjustment ledger for %.', v_branch.name_en; end if;
    v_assignee := null;
    select d.entry_task_user_id into v_assignee from public.branch_default_positions d
      join public.users u on u.id = d.entry_task_user_id and u.status = 'active'
      where d.branch_id = v_branch.id and exists(select 1 from public.hr_employee_master e
        where e.user_id = d.entry_task_user_id and e.current_branch_id = v_branch.id and not e.is_removed)
      for share of d, u;
    if v_assignee is null then raise exception 'No active Entry Task user is configured for %.', v_branch.name_en; end if;
    v_narration := 'Salary branch adjustment ' || v_statement.start_date || ' to ' || v_statement.end_date || ' | '
      || v_employee.id || ' - ' || coalesce(v_employee.name_en, v_employee.name_ar, v_employee.id)
      || ' | ' || coalesce(v_branch.name_en, v_branch.name_ar);
    v_validated := v_validated || jsonb_build_array(jsonb_build_object(
      'employee_id', v_employee.id, 'branch_id', v_branch.id, 'branch_name', coalesce(v_branch.name_en, v_branch.name_ar),
      'company_id', v_company.id, 'company_name', v_company.name_en, 'company_name_ar', v_company.name_ar,
      'assigned_to', v_assignee,
      'lines', jsonb_build_array(
        jsonb_build_object('ledger_name', v_adjustment_ledger.ledger_name, 'ledger_code', v_adjustment_ledger.ledger_code,
          'side', 'Debit', 'amount', to_char(v_amount, 'FM9999999999999990.00'), 'narration', v_narration),
        jsonb_build_object('ledger_name', v_employee_ledger.ledger_name, 'ledger_code', v_employee_ledger.ledger_code,
          'side', 'Credit', 'amount', to_char(v_amount, 'FM9999999999999990.00'), 'narration', v_narration))));
  end loop;

  for v_group in select (e->>'branch_id')::bigint as branch_id, (e->>'company_id')::bigint as company_id,
    jsonb_agg(e order by e->>'employee_id') as entries
    from jsonb_array_elements(v_validated) e
    group by (e->>'branch_id')::bigint, (e->>'company_id')::bigint
    order by (e->>'branch_id')::bigint, (e->>'company_id')::bigint loop
    v_first := v_group.entries->0;
    select jsonb_agg(e->>'employee_id' order by e->>'employee_id') into v_employee_ids
      from jsonb_array_elements(v_group.entries) e;
    select jsonb_agg(l.line order by e.ordinality, l.ordinality) into v_lines
      from jsonb_array_elements(v_group.entries) with ordinality e(item, ordinality)
      cross join lateral jsonb_array_elements(e.item->'lines') with ordinality l(line, ordinality);
    -- Input is capped at 1000 employees, hence each combined JV has 2..2000
    -- lines and retains the individual employee debit/credit narration pairs.
    v_workflow := 'salary-vikin-adjustment-test-v2:' || p_statement_id || ':' || v_group.branch_id || ':' || v_group.company_id;
    v_payload := jsonb_build_object('version', 2, 'erp_provider', 'vikin', 'test_mode', true, 'save_enabled', false,
      'salary_statement_id', p_statement_id, 'company_id', v_group.company_id,
      'company_name', v_first->>'company_name', 'company_name_ar', v_first->>'company_name_ar',
      'branch_id', v_group.branch_id, 'branch_name', v_first->>'branch_name',
      'employee_ids', v_employee_ids, 'employee_count', jsonb_array_length(v_employee_ids),
      'line_count', jsonb_array_length(v_lines), 'posting_date', v_statement.end_date, 'lines', v_lines);
    v_groups := v_groups || jsonb_build_array(jsonb_build_object(
      'workflow_key', v_workflow, 'branch_id', v_group.branch_id, 'assigned_to', v_first->>'assigned_to', 'payload', v_payload,
      'title', 'Vikin Adjustment JV (TEST — NO SAVE) - ' || (v_first->>'branch_name') || ' - '
        || coalesce(v_first->>'company_name', v_first->>'company_name_ar') || ' (' || jsonb_array_length(v_employee_ids) || ' employees)'));
  end loop;

  -- Existing per-employee tasks must be explicitly removed by the authorized
  -- cleanup before switching formats. Never leave old and new tasks together.
  perform 1 from public.assistant_workflow_tasks
    where task_type = 'salary_vikin_adjustment_test_jv' and source_record_id = p_statement_id for update;
  if exists(select 1 from public.assistant_workflow_tasks where task_type = 'salary_vikin_adjustment_test_jv'
    and source_record_id = p_statement_id and coalesce(payload->>'version', '') <> '2') then
    raise exception 'Remove the previous per-employee Vikin test tasks before creating combined JVs.';
  end if;
  select count(*) into v_existing_count from public.assistant_workflow_tasks
    where task_type = 'salary_vikin_adjustment_test_jv' and source_record_id = p_statement_id;
  if v_existing_count > 0 then
    if v_existing_count <> jsonb_array_length(v_groups) then
      raise exception 'Combined Vikin tasks already exist for a different entry set. Refresh the task status; do not post a partial set.';
    end if;
    for v_item in select value from jsonb_array_elements(v_groups) loop
      select * into v_existing from public.assistant_workflow_tasks where workflow_key = v_item->>'workflow_key';
      if not found or v_existing.payload is distinct from v_item->'payload'
        or v_existing.branch_id is distinct from (v_item->>'branch_id')::bigint
        or v_existing.assigned_to is distinct from (v_item->>'assigned_to')::uuid then
        raise exception 'Combined Vikin tasks already exist for different entries or account links. Refresh the task status; existing tasks cannot be replaced.';
      end if;
    end loop;
    return public.get_salary_vikin_adjustment_test_tasks(p_statement_id);
  end if;

  for v_item in select value from jsonb_array_elements(v_groups) loop
    insert into public.assistant_workflow_tasks(task_type, title, branch_id, assigned_to, created_by, source_record_id, workflow_key, payload)
    values('salary_vikin_adjustment_test_jv', v_item->>'title', (v_item->>'branch_id')::bigint,
      (v_item->>'assigned_to')::uuid, v_actor, p_statement_id, v_item->>'workflow_key', v_item->'payload');
  end loop;
  return public.get_salary_vikin_adjustment_test_tasks(p_statement_id);
end;
$$;

-- Keep the existing prevent_vikin_test_task_completion trigger: no test task
-- may become completed while final JV Save remains disabled.
revoke all on function public.get_salary_vikin_adjustment_test_tasks(uuid),
  public.post_salary_vikin_adjustment_test_tasks(uuid,jsonb) from public, anon;
grant execute on function public.get_salary_vikin_adjustment_test_tasks(uuid),
  public.post_salary_vikin_adjustment_test_tasks(uuid,jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
