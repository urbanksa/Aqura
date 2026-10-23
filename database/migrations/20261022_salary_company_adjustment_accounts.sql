begin;
create table public.salary_company_adjustment_accounts (
  company_id bigint not null references public.company_master(id) on delete cascade,
  branch_id bigint not null references public.branches(id) on delete cascade,
  erp_ledger_id bigint not null check (erp_ledger_id > 0),
  ledger_code text not null,
  ledger_name text not null check (length(btrim(ledger_name)) > 0),
  updated_at timestamptz not null default now(),
  primary key(company_id, branch_id)
);
create function public.validate_salary_company_adjustment_account()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from public.company_master where id = new.company_id and erp_provider = 'vikin')
    or not exists(select 1 from public.branches b join public.company_master c on c.id = b.company_id
      where b.id = new.branch_id and b.is_active and c.erp_provider = 'polosys'
        and exists(select 1 from public.erp_connections e where e.branch_id = b.id and e.is_active)) then
    raise exception 'Select a Vikin sponsor and an active Polosys ERP branch';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_salary_company_adjustment_account() from public;
create trigger validate_salary_company_adjustment_account before insert or update
on public.salary_company_adjustment_accounts for each row execute function public.validate_salary_company_adjustment_account();
alter table public.salary_company_adjustment_accounts enable row level security;
create function public.salary_company_adjustment_can_access()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.users u where u.id = public.aqura_current_user_id() and u.status = 'active'
    and (coalesce(u.is_master_admin,false) or exists(select 1 from public.button_permissions bp
      where bp.user_id=u.id and bp.button_code='SALARY_STATEMENT' and bp.is_enabled)));
$$;
revoke all on function public.salary_company_adjustment_can_access() from public,anon;
grant execute on function public.salary_company_adjustment_can_access() to authenticated;
create policy "Salary permission company adjustment access" on public.salary_company_adjustment_accounts
  for all to authenticated using (public.salary_company_adjustment_can_access())
  with check (public.salary_company_adjustment_can_access());
grant select, insert, update on public.salary_company_adjustment_accounts to authenticated;
grant all on public.salary_company_adjustment_accounts to service_role;
create or replace function public.get_salary_payment_preview_accounts(p_employee_id text, p_branch_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_actor uuid := public.aqura_current_user_id();
  v_company bigint;
  v_provider text;
  v_sponsor_provider text;
  v_sponsor_name text;
  v_sponsor_name_ar text;
  v_bank public.salary_sponsor_bank_accounts%rowtype;
begin
  if not exists (
    select 1 from public.users u where u.id = v_actor and u.status = 'active'
      and (coalesce(u.is_master_admin, false) or exists (
        select 1 from public.button_permissions bp
        where bp.user_id = u.id and bp.button_code = 'SALARY_STATEMENT' and bp.is_enabled
      ))
  ) then raise exception 'Salary Statement permission required.'; end if;

  select b.company_id, c.erp_provider into v_company, v_provider
  from public.branches b join public.company_master c on c.id = b.company_id
  where b.id = p_branch_id
    and exists (select 1 from public.hr_employee_master e where e.id = p_employee_id and e.sponsor_id is not null);
  if v_provider is distinct from 'polosys' then
    return jsonb_build_object('provider', v_provider);
  end if;
  select c.erp_provider, coalesce(c.name_en, c.name_ar), c.name_ar
  into v_sponsor_provider, v_sponsor_name, v_sponsor_name_ar
  from public.hr_employee_master e join public.company_master c on c.id = e.sponsor_id
  where e.id = p_employee_id;
  select * into v_bank from public.salary_sponsor_bank_accounts where company_id = v_company;
  return jsonb_build_object(
    'provider', v_provider,
    'sponsor_provider', v_sponsor_provider,
    'sponsor_name', v_sponsor_name,
    'sponsor_name_ar', v_sponsor_name_ar,
    'sponsor_adjustment', (select jsonb_build_object('company_id', a.company_id, 'branch_id', a.branch_id,
      'ledger_name', a.ledger_name, 'ledger_code', a.ledger_code)
      from public.salary_company_adjustment_accounts a join public.hr_employee_master e on e.sponsor_id = a.company_id
      where e.id = p_employee_id and a.branch_id = p_branch_id),
    'bank', (select jsonb_build_object('branch_id', v_bank.branch_id, 'branch_name', coalesce(b.name_en, b.name_ar),
      'ledger_name', v_bank.ledger_name, 'ledger_code', v_bank.ledger_code)
      from public.branches b where b.id = v_bank.branch_id),
    'cross_branch_accounts', coalesce((select jsonb_agg(jsonb_build_object(
      'source_branch_id', d.source_branch_id, 'target_branch_id', d.target_branch_id,
      'ledger_name', d.target_ledger_name)) from public.default_accounts_other_branches d
      where (d.source_branch_id = v_bank.branch_id and d.target_branch_id = p_branch_id)
         or (d.source_branch_id = p_branch_id and d.target_branch_id = v_bank.branch_id)), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_salary_payment_preview_accounts(text,bigint) from public,anon;
grant execute on function public.get_salary_payment_preview_accounts(text,bigint) to authenticated;
notify pgrst, 'reload schema';
commit;
