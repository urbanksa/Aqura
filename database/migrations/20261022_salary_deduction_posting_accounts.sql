begin;

create table if not exists public.salary_deduction_posting_accounts (
    id uuid primary key default gen_random_uuid(),
    branch_id bigint not null references public.branches(id) on delete cascade,
    deduction_key text not null check (deduction_key in (
        'gosiDeduction', 'lateDeductions', 'underWorkedDeductions',
        'incompleteDeductions', 'unapprovedLeaveDeductions',
        'penaltiesDeductions', 'otherDeductions', 'foodAllowanceDeduction'
    )),
    erp_ledger_id bigint not null check (erp_ledger_id > 0),
    ledger_code text not null,
    ledger_name text not null,
    updated_at timestamptz not null default now(),
    unique (branch_id, deduction_key)
);

alter table public.salary_deduction_posting_accounts enable row level security;
create policy "Authenticated salary posting account access"
    on public.salary_deduction_posting_accounts for all to authenticated
    using (true) with check (true);
grant select, insert, update on public.salary_deduction_posting_accounts to authenticated;
grant all on public.salary_deduction_posting_accounts to service_role;

commit;
