begin;
create table public.salary_entry_batches (
  id uuid primary key default gen_random_uuid(),
  statement_id uuid not null unique references public.hr_salary_statements(id),
  statement_end_date date not null,
  source_snapshot_hash text not null,
  created_by uuid not null references public.users(id),
  created_at timestamptz not null default now()
);
create table public.salary_entry_vouchers (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.salary_entry_batches(id),
  category text not null check(category in ('booking','adjustments','bankPolosys','cash')),
  branch_id bigint not null references public.branches(id),
  branch_name text not null,
  employee_id text not null default '',
  employee_name text,
  voucher_type text not null check(voucher_type in ('MJV','CP')),
  lines jsonb not null,
  debit_total numeric(18,2) not null,
  credit_total numeric(18,2) not null,
  paid_from jsonb,
  voucher_date date,
  task_id uuid unique references public.assistant_workflow_tasks(id),
  task_created_at timestamptz,
  unique(batch_id,category,branch_id,employee_id),
  check(debit_total > 0 and debit_total = credit_total),
  check((category='cash' and voucher_type='CP' and employee_id<>'') or (category<>'cash' and voucher_type='MJV' and employee_id=''))
);
alter table public.salary_entry_batches enable row level security;
alter table public.salary_entry_vouchers enable row level security;
revoke all on public.salary_entry_batches,public.salary_entry_vouchers from public,anon,authenticated;
grant all on public.salary_entry_batches,public.salary_entry_vouchers to service_role;

create function public.lock_saved_salary_entries() returns trigger language plpgsql as $$
begin
  if tg_op='DELETE' or tg_table_name='salary_entry_batches' then raise exception 'Saved salary entries are locked.'; end if;
  if (to_jsonb(new)-'task_id'-'task_created_at'-'voucher_date') is distinct from (to_jsonb(old)-'task_id'-'task_created_at'-'voucher_date')
    or old.task_id is not null then raise exception 'Saved salary entries are locked.'; end if;
  if new.task_id is null or new.task_created_at is null then raise exception 'Only task assignment may update a saved voucher.'; end if;
  return new;
end;
$$;
create trigger lock_salary_entry_batches before update or delete on public.salary_entry_batches for each row execute function public.lock_saved_salary_entries();
create trigger lock_salary_entry_vouchers before update or delete on public.salary_entry_vouchers for each row execute function public.lock_saved_salary_entries();

create function public.get_saved_salary_entries(p_statement_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
begin
  if not public.salary_company_adjustment_can_access() then raise exception 'Salary Statement permission required.'; end if;
  return (select to_jsonb(b)||jsonb_build_object('vouchers',coalesce((select jsonb_agg(to_jsonb(v)||jsonb_build_object(
    'task_status',coalesce(t.status,'saved'),'assigned_user_name',u.username
  ) order by v.category,v.branch_name,v.employee_id) from public.salary_entry_vouchers v
  left join public.assistant_workflow_tasks t on t.id=v.task_id left join public.users u on u.id=t.assigned_to
  where v.batch_id=b.id),'[]'::jsonb)) from public.salary_entry_batches b where b.statement_id=p_statement_id);
end;
$$;

create function public.save_salary_entries(p_statement_id uuid,p_vouchers jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=public.aqura_current_user_id(); v_statement public.hr_salary_statements%rowtype;
  v_batch uuid; v_item jsonb; v_line jsonb; v_debit numeric; v_credit numeric; v_branch text;
begin
  if not public.salary_company_adjustment_can_access() then raise exception 'Salary Statement permission required.'; end if;
  select * into v_statement from public.hr_salary_statements where id=p_statement_id for update;
  if not found then raise exception 'Saved salary statement not found.'; end if;
  if exists(select 1 from public.salary_entry_batches where statement_id=p_statement_id) then raise exception 'Salary entries are already saved and locked.'; end if;
  if jsonb_typeof(p_vouchers) is distinct from 'array' or jsonb_array_length(p_vouchers)=0 then raise exception 'Generate all entries before saving.'; end if;
  insert into public.salary_entry_batches(statement_id,statement_end_date,source_snapshot_hash,created_by)
  values(p_statement_id,v_statement.end_date,md5(v_statement.data_json::text),v_actor) returning id into v_batch;
  for v_item in select value from jsonb_array_elements(p_vouchers) loop
    if coalesce(v_item->>'category','') not in ('booking','adjustments','bankPolosys','cash') then raise exception 'Vikin entries cannot be saved.'; end if;
    select b.name_en into v_branch from public.branches b join public.company_master c on c.id=b.company_id
      where b.id=(v_item->>'branch_id')::bigint and c.erp_provider='polosys';
    if not found then raise exception 'Only Polosys branch entries can be saved.'; end if;
    if jsonb_typeof(v_item->'lines') is distinct from 'array' or jsonb_array_length(v_item->'lines')<2 then raise exception 'Every voucher needs balanced lines.'; end if;
    v_debit:=0; v_credit:=0;
    for v_line in select value from jsonb_array_elements(v_item->'lines') loop
      if coalesce(v_line->>'side','') not in ('Debit','Credit') or nullif(btrim(v_line->>'ledger_name'),'') is null
        or nullif(btrim(v_line->>'narration'),'') is null or coalesce(v_line->>'amount','') !~ '^[0-9]+(\.[0-9]{1,2})?$'
        or (v_line->>'amount')::numeric<=0 or coalesce((v_line->>'placeholder')::boolean,false) then raise exception 'Invalid or placeholder salary voucher line.'; end if;
      if v_line->>'side'='Debit' then v_debit:=v_debit+(v_line->>'amount')::numeric; else v_credit:=v_credit+(v_line->>'amount')::numeric; end if;
    end loop;
    if v_debit<>v_credit then raise exception 'Every salary voucher must balance.'; end if;
    if v_item->>'category'='cash' then
      if jsonb_array_length(v_item->'lines')<>2 or not exists(select 1 from jsonb_array_elements(v_statement.data_json->'analysisData') r
        where r->>'employeeId'=v_item->>'employee_id' and r->>'employeeId'<>'EMP51' and (r->>'currentBranchId')::bigint=(v_item->>'branch_id')::bigint)
        or not exists(select 1 from public.erp_posting_ledger_links c where c.branch_id=(v_item->>'branch_id')::bigint and c.account_key='branch_cash'
          and c.ledger_name=v_item->'paid_from'->>'name' and exists(select 1 from jsonb_array_elements(v_item->'lines') l where l->>'side'='Credit' and l->>'ledger_name'=c.ledger_name))
      then raise exception 'Each CP must use its employee statement branch and configured cash account.'; end if;
    elsif coalesce(v_item->>'employee_id','')<>'' then raise exception 'MJVs must be grouped by category and branch.'; end if;
    insert into public.salary_entry_vouchers(batch_id,category,branch_id,branch_name,employee_id,employee_name,voucher_type,lines,debit_total,credit_total,paid_from,voucher_date)
    values(v_batch,v_item->>'category',(v_item->>'branch_id')::bigint,v_branch,coalesce(v_item->>'employee_id',''),v_item->>'employee_name',
      case when v_item->>'category'='cash' then 'CP' else 'MJV' end,v_item->'lines',v_debit,v_credit,
      case when v_item->>'category'='cash' then v_item->'paid_from' end,
      case when v_item->>'category' in ('booking','adjustments') then v_statement.end_date end);
  end loop;
  return public.get_saved_salary_entries(p_statement_id);
end;
$$;

create function public.post_salary_entry_tasks(p_batch_id uuid,p_category text,p_voucher_id uuid default null) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=public.aqura_current_user_id(); v_batch public.salary_entry_batches%rowtype;
  v_voucher public.salary_entry_vouchers%rowtype; v_assignee uuid; v_task uuid; v_payload jsonb; v_date date;
begin
  if not public.salary_company_adjustment_can_access() then raise exception 'Salary Statement permission required.'; end if;
  select * into v_batch from public.salary_entry_batches where id=p_batch_id for update;
  if not found then raise exception 'Save salary entries before posting tasks.'; end if;
  if p_category not in ('booking','adjustments','bankPolosys','cash') or (p_category='cash' and p_voucher_id is null)
    or (p_category<>'cash' and p_voucher_id is not null) then raise exception 'Choose a category or one saved CP.'; end if;
  if not exists(select 1 from public.salary_entry_vouchers where batch_id=p_batch_id and category=p_category and (p_voucher_id is null or id=p_voucher_id))
    then raise exception 'No saved entries for this selection.'; end if;
  for v_voucher in select * from public.salary_entry_vouchers where batch_id=p_batch_id and category=p_category
    and (p_voucher_id is null or id=p_voucher_id) and task_id is null order by branch_id,id for update loop
    select d.entry_task_user_id into v_assignee from public.branch_default_positions d join public.users u on u.id=d.entry_task_user_id and u.status='active'
      where d.branch_id=v_voucher.branch_id and exists(select 1 from public.hr_employee_master e
      where e.user_id=d.entry_task_user_id and e.current_branch_id=v_voucher.branch_id and not e.is_removed);
    if v_assignee is null then raise exception 'No active Entry Task user is configured for %.',v_voucher.branch_name; end if;
    v_date:=case when p_category='bankPolosys' then (now() at time zone 'Asia/Riyadh')::date when p_category<>'cash' then v_batch.statement_end_date end;
    v_payload:=jsonb_build_object('version',1,'salary_entry_voucher_id',v_voucher.id,'salary_statement_id',v_batch.statement_id,
      'salary_category',p_category,'branch_name',v_voucher.branch_name,'statement_date',v_batch.statement_end_date,'posting_date',v_date,'lines',v_voucher.lines);
    if p_category='cash' then
      select v_payload||jsonb_build_object('ledger_name',l->>'ledger_name','amount',l->>'amount','narration',l->>'narration',
        'cash_account',v_voucher.paid_from->>'name','employee_id',v_voucher.employee_id) into v_payload
        from jsonb_array_elements(v_voucher.lines) l where l->>'side'='Debit';
    end if;
    insert into public.assistant_workflow_tasks(task_type,title,branch_id,assigned_to,created_by,payload,source_record_id,workflow_key)
    values(case when p_category='cash' then 'salary_cash_payment' else 'cash_closing_mjv' end,
      'Salary '||p_category||' - '||v_voucher.branch_name||case when p_category='cash' then ' - '||v_voucher.employee_name else '' end,
      v_voucher.branch_id,v_assignee,v_actor,v_payload,v_voucher.id,'salary-entry:'||v_voucher.id) returning id into v_task;
    update public.salary_entry_vouchers set task_id=v_task,task_created_at=now(),voucher_date=v_date where id=v_voucher.id;
  end loop;
  return public.get_saved_salary_entries(v_batch.statement_id);
end;
$$;

create function public.lock_salary_posted_task() returns trigger language plpgsql as $$
begin
  if old.payload ? 'salary_entry_voucher_id' then
    if tg_op='DELETE' then raise exception 'Salary posting tasks are locked.'; end if;
    if new.payload is distinct from old.payload or new.branch_id<>old.branch_id or new.assigned_to<>old.assigned_to
      or (old.status='completed' and new.status<>'completed') then raise exception 'Salary posting tasks are locked.'; end if;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
create trigger lock_salary_posted_task before update or delete on public.assistant_workflow_tasks for each row execute function public.lock_salary_posted_task();
revoke all on function public.get_saved_salary_entries(uuid),public.save_salary_entries(uuid,jsonb),public.post_salary_entry_tasks(uuid,text,uuid) from public,anon;
grant execute on function public.get_saved_salary_entries(uuid),public.save_salary_entries(uuid,jsonb),public.post_salary_entry_tasks(uuid,text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
