begin;

create table public.salary_vikin_branch_adjustment_accounts (
  company_id bigint not null references public.company_master(id) on delete restrict,
  branch_id bigint not null references public.branches(id) on delete restrict,
  ledger_id uuid not null,
  updated_at timestamptz not null default now(),
  updated_by uuid not null references public.users(id),
  primary key (company_id, branch_id),
  foreign key (ledger_id, company_id) references public.vikin_ledgers(id, company_id) on delete restrict
);
create table public.salary_vikin_bank_accounts (
  company_id bigint primary key references public.company_master(id) on delete restrict,
  ledger_id uuid not null,
  updated_at timestamptz not null default now(),
  updated_by uuid not null references public.users(id),
  foreign key (ledger_id, company_id) references public.vikin_ledgers(id, company_id) on delete restrict
);
alter table public.salary_vikin_branch_adjustment_accounts enable row level security;
alter table public.salary_vikin_bank_accounts enable row level security;
revoke all on public.salary_vikin_branch_adjustment_accounts, public.salary_vikin_bank_accounts from public, anon, authenticated;
grant all on public.salary_vikin_branch_adjustment_accounts, public.salary_vikin_bank_accounts to service_role;

create function public.get_salary_vikin_ledger_accounts()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.salary_company_adjustment_can_access() then
    raise exception 'Salary Statement permission required.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'companies', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name_en', name_en, 'name_ar', name_ar) order by name_en, id)
      from public.company_master where erp_provider = 'vikin'), '[]'::jsonb),
    'branches', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name_en', name_en, 'name_ar', name_ar) order by name_en, id)
      from public.branches where is_active), '[]'::jsonb),
    'ledgers', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'company_id', l.company_id,
      'ledger_name', l.ledger_name, 'ledger_code', l.ledger_code, 'account_group_name', l.account_group_name) order by l.ledger_name, l.ledger_code)
      from public.vikin_ledgers l join public.company_master c on c.id = l.company_id where c.erp_provider = 'vikin'), '[]'::jsonb),
    'adjustments', coalesce((select jsonb_agg(jsonb_build_object('company_id', a.company_id, 'branch_id', a.branch_id,
      'ledger_id', l.id, 'ledger_name', l.ledger_name, 'ledger_code', l.ledger_code) order by a.company_id, a.branch_id)
      from public.salary_vikin_branch_adjustment_accounts a join public.vikin_ledgers l on l.id = a.ledger_id and l.company_id = a.company_id
      join public.company_master c on c.id = a.company_id where c.erp_provider = 'vikin'), '[]'::jsonb),
    'banks', coalesce((select jsonb_agg(jsonb_build_object('company_id', a.company_id,
      'ledger_id', l.id, 'ledger_name', l.ledger_name, 'ledger_code', l.ledger_code) order by a.company_id)
      from public.salary_vikin_bank_accounts a join public.vikin_ledgers l on l.id = a.ledger_id and l.company_id = a.company_id
      join public.company_master c on c.id = a.company_id where c.erp_provider = 'vikin'), '[]'::jsonb)
  );
end;
$$;

create function public.set_salary_vikin_ledger_account(p_kind text, p_company_id bigint, p_branch_id bigint, p_ledger_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_ledger public.vikin_ledgers%rowtype;
  v_actor uuid := public.aqura_current_user_id();
begin
  if not public.salary_company_adjustment_can_access() then
    raise exception 'Salary Statement permission required.' using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('adjustment', 'bank') then
    raise exception 'Select branch adjustment or salary bank account.' using errcode = '22023';
  end if;
  perform 1 from public.company_master where id = p_company_id and erp_provider = 'vikin' for share;
  if not found then raise exception 'Select a company linked to Vikin.' using errcode = '22023'; end if;
  select * into v_ledger from public.vikin_ledgers where id = p_ledger_id and company_id = p_company_id for share;
  if not found then raise exception 'Select a synced ledger from the selected Vikin company.' using errcode = '22023'; end if;
  if p_kind = 'adjustment' then
    perform 1 from public.branches where id = p_branch_id and is_active for share;
    if not found then raise exception 'Select an active statement branch.' using errcode = '22023'; end if;
    insert into public.salary_vikin_branch_adjustment_accounts(company_id, branch_id, ledger_id, updated_by)
    values (p_company_id, p_branch_id, p_ledger_id, v_actor)
    on conflict (company_id, branch_id) do update set ledger_id = excluded.ledger_id, updated_at = clock_timestamp(), updated_by = v_actor;
  else
    if p_branch_id is not null then raise exception 'Vikin salary bank accounts are linked per company.' using errcode = '22023'; end if;
    if lower(btrim(v_ledger.account_group_name)) !~ '(^|\s)banks?(\s|$)|بنك|بنوك' then
      raise exception 'Select a Vikin bank ledger.' using errcode = '22023';
    end if;
    insert into public.salary_vikin_bank_accounts(company_id, ledger_id, updated_by)
    values (p_company_id, p_ledger_id, v_actor)
    on conflict (company_id) do update set ledger_id = excluded.ledger_id, updated_at = clock_timestamp(), updated_by = v_actor;
  end if;
  return public.get_salary_vikin_ledger_accounts();
end;
$$;
revoke all on function public.get_salary_vikin_ledger_accounts() from public, anon;
revoke all on function public.set_salary_vikin_ledger_account(text,bigint,bigint,uuid) from public, anon;
grant execute on function public.get_salary_vikin_ledger_accounts() to authenticated;
grant execute on function public.set_salary_vikin_ledger_account(text,bigint,bigint,uuid) to authenticated;

create or replace function public.get_salary_payment_preview_accounts(p_employee_id text, p_branch_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_company bigint;
  v_provider text;
  v_sponsor_provider text;
  v_sponsor_name text;
  v_sponsor_name_ar text;
  v_sponsor_id bigint;
  v_context jsonb;
  v_bank public.salary_sponsor_bank_accounts%rowtype;
begin
  if not public.salary_company_adjustment_can_access() then
    raise exception 'Salary Statement permission required.' using errcode = '42501';
  end if;
  select b.company_id, c.erp_provider into v_company, v_provider
  from public.branches b join public.company_master c on c.id = b.company_id
  where b.id = p_branch_id
    and exists (select 1 from public.hr_employee_master e where e.id = p_employee_id and e.sponsor_id is not null);
  select c.id, c.erp_provider, coalesce(c.name_en, c.name_ar), c.name_ar
  into v_sponsor_id, v_sponsor_provider, v_sponsor_name, v_sponsor_name_ar
  from public.hr_employee_master e join public.company_master c on c.id = e.sponsor_id
  where e.id = p_employee_id;
  v_context := jsonb_build_object(
    'provider', v_provider, 'sponsor_provider', v_sponsor_provider, 'sponsor_name', v_sponsor_name, 'sponsor_name_ar', v_sponsor_name_ar,
    'vikin_employee_ledger', (select jsonb_build_object('employee_id', p_employee_id, 'ledger_name', l.ledger_name, 'ledger_code', l.ledger_code)
      from public.vikin_employee_ledger_links saved join public.vikin_ledgers l on l.id = saved.vikin_ledger_id and l.company_id = saved.company_id
      where saved.employee_id = p_employee_id and saved.company_id = v_sponsor_id and v_sponsor_provider = 'vikin'),
    'vikin_branch_adjustment', (select jsonb_build_object('branch_id', a.branch_id, 'ledger_name', l.ledger_name, 'ledger_code', l.ledger_code)
      from public.salary_vikin_branch_adjustment_accounts a join public.vikin_ledgers l on l.id = a.ledger_id and l.company_id = a.company_id
      where a.company_id = v_sponsor_id and a.branch_id = p_branch_id and v_sponsor_provider = 'vikin'),
    'vikin_bank', (select jsonb_build_object('ledger_name', l.ledger_name, 'ledger_code', l.ledger_code)
      from public.salary_vikin_bank_accounts a join public.vikin_ledgers l on l.id = a.ledger_id and l.company_id = a.company_id
      where a.company_id = v_sponsor_id and v_sponsor_provider = 'vikin')
  );
  if v_provider is distinct from 'polosys' then return v_context; end if;
  select * into v_bank from public.salary_sponsor_bank_accounts where company_id = v_company;
  return v_context || jsonb_build_object(
    'sponsor_adjustment', (select jsonb_build_object('company_id', a.company_id, 'branch_id', a.branch_id,
      'ledger_name', a.ledger_name, 'ledger_code', a.ledger_code)
      from public.salary_company_adjustment_accounts a where a.company_id = v_sponsor_id and a.branch_id = p_branch_id),
    'bank', (select jsonb_build_object('branch_id', v_bank.branch_id, 'branch_name', coalesce(b.name_en, b.name_ar),
      'ledger_name', v_bank.ledger_name, 'ledger_code', v_bank.ledger_code) from public.branches b where b.id = v_bank.branch_id),
    'cross_branch_accounts', coalesce((select jsonb_agg(jsonb_build_object(
      'source_branch_id', d.source_branch_id, 'target_branch_id', d.target_branch_id, 'ledger_name', d.target_ledger_name))
      from public.default_accounts_other_branches d where (d.source_branch_id = v_bank.branch_id and d.target_branch_id = p_branch_id)
         or (d.source_branch_id = p_branch_id and d.target_branch_id = v_bank.branch_id)), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_salary_payment_preview_accounts(text,bigint) from public, anon;
grant execute on function public.get_salary_payment_preview_accounts(text,bigint) to authenticated;
notify pgrst, 'reload schema';
commit;
