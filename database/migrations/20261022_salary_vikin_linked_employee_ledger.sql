begin;

-- Salary previews read the current employee's Vikin link using salary access,
-- without granting access to Link ID editing or the full Vikin catalogue.
create or replace function public.get_salary_payment_preview_accounts(p_employee_id text, p_branch_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_actor uuid := public.aqura_current_user_id();
  v_company bigint;
  v_provider text;
  v_sponsor_provider text;
  v_sponsor_name text;
  v_sponsor_name_ar text;
  v_context jsonb;
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

  select c.erp_provider, coalesce(c.name_en, c.name_ar), c.name_ar
  into v_sponsor_provider, v_sponsor_name, v_sponsor_name_ar
  from public.hr_employee_master e join public.company_master c on c.id = e.sponsor_id
  where e.id = p_employee_id;

  v_context := jsonb_build_object(
    'provider', v_provider,
    'sponsor_provider', v_sponsor_provider,
    'sponsor_name', v_sponsor_name,
    'sponsor_name_ar', v_sponsor_name_ar,
    'vikin_employee_ledger', (
      select jsonb_build_object('employee_id', e.id, 'ledger_name', l.ledger_name, 'ledger_code', l.ledger_code)
      from public.hr_employee_master e
      join public.company_master c on c.id = e.sponsor_id and c.erp_provider = 'vikin'
      join public.vikin_employee_ledger_links saved on saved.employee_id = e.id and saved.company_id = c.id
      join public.vikin_ledgers l on l.id = saved.vikin_ledger_id and l.company_id = saved.company_id
      where e.id = p_employee_id
    )
  );
  if v_provider is distinct from 'polosys' then return v_context; end if;

  select * into v_bank from public.salary_sponsor_bank_accounts where company_id = v_company;
  return v_context || jsonb_build_object(
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
