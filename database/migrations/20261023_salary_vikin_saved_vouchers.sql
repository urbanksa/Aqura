begin;

-- Existing batches may append the two Vikin categories once without changing
-- any previously saved or posted Polosys vouchers. New saves lock all categories.
alter table public.salary_entry_batches add column vikin_entries_saved boolean not null default false;
alter table public.salary_entry_vouchers
  add column company_id bigint references public.company_master(id),
  add column company_name text,
  add column company_name_ar text,
  add column employee_ids jsonb not null default '[]'::jsonb,
  add column employee_entries jsonb not null default '[]'::jsonb;
alter table public.salary_entry_vouchers
  drop constraint salary_entry_vouchers_category_check,
  drop constraint salary_entry_vouchers_voucher_type_check,
  drop constraint salary_entry_vouchers_check1,
  drop constraint salary_entry_vouchers_batch_id_category_branch_id_employee__key,
  add constraint salary_entry_vouchers_category_check check(category in ('booking','adjustments','adjustmentsVikin','bankPolosys','bankVikin','cash')),
  add constraint salary_entry_vouchers_voucher_type_check check(voucher_type in ('MJV','JV','CP')),
  add constraint salary_entry_vouchers_kind_check check(
    (category='cash' and voucher_type='CP' and employee_id<>'' and company_id is null)
    or (category in ('booking','adjustments','bankPolosys') and voucher_type='MJV' and employee_id='' and company_id is null)
    or (category in ('adjustmentsVikin','bankVikin') and voucher_type='JV' and employee_id='' and company_id is not null
      and jsonb_typeof(employee_ids)='array' and jsonb_typeof(employee_entries)='array'
      and jsonb_array_length(employee_ids) between 1 and 1000
      and jsonb_array_length(employee_ids)=jsonb_array_length(employee_entries)
      and jsonb_array_length(lines)=2*jsonb_array_length(employee_ids)));
create unique index salary_entry_vouchers_polosys_group_unique
  on public.salary_entry_vouchers(batch_id,category,branch_id,employee_id) where company_id is null;
create unique index salary_entry_vouchers_vikin_group_unique
  on public.salary_entry_vouchers(batch_id,category,branch_id,company_id) where company_id is not null;

create or replace function public.lock_saved_salary_entries() returns trigger language plpgsql as $$
begin
  if tg_op='DELETE' then raise exception 'Saved salary entries are locked.'; end if;
  if tg_table_name='salary_entry_batches' then
    if not old.vikin_entries_saved and new.vikin_entries_saved
      and (to_jsonb(new)-'vikin_entries_saved')=(to_jsonb(old)-'vikin_entries_saved') then return new; end if;
    raise exception 'Saved salary entries are locked.';
  end if;
  if (to_jsonb(new)-'task_id'-'task_created_at'-'voucher_date') is distinct from (to_jsonb(old)-'task_id'-'task_created_at'-'voucher_date')
    or old.task_id is not null then raise exception 'Saved salary entries are locked.'; end if;
  if new.task_id is null or new.task_created_at is null then raise exception 'Only task assignment may update a saved voucher.'; end if;
  return new;
end;
$$;

-- Called only by the permission-checked Save RPC, after generic line/amount
-- validation. Rebuild names and metadata from current company-scoped mappings.
create function public.validate_salary_vikin_voucher(p_statement_id uuid,p_item jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_statement public.hr_salary_statements%rowtype;
  v_company public.company_master%rowtype;
  v_employee public.hr_employee_master%rowtype;
  v_employee_ledger public.vikin_ledgers%rowtype;
  v_other_ledger public.vikin_ledgers%rowtype;
  v_entry jsonb; v_ids jsonb; v_entries jsonb:='[]'::jsonb; v_lines jsonb;
  v_first jsonb; v_second jsonb; v_amount numeric(18,2); v_index integer:=0; v_prefix text;
begin
  select * into strict v_statement from public.hr_salary_statements where id=p_statement_id;
  if p_item->>'voucher_type' is distinct from 'JV' or coalesce(p_item->>'employee_id','')<>'' then
    raise exception 'Vikin entries must be grouped JV vouchers by statement branch and company.';
  end if;
  select * into v_company from public.company_master where id=(p_item->>'company_id')::bigint and erp_provider='vikin' for share;
  if not found then raise exception 'Select the employee sponsor company linked to Vikin.'; end if;
  if jsonb_typeof(p_item->'employee_entries') is distinct from 'array'
    or jsonb_array_length(p_item->'employee_entries') not between 1 and 1000
    or jsonb_typeof(p_item->'employee_ids') is distinct from 'array'
    or jsonb_array_length(p_item->'lines')<>2*jsonb_array_length(p_item->'employee_entries') then
    raise exception 'Each Vikin employee requires one ordered debit and credit pair (up to 2000 lines).';
  end if;
  select jsonb_agg(e.value->>'employee_id' order by e.ordinality) into v_ids
    from jsonb_array_elements(p_item->'employee_entries') with ordinality e(value,ordinality);
  if v_ids is distinct from p_item->'employee_ids'
    or exists(select 1 from jsonb_array_elements_text(v_ids) e group by e having count(*)>1) then
    raise exception 'Vikin voucher employee IDs must match its unique ordered employee entries.';
  end if;
  for v_entry in select value from jsonb_array_elements(p_item->'employee_entries') loop
    if coalesce(v_entry->>'amount','') !~ '^[0-9]{1,16}(\.[0-9]{1,2})?$' or (v_entry->>'amount')::numeric<=0 then
      raise exception 'Each Vikin employee entry requires a positive Net Bank amount.';
    end if;
    v_amount:=(v_entry->>'amount')::numeric;
    select * into v_employee from public.hr_employee_master where id=v_entry->>'employee_id' for share;
    if not found or v_employee.sponsor_id is distinct from v_company.id or not exists(
      select 1 from jsonb_array_elements(v_statement.data_json->'analysisData') r
      where r->>'employeeId'=v_employee.id and (r->>'currentBranchId')::bigint=(p_item->>'branch_id')::bigint) then
      raise exception 'Each Vikin employee must belong to this statement branch and sponsor company.';
    end if;
    select l.* into v_employee_ledger from public.vikin_employee_ledger_links a
      join public.vikin_ledgers l on l.id=a.vikin_ledger_id and l.company_id=a.company_id
      where a.employee_id=v_employee.id and a.company_id=v_company.id for share of a,l;
    if not found then raise exception 'Employee % has no linked Vikin ledger.',v_employee.id; end if;
    if p_item->>'category'='adjustmentsVikin' then
      select l.* into v_other_ledger from public.salary_vikin_branch_adjustment_accounts a
        join public.vikin_ledgers l on l.id=a.ledger_id and l.company_id=a.company_id
        where a.company_id=v_company.id and a.branch_id=(p_item->>'branch_id')::bigint for share of a,l;
      if not found then raise exception 'Link the Vikin branch adjustment ledger before saving.'; end if;
    else
      select l.* into v_other_ledger from public.salary_vikin_bank_accounts a
        join public.vikin_ledgers l on l.id=a.ledger_id and l.company_id=a.company_id
        where a.company_id=v_company.id for share of a,l;
      if not found then raise exception 'Link the Vikin company salary bank ledger before saving.'; end if;
    end if;
    v_first:=p_item->'lines'->(2*v_index); v_second:=p_item->'lines'->(2*v_index+1);
    if v_first->>'side' is distinct from 'Debit' or v_second->>'side' is distinct from 'Credit'
      or (v_first->>'amount')::numeric is distinct from v_amount or (v_second->>'amount')::numeric is distinct from v_amount
      or v_first->>'ledger_name' is distinct from (case when p_item->>'category'='adjustmentsVikin' then v_other_ledger.ledger_name else v_employee_ledger.ledger_name end)
      or v_first->>'ledger_code' is distinct from (case when p_item->>'category'='adjustmentsVikin' then v_other_ledger.ledger_code else v_employee_ledger.ledger_code end)
      or v_second->>'ledger_name' is distinct from (case when p_item->>'category'='adjustmentsVikin' then v_employee_ledger.ledger_name else v_other_ledger.ledger_name end)
      or v_second->>'ledger_code' is distinct from (case when p_item->>'category'='adjustmentsVikin' then v_employee_ledger.ledger_code else v_other_ledger.ledger_code end) then
      raise exception 'Vikin employee ledger pairs must use the current linked ledgers, sides and Net Bank amounts.';
    end if;
    v_prefix:='Salary '||case when p_item->>'category'='adjustmentsVikin' then 'branch adjustment' else 'bank payment' end
      ||' '||v_statement.start_date||' to '||v_statement.end_date||' | '||v_employee.id||' - ';
    if left(v_first->>'narration',length(v_prefix)) is distinct from v_prefix
      or v_first->>'narration' is distinct from v_second->>'narration' then
      raise exception 'Vikin narration must identify its employee and salary statement period.';
    end if;
    v_entries:=v_entries||jsonb_build_array(jsonb_build_object('employee_id',v_employee.id,'amount',to_char(v_amount,'FM9999999999999990.00')));
    v_index:=v_index+1;
  end loop;
  return jsonb_build_object('company_id',v_company.id,'company_name',v_company.name_en,'company_name_ar',v_company.name_ar,
    'employee_ids',v_ids,'employee_entries',v_entries);
end;
$$;
revoke all on function public.validate_salary_vikin_voucher(uuid,jsonb) from public,anon,authenticated;

create or replace function public.save_salary_entries(p_statement_id uuid,p_vouchers jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_actor uuid:=public.aqura_current_user_id(); v_statement public.hr_salary_statements%rowtype;
  v_existing public.salary_entry_batches%rowtype; v_batch uuid; v_item jsonb; v_line jsonb;
  v_debit numeric; v_credit numeric; v_branch text; v_vikin jsonb; v_append boolean:=false;
begin
  if not public.salary_company_adjustment_can_access() then raise exception 'Salary Statement permission required.'; end if;
  select * into v_statement from public.hr_salary_statements where id=p_statement_id for update;
  if not found then raise exception 'Saved salary statement not found.'; end if;
  if jsonb_typeof(p_vouchers) is distinct from 'array' then raise exception 'Generate all entries before saving.'; end if;
  select * into v_existing from public.salary_entry_batches where statement_id=p_statement_id for update;
  if found then
    if v_existing.vikin_entries_saved then raise exception 'Salary entries are already saved and locked.'; end if;
    if v_existing.source_snapshot_hash is distinct from md5(v_statement.data_json::text)
      or v_existing.statement_end_date is distinct from v_statement.end_date then
      raise exception 'The statement changed after saving; Vikin entries cannot be appended to a different snapshot.';
    end if;
    if exists(select 1 from jsonb_array_elements(p_vouchers) e where coalesce(e->>'category','') not in ('adjustmentsVikin','bankVikin')) then
      raise exception 'Only Vikin entries may be appended to an existing saved salary batch.';
    end if;
    if exists(select 1 from public.salary_entry_vouchers where batch_id=v_existing.id and category in ('adjustmentsVikin','bankVikin')) then
      raise exception 'Vikin entries are already saved and locked.';
    end if;
    v_batch:=v_existing.id; v_append:=true;
  else
    if jsonb_array_length(p_vouchers)=0 then raise exception 'Generate all entries before saving.'; end if;
    insert into public.salary_entry_batches(statement_id,statement_end_date,source_snapshot_hash,created_by,vikin_entries_saved)
      values(p_statement_id,v_statement.end_date,md5(v_statement.data_json::text),v_actor,true) returning id into v_batch;
  end if;
  for v_item in select value from jsonb_array_elements(p_vouchers) loop
    if coalesce(v_item->>'category','') not in ('booking','adjustments','adjustmentsVikin','bankPolosys','bankVikin','cash') then
      raise exception 'Choose a valid salary entry category.';
    end if;
    v_vikin:=null;
    if v_item->>'category' in ('adjustmentsVikin','bankVikin') then
      select coalesce(name_en,name_ar) into v_branch from public.branches where id=(v_item->>'branch_id')::bigint;
      if not found then raise exception 'Select a valid employee statement branch.'; end if;
    else
      select b.name_en into v_branch from public.branches b join public.company_master c on c.id=b.company_id
        where b.id=(v_item->>'branch_id')::bigint and c.erp_provider='polosys';
      if not found then raise exception 'Only Polosys branch entries can be saved.'; end if;
    end if;
    if jsonb_typeof(v_item->'lines') is distinct from 'array' or jsonb_array_length(v_item->'lines')<2 then
      raise exception 'Every voucher needs balanced lines.';
    end if;
    v_debit:=0; v_credit:=0;
    for v_line in select value from jsonb_array_elements(v_item->'lines') loop
      if coalesce(v_line->>'side','') not in ('Debit','Credit') or nullif(btrim(v_line->>'ledger_name'),'') is null
        or nullif(btrim(v_line->>'narration'),'') is null or coalesce(v_line->>'amount','') !~ '^[0-9]{1,16}(\.[0-9]{1,2})?$'
        or (v_line->>'amount')::numeric<=0 or coalesce((v_line->>'placeholder')::boolean,false) then
        raise exception 'Invalid or placeholder salary voucher line.';
      end if;
      if v_line->>'side'='Debit' then v_debit:=v_debit+(v_line->>'amount')::numeric; else v_credit:=v_credit+(v_line->>'amount')::numeric; end if;
    end loop;
    if v_debit<>v_credit then raise exception 'Every salary voucher must balance.'; end if;
    if v_item->>'category' in ('adjustmentsVikin','bankVikin') then
      v_vikin:=public.validate_salary_vikin_voucher(p_statement_id,v_item);
    elsif v_item->>'category'='cash' then
      if jsonb_array_length(v_item->'lines')<>2 or not exists(select 1 from jsonb_array_elements(v_statement.data_json->'analysisData') r
        where r->>'employeeId'=v_item->>'employee_id' and r->>'employeeId'<>'EMP51' and (r->>'currentBranchId')::bigint=(v_item->>'branch_id')::bigint)
        or not exists(select 1 from public.erp_posting_ledger_links c where c.branch_id=(v_item->>'branch_id')::bigint and c.account_key='branch_cash'
          and c.ledger_name=v_item->'paid_from'->>'name' and exists(select 1 from jsonb_array_elements(v_item->'lines') l where l->>'side'='Credit' and l->>'ledger_name'=c.ledger_name)) then
        raise exception 'Each CP must use its employee statement branch and configured cash account.';
      end if;
    elsif coalesce(v_item->>'employee_id','')<>'' then raise exception 'MJVs must be grouped by category and branch.'; end if;
    insert into public.salary_entry_vouchers(batch_id,category,branch_id,branch_name,employee_id,employee_name,voucher_type,lines,
      debit_total,credit_total,paid_from,voucher_date,company_id,company_name,company_name_ar,employee_ids,employee_entries)
    values(v_batch,v_item->>'category',(v_item->>'branch_id')::bigint,v_branch,coalesce(v_item->>'employee_id',''),v_item->>'employee_name',
      case when v_vikin is not null then 'JV' when v_item->>'category'='cash' then 'CP' else 'MJV' end,v_item->'lines',v_debit,v_credit,
      case when v_item->>'category'='cash' then v_item->'paid_from' end,
      case when v_item->>'category' in ('booking','adjustments','adjustmentsVikin') then v_statement.end_date end,
      (v_vikin->>'company_id')::bigint,v_vikin->>'company_name',v_vikin->>'company_name_ar',
      coalesce(v_vikin->'employee_ids','[]'::jsonb),coalesce(v_vikin->'employee_entries','[]'::jsonb));
  end loop;
  if v_append then update public.salary_entry_batches set vikin_entries_saved=true where id=v_batch; end if;
  return public.get_saved_salary_entries(p_statement_id);
end;
$$;

create or replace function public.post_salary_entry_tasks(p_batch_id uuid,p_category text,p_voucher_id uuid default null) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_actor uuid:=public.aqura_current_user_id(); v_batch public.salary_entry_batches%rowtype;
  v_voucher public.salary_entry_vouchers%rowtype; v_assignee uuid; v_task uuid; v_payload jsonb; v_date date; v_is_vikin boolean;
begin
  if not public.salary_company_adjustment_can_access() then raise exception 'Salary Statement permission required.'; end if;
  select * into v_batch from public.salary_entry_batches where id=p_batch_id for update;
  if not found then raise exception 'Save salary entries before posting tasks.'; end if;
  if p_category is null or p_category not in ('booking','adjustments','adjustmentsVikin','bankPolosys','bankVikin','cash')
    or (p_category='cash' and p_voucher_id is null) or (p_category<>'cash' and p_voucher_id is not null) then
    raise exception 'Choose a category or one saved CP.';
  end if;
  if not exists(select 1 from public.salary_entry_vouchers where batch_id=p_batch_id and category=p_category
    and (p_voucher_id is null or id=p_voucher_id)) then raise exception 'No saved entries for this selection.'; end if;
  for v_voucher in select * from public.salary_entry_vouchers where batch_id=p_batch_id and category=p_category
    and (p_voucher_id is null or id=p_voucher_id) and task_id is null order by branch_id,company_id,id for update loop
    v_assignee:=null;
    select d.entry_task_user_id into v_assignee from public.branch_default_positions d join public.users u on u.id=d.entry_task_user_id and u.status='active'
      where d.branch_id=v_voucher.branch_id and exists(select 1 from public.hr_employee_master e
        where e.user_id=d.entry_task_user_id and e.current_branch_id=v_voucher.branch_id and not e.is_removed);
    if v_assignee is null then raise exception 'No active Entry Task user is configured for %.',v_voucher.branch_name; end if;
    v_is_vikin:=p_category in ('adjustmentsVikin','bankVikin');
    v_date:=case when p_category in ('bankPolosys','bankVikin') then (now() at time zone 'Asia/Riyadh')::date
      when p_category<>'cash' then v_batch.statement_end_date end;
    v_payload:=jsonb_build_object('version',1,'salary_entry_voucher_id',v_voucher.id,'salary_statement_id',v_batch.statement_id,
      'salary_category',p_category,'branch_name',v_voucher.branch_name,'statement_date',v_batch.statement_end_date,'posting_date',v_date,'lines',v_voucher.lines);
    if v_is_vikin then
      if not v_batch.vikin_entries_saved or not exists(select 1 from public.company_master where id=v_voucher.company_id and erp_provider='vikin') then
        raise exception 'Save the Vikin categories and use a company linked to Vikin before posting tasks.';
      end if;
      v_payload:=v_payload||jsonb_build_object('version',4,'erp_provider','vikin','test_mode',false,'save_enabled',true,
        'entry_kind',case when p_category='adjustmentsVikin' then 'adjustment' else 'bank_payment' end,
        'branch_id',v_voucher.branch_id,'company_id',v_voucher.company_id,'company_name',v_voucher.company_name,
        'company_name_ar',v_voucher.company_name_ar,'employee_ids',v_voucher.employee_ids,
        'employee_count',jsonb_array_length(v_voucher.employee_ids),'line_count',jsonb_array_length(v_voucher.lines));
    elsif p_category='cash' then
      select v_payload||jsonb_build_object('ledger_name',l->>'ledger_name','amount',l->>'amount','narration',l->>'narration',
        'cash_account',v_voucher.paid_from->>'name','employee_id',v_voucher.employee_id) into v_payload
        from jsonb_array_elements(v_voucher.lines) l where l->>'side'='Debit';
    end if;
    insert into public.assistant_workflow_tasks(task_type,title,branch_id,assigned_to,created_by,payload,source_record_id,workflow_key)
    values(case when v_is_vikin then 'salary_vikin_saved_jv' when p_category='cash' then 'salary_cash_payment' else 'cash_closing_mjv' end,
      'Salary '||p_category||' - '||v_voucher.branch_name||case when v_is_vikin then ' - '||coalesce(v_voucher.company_name,v_voucher.company_name_ar)
        when p_category='cash' then ' - '||v_voucher.employee_name else '' end,
      v_voucher.branch_id,v_assignee,v_actor,v_payload,v_voucher.id,'salary-entry:'||v_voucher.id) returning id into v_task;
    update public.salary_entry_vouchers set task_id=v_task,task_created_at=now(),voucher_date=v_date where id=v_voucher.id;
  end loop;
  return public.get_saved_salary_entries(v_batch.statement_id);
end;
$$;

-- The temporary test endpoint may not create unsaved JVs or reversals anymore.
create or replace function public.post_salary_vikin_adjustment_test_tasks(p_statement_id uuid,p_entries jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
begin
  if not public.salary_company_adjustment_can_access() then
    raise exception 'Salary Statement permission required.' using errcode='42501';
  end if;
  raise exception 'Save salary entries first, then use Post Task for the saved Vikin category.';
end;
$$;

revoke all on function public.save_salary_entries(uuid,jsonb),public.post_salary_entry_tasks(uuid,text,uuid),
  public.post_salary_vikin_adjustment_test_tasks(uuid,jsonb) from public,anon;
grant execute on function public.save_salary_entries(uuid,jsonb),public.post_salary_entry_tasks(uuid,text,uuid),
  public.post_salary_vikin_adjustment_test_tasks(uuid,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
