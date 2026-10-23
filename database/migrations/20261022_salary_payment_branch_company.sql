begin;

-- Route salary payments through the statement branch company, independently of the employee sponsor ERP.
create or replace function public.get_salary_payment_preview_accounts(p_employee_id text, p_branch_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_actor uuid := public.aqura_current_user_id();
  v_company bigint;
  v_provider text;
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
  select * into v_bank from public.salary_sponsor_bank_accounts where company_id = v_company;
  return jsonb_build_object(
    'provider', v_provider,
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
