begin;

create table public.salary_sponsor_bank_accounts (
  id uuid primary key default gen_random_uuid(),
  company_id bigint not null references public.company_master(id) on delete cascade,
  branch_id bigint not null references public.branches(id) on delete cascade,
  erp_ledger_id bigint not null check (erp_ledger_id > 0),
  ledger_code text not null,
  ledger_name text not null check (length(btrim(ledger_name)) > 0),
  updated_at timestamptz not null default now(),
  unique (company_id, branch_id)
);

create function public.validate_salary_sponsor_bank_account()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if not exists (
    select 1 from public.company_master c join public.branches b on b.company_id = c.id
    where c.id = new.company_id and b.id = new.branch_id
      and c.erp_provider = 'polosys' and b.is_active = true
  ) then
    raise exception 'Select an active branch belonging to this Polosys company';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_salary_sponsor_bank_account() from public;
create trigger validate_salary_sponsor_bank_account
before insert or update on public.salary_sponsor_bank_accounts
for each row execute function public.validate_salary_sponsor_bank_account();

alter table public.salary_sponsor_bank_accounts enable row level security;
create policy "Authenticated salary sponsor bank access"
  on public.salary_sponsor_bank_accounts for all to authenticated using (true) with check (true);
grant select, insert, update on public.salary_sponsor_bank_accounts to authenticated;
grant all on public.salary_sponsor_bank_accounts to service_role;

notify pgrst, 'reload schema';
commit;
