begin;

create function public.get_salary_vikin_adjustment_test_tasks(p_statement_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.salary_company_adjustment_can_access() then
    raise exception 'Salary Statement permission required.' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'status', status,
    'employee_id', payload->>'employee_id', 'branch_id', branch_id) order by created_at, id)
    from public.assistant_workflow_tasks where task_type = 'salary_vikin_adjustment_test_jv' and source_record_id = p_statement_id), '[]'::jsonb);
end;
$$;

create function public.post_salary_vikin_adjustment_test_tasks(p_statement_id uuid, p_entries jsonb)
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
  v_assignee uuid;
  v_amount numeric(18,2);
  v_narration text;
  v_workflow text;
  v_start text;
begin
  if not public.salary_company_adjustment_can_access() then
    raise exception 'Salary Statement permission required.' using errcode = '42501';
  end if;
  select * into v_statement from public.hr_salary_statements where id = p_statement_id for update;
  if not found then raise exception 'Saved salary statement not found.'; end if;
  if jsonb_typeof(p_entries) is distinct from 'array' or jsonb_array_length(p_entries) not between 1 and 1000 then
    raise exception 'Generate the Vikin adjustment entries first.';
  end if;
  if exists(select 1 from jsonb_array_elements(p_entries) e group by e->>'employee_id', e->>'branch_id' having count(*) > 1) then
    raise exception 'Duplicate employee adjustment entries.';
  end if;
  v_start := v_statement.start_date::text;
  for v_item in select value from jsonb_array_elements(p_entries) loop
    if coalesce(v_item->>'amount','') !~ '^[0-9]+(\.[0-9]{1,2})?$' or (v_item->>'amount')::numeric <= 0 then
      raise exception 'Each Vikin adjustment needs a positive Net Bank amount.';
    end if;
    v_amount := (v_item->>'amount')::numeric;
    select * into v_employee from public.hr_employee_master where id = v_item->>'employee_id' for share;
    if not found then raise exception 'Employee not found.'; end if;
    select * into v_branch from public.branches where id = (v_item->>'branch_id')::bigint;
    if not found or not exists(select 1 from jsonb_array_elements(v_statement.data_json->'analysisData') r
      where r->>'employeeId' = v_employee.id and (r->>'currentBranchId')::bigint = v_branch.id) then
      raise exception 'Employee % is not in this statement branch.', v_employee.id;
    end if;
    select * into v_company from public.company_master where id = v_employee.sponsor_id and erp_provider = 'vikin' for share;
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
        where e.user_id = d.entry_task_user_id and e.current_branch_id = v_branch.id and not e.is_removed);
    if v_assignee is null then raise exception 'No active Entry Task user is configured for %.', v_branch.name_en; end if;
    v_workflow := 'salary-vikin-adjustment-test:' || p_statement_id || ':' || v_branch.id || ':' || v_employee.id;
    v_narration := 'Salary branch adjustment ' || v_start || ' to ' || v_statement.end_date || ' | ' || v_employee.id || ' - '
      || coalesce(v_employee.name_en, v_employee.name_ar, v_employee.id) || ' | ' || coalesce(v_branch.name_en, v_branch.name_ar);
    if not exists(select 1 from public.assistant_workflow_tasks where workflow_key = v_workflow) then
      insert into public.assistant_workflow_tasks(task_type, title, branch_id, assigned_to, created_by, source_record_id, workflow_key, payload)
      values('salary_vikin_adjustment_test_jv', 'Vikin Adjustment JV (TEST — NO SAVE) - ' || v_employee.id || ' - ' || coalesce(v_branch.name_en, v_branch.name_ar),
        v_branch.id, v_assignee, v_actor, p_statement_id, v_workflow,
        jsonb_build_object('version', 1, 'erp_provider', 'vikin', 'test_mode', true, 'save_enabled', false,
          'salary_statement_id', p_statement_id, 'employee_id', v_employee.id, 'company_id', v_company.id,
          'company_name', v_company.name_en, 'company_name_ar', v_company.name_ar,
          'posting_date', v_statement.end_date, 'branch_name', coalesce(v_branch.name_en, v_branch.name_ar),
          'lines', jsonb_build_array(
            jsonb_build_object('ledger_name', v_adjustment_ledger.ledger_name, 'ledger_code', v_adjustment_ledger.ledger_code,
              'side', 'Debit', 'amount', to_char(v_amount,'FM9999999999999990.00'), 'narration', v_narration),
            jsonb_build_object('ledger_name', v_employee_ledger.ledger_name, 'ledger_code', v_employee_ledger.ledger_code,
              'side', 'Credit', 'amount', to_char(v_amount,'FM9999999999999990.00'), 'narration', v_narration))));
    end if;
  end loop;
  return public.get_salary_vikin_adjustment_test_tasks(p_statement_id);
end;
$$;

create function public.prevent_vikin_test_task_completion() returns trigger language plpgsql as $$
begin
  if new.task_type = 'salary_vikin_adjustment_test_jv' and new.status = 'completed' then
    raise exception 'Vikin JV test tasks cannot be completed: final Save is disabled.';
  end if;
  return new;
end;
$$;
create trigger prevent_vikin_test_task_completion before insert or update on public.assistant_workflow_tasks
  for each row execute function public.prevent_vikin_test_task_completion();
revoke all on function public.get_salary_vikin_adjustment_test_tasks(uuid), public.post_salary_vikin_adjustment_test_tasks(uuid,jsonb) from public, anon;
grant execute on function public.get_salary_vikin_adjustment_test_tasks(uuid), public.post_salary_vikin_adjustment_test_tasks(uuid,jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
