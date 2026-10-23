begin;

-- Real Vikin adjustment/reversal pairs are a new task type. Legacy no-save
-- tasks retain their completion guard and must be explicitly cleaned up.
create function public.validate_salary_vikin_adjustment_jv() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_parent public.assistant_workflow_tasks%rowtype;
  v_expected jsonb;
  v_line jsonb;
  v_balance numeric := 0;
  v_kind text;
begin
  if tg_op = 'DELETE' then
    if old.task_type = 'salary_vikin_adjustment_jv' then
      if old.status = 'completed' then raise exception 'Posted Vikin JVs cannot be deleted; use their reversal task.'; end if;
      if exists(select 1 from public.assistant_workflow_tasks t
        where t.task_type = 'salary_vikin_adjustment_jv' and t.payload->>'depends_on_task_id' = old.id::text) then
        raise exception 'Remove the dependent pending Vikin reversal before removing its original task.';
      end if;
    end if;
    return old;
  end if;
  if tg_op = 'UPDATE' and old.task_type = 'salary_vikin_adjustment_jv' then
    if new.task_type is distinct from old.task_type or new.payload is distinct from old.payload
      or new.branch_id is distinct from old.branch_id or new.source_record_id is distinct from old.source_record_id
      or new.assigned_to is distinct from old.assigned_to or new.created_by is distinct from old.created_by
      or new.workflow_key is distinct from old.workflow_key then
      raise exception 'Vikin adjustment and reversal task entries are locked after creation.';
    end if;
    if old.status = 'completed' and new.status <> 'completed' then
      raise exception 'Posted Vikin JV tasks cannot be reopened.';
    end if;
  end if;
  if new.task_type <> 'salary_vikin_adjustment_jv' then return new; end if;
  v_kind := new.payload->>'entry_kind';
  if new.payload->>'version' is distinct from '3' or new.payload->>'erp_provider' is distinct from 'vikin'
    or new.payload->'test_mode' is distinct from 'false'::jsonb
    or new.payload->'save_enabled' is distinct from 'true'::jsonb
    or v_kind is null or v_kind not in ('adjustment', 'reversal') then
    raise exception 'Invalid saved Vikin JV task contract.';
  end if;
  if new.payload->>'salary_statement_id' is distinct from new.source_record_id::text
    or new.payload->>'branch_id' is distinct from new.branch_id::text
    or not exists(select 1 from public.hr_salary_statements s where s.id = new.source_record_id
      and s.end_date::text = new.payload->>'posting_date')
    or not exists(select 1 from public.company_master c
      where c.id::text = new.payload->>'company_id' and c.erp_provider = 'vikin') then
    raise exception 'Vikin JV company, branch, statement or posting date does not match.';
  end if;
  if jsonb_typeof(new.payload->'lines') is distinct from 'array'
    or jsonb_array_length(new.payload->'lines') not between 2 and 2000
    or jsonb_array_length(new.payload->'lines') % 2 <> 0
    or jsonb_typeof(new.payload->'employee_ids') is distinct from 'array'
    or jsonb_array_length(new.payload->'employee_ids') * 2 <> jsonb_array_length(new.payload->'lines')
    or new.payload->>'employee_count' is distinct from jsonb_array_length(new.payload->'employee_ids')::text
    or new.payload->>'line_count' is distinct from jsonb_array_length(new.payload->'lines')::text then
    raise exception 'Vikin JV employee and line counts do not match.';
  end if;
  for v_line in select value from jsonb_array_elements(new.payload->'lines') loop
    if nullif(btrim(v_line->>'ledger_name'), '') is null or nullif(btrim(v_line->>'ledger_code'), '') is null
      or nullif(btrim(v_line->>'narration'), '') is null
      or coalesce(v_line->>'side', '') not in ('Debit', 'Credit')
      or coalesce(v_line->>'amount', '') !~ '^[0-9]{1,16}(\.[0-9]{1,2})?$'
      or (v_line->>'amount')::numeric <= 0 then
      raise exception 'Vikin JV lines need real ledgers, narration and positive amounts.';
    end if;
    v_balance := v_balance + case when v_line->>'side' = 'Debit' then (v_line->>'amount')::numeric else -(v_line->>'amount')::numeric end;
  end loop;
  if v_balance <> 0 then raise exception 'Vikin JV lines must balance.'; end if;
  if v_kind = 'adjustment' then
    if new.payload ? 'depends_on_task_id' then raise exception 'An original Vikin adjustment cannot depend on another task.'; end if;
    return new;
  end if;
  select * into v_parent from public.assistant_workflow_tasks
    where id::text = new.payload->>'depends_on_task_id' for share;
  if not found or v_parent.id = new.id or v_parent.task_type <> 'salary_vikin_adjustment_jv'
    or v_parent.payload->>'entry_kind' is distinct from 'adjustment'
    or v_parent.branch_id is distinct from new.branch_id
    or v_parent.source_record_id is distinct from new.source_record_id
    or v_parent.assigned_to is distinct from new.assigned_to or v_parent.created_by is distinct from new.created_by then
    raise exception 'The Vikin reversal must reference its matching original adjustment task.';
  end if;
  select v_parent.payload || jsonb_build_object('entry_kind', 'reversal', 'depends_on_task_id', v_parent.id,
    'lines', jsonb_agg(l.line || jsonb_build_object('side',
      case l.line->>'side' when 'Debit' then 'Credit' else 'Debit' end,
      'narration', 'Reversal | ' || (l.line->>'narration')) order by l.ordinality))
    into v_expected from jsonb_array_elements(v_parent.payload->'lines') with ordinality l(line, ordinality);
  if new.payload is distinct from v_expected then
    raise exception 'The Vikin reversal must exactly reverse its original ledgers, amounts, date and narration.';
  end if;
  if new.status in ('in_progress', 'completed') and v_parent.status <> 'completed' then
    raise exception 'Post and save the original Vikin adjustment before posting its reversal.';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_salary_vikin_adjustment_jv() from public, anon, authenticated;
create trigger validate_salary_vikin_adjustment_jv before insert or update or delete
  on public.assistant_workflow_tasks for each row execute function public.validate_salary_vikin_adjustment_jv();

create or replace function public.get_salary_vikin_adjustment_test_tasks(p_statement_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.salary_company_adjustment_can_access() then
    raise exception 'Salary Statement permission required.' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', t.id, 'task_type', t.task_type, 'status', t.status, 'branch_id', t.branch_id,
    'company_id', t.payload->'company_id', 'company_name', t.payload->>'company_name',
    'entry_kind', coalesce(t.payload->>'entry_kind', 'test'),
    'depends_on_task_id', t.payload->>'depends_on_task_id', 'depends_on_status', parent.status,
    'employee_id', t.payload->>'employee_id',
    'employee_ids', coalesce(t.payload->'employee_ids',
      case when nullif(t.payload->>'employee_id', '') is not null
        then jsonb_build_array(t.payload->>'employee_id') else '[]'::jsonb end),
    'employee_count', coalesce(t.payload->'employee_count',
      to_jsonb(case when nullif(t.payload->>'employee_id', '') is not null then 1 else 0 end)),
    'line_count', jsonb_array_length(t.payload->'lines'))
      order by t.branch_id, t.payload->>'company_id',
        case t.payload->>'entry_kind' when 'adjustment' then 0 when 'reversal' then 1 else 2 end, t.created_at, t.id)
    from public.assistant_workflow_tasks t left join public.assistant_workflow_tasks parent
      on parent.id::text = t.payload->>'depends_on_task_id'
    where t.task_type in ('salary_vikin_adjustment_test_jv', 'salary_vikin_adjustment_jv')
      and t.source_record_id = p_statement_id), '[]'::jsonb);
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
  v_original_id uuid;
  v_reversal_id uuid;
  v_reversal_payload jsonb;
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
    v_workflow := 'salary-vikin-adjustment-v3:' || p_statement_id || ':' || v_group.branch_id || ':' || v_group.company_id;
    select id into v_original_id from public.assistant_workflow_tasks where workflow_key = v_workflow || ':adjustment';
    if not found then v_original_id := gen_random_uuid(); end if;
    select id into v_reversal_id from public.assistant_workflow_tasks where workflow_key = v_workflow || ':reversal';
    if not found then v_reversal_id := gen_random_uuid(); end if;
    v_payload := jsonb_build_object('version', 3, 'erp_provider', 'vikin', 'test_mode', false, 'save_enabled', true,
      'entry_kind', 'adjustment',
      'salary_statement_id', p_statement_id, 'company_id', v_group.company_id,
      'company_name', v_first->>'company_name', 'company_name_ar', v_first->>'company_name_ar',
      'branch_id', v_group.branch_id, 'branch_name', v_first->>'branch_name',
      'employee_ids', v_employee_ids, 'employee_count', jsonb_array_length(v_employee_ids),
      'line_count', jsonb_array_length(v_lines), 'posting_date', v_statement.end_date, 'lines', v_lines);
    select v_payload || jsonb_build_object('entry_kind', 'reversal', 'depends_on_task_id', v_original_id,
      'lines', jsonb_agg(l.line || jsonb_build_object('side',
        case l.line->>'side' when 'Debit' then 'Credit' else 'Debit' end,
        'narration', 'Reversal | ' || (l.line->>'narration')) order by l.ordinality))
      into v_reversal_payload from jsonb_array_elements(v_lines) with ordinality l(line, ordinality);
    v_groups := v_groups || jsonb_build_array(
      jsonb_build_object('id', v_original_id, 'workflow_key', v_workflow || ':adjustment',
        'branch_id', v_group.branch_id, 'assigned_to', v_first->>'assigned_to', 'payload', v_payload,
        'title', 'Vikin Adjustment JV - ' || (v_first->>'branch_name') || ' - '
          || coalesce(v_first->>'company_name', v_first->>'company_name_ar') || ' (' || jsonb_array_length(v_employee_ids) || ' employees)'),
      jsonb_build_object('id', v_reversal_id, 'workflow_key', v_workflow || ':reversal',
        'branch_id', v_group.branch_id, 'assigned_to', v_first->>'assigned_to', 'payload', v_reversal_payload,
        'title', 'Vikin Reversal JV - ' || (v_first->>'branch_name') || ' - '
          || coalesce(v_first->>'company_name', v_first->>'company_name_ar') || ' (' || jsonb_array_length(v_employee_ids) || ' employees)'));
  end loop;

  -- Old no-save tasks are removed explicitly after backup, never silently
  -- upgraded into real financial posting tasks.
  perform 1 from public.assistant_workflow_tasks where source_record_id = p_statement_id
    and task_type in ('salary_vikin_adjustment_test_jv', 'salary_vikin_adjustment_jv') for update;
  if exists(select 1 from public.assistant_workflow_tasks
    where task_type = 'salary_vikin_adjustment_test_jv' and source_record_id = p_statement_id) then
    raise exception 'Remove the previous no-save Vikin test tasks before creating adjustment and reversal JVs.';
  end if;
  select count(*) into v_existing_count from public.assistant_workflow_tasks
    where task_type = 'salary_vikin_adjustment_jv' and source_record_id = p_statement_id;
  if v_existing_count > 0 then
    if v_existing_count <> jsonb_array_length(v_groups) then
      raise exception 'Vikin adjustment and reversal tasks already exist for a different entry set. Refresh the task status; do not post a partial set.';
    end if;
    for v_item in select value from jsonb_array_elements(v_groups) loop
      select * into v_existing from public.assistant_workflow_tasks where workflow_key = v_item->>'workflow_key';
      if not found or v_existing.payload is distinct from v_item->'payload'
        or v_existing.branch_id is distinct from (v_item->>'branch_id')::bigint
        or v_existing.assigned_to is distinct from (v_item->>'assigned_to')::uuid
        or v_existing.task_type <> 'salary_vikin_adjustment_jv'
        or v_existing.source_record_id is distinct from p_statement_id then
        raise exception 'Vikin adjustment and reversal tasks already exist for different entries or account links. Refresh the task status; existing tasks cannot be replaced.';
      end if;
    end loop;
    return public.get_salary_vikin_adjustment_test_tasks(p_statement_id);
  end if;

  for v_item in select value from jsonb_array_elements(v_groups) loop
    insert into public.assistant_workflow_tasks(id, task_type, title, branch_id, assigned_to, created_by, source_record_id, workflow_key, payload)
    values((v_item->>'id')::uuid, 'salary_vikin_adjustment_jv', v_item->>'title', (v_item->>'branch_id')::bigint,
      (v_item->>'assigned_to')::uuid, v_actor, p_statement_id, v_item->>'workflow_key', v_item->'payload');
  end loop;
  return public.get_salary_vikin_adjustment_test_tasks(p_statement_id);
end;
$$;

-- The old prevent_vikin_test_task_completion trigger is intentionally retained.
revoke all on function public.get_salary_vikin_adjustment_test_tasks(uuid),
  public.post_salary_vikin_adjustment_test_tasks(uuid,jsonb) from public, anon;
grant execute on function public.get_salary_vikin_adjustment_test_tasks(uuid),
  public.post_salary_vikin_adjustment_test_tasks(uuid,jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
