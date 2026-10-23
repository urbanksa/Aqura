begin;

-- Preserve existing selections. Do not guess which bank to keep if duplicates exist.
do $$
begin
  if exists (
    select company_id from public.salary_sponsor_bank_accounts
    group by company_id having count(*) > 1
  ) then
    raise exception 'Multiple salary bank accounts exist for a company; select the account to retain before applying this migration';
  end if;
end;
$$;

alter table public.salary_sponsor_bank_accounts
  add constraint salary_sponsor_bank_accounts_company_id_key unique (company_id);
alter table public.salary_sponsor_bank_accounts
  drop constraint salary_sponsor_bank_accounts_company_id_branch_id_key;

notify pgrst, 'reload schema';
commit;
