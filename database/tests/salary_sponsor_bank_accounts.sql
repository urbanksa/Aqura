-- All temporary bank links and provider changes are rolled back.
begin;
do $$
declare
  v_company bigint;
  v_branch bigint;
  v_other_company bigint;
begin
  select c.id, b.id into strict v_company, v_branch
  from public.company_master c join public.branches b on b.company_id = c.id
  where c.erp_provider = 'polosys' and b.is_active = true
  order by c.id, b.id limit 1;

  insert into public.salary_sponsor_bank_accounts(company_id, branch_id, erp_ledger_id, ledger_code, ledger_name)
  values(v_company, v_branch, 1, 'test', 'Temporary test bank')
  on conflict(company_id) do update set branch_id = excluded.branch_id, ledger_name = excluded.ledger_name;

  insert into public.salary_sponsor_bank_accounts(company_id, branch_id, erp_ledger_id, ledger_code, ledger_name)
  values(v_company, v_branch, 2, 'replacement', 'Replacement test bank')
  on conflict(company_id) do update set branch_id = excluded.branch_id,
    erp_ledger_id = excluded.erp_ledger_id, ledger_code = excluded.ledger_code, ledger_name = excluded.ledger_name;
  if (select count(*) from public.salary_sponsor_bank_accounts where company_id = v_company) <> 1 then
    raise exception 'Company must have exactly one salary bank account';
  end if;
  if (select ledger_code from public.salary_sponsor_bank_accounts where company_id = v_company) <> 'replacement' then
    raise exception 'Replacing the salary bank account failed';
  end if;

  select id into strict v_other_company from public.company_master where id <> v_company order by id limit 1;
  begin
    insert into public.salary_sponsor_bank_accounts(company_id, branch_id, erp_ledger_id, ledger_code, ledger_name)
    values(v_other_company, v_branch, 1, 'test', 'Wrong company bank');
    raise exception 'Expected company/branch validation';
  exception when raise_exception then
    if sqlerrm <> 'Select an active branch belonging to this Polosys company' then raise; end if;
  end;

  update public.company_master set erp_provider = 'vikin' where id = v_company;
  begin
    update public.salary_sponsor_bank_accounts set ledger_name = 'Not allowed for Vikin'
    where company_id = v_company and branch_id = v_branch;
    raise exception 'Expected provider validation';
  exception when raise_exception then
    if sqlerrm <> 'Select an active branch belonging to this Polosys company' then raise; end if;
  end;

  raise notice 'Sponsor bank company/branch and Polosys-only validation passed';
end;
$$;
rollback;
