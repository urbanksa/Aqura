begin;

alter table public.salary_deduction_posting_accounts
    drop constraint salary_deduction_posting_accounts_deduction_key_check;

alter table public.salary_deduction_posting_accounts
    add constraint salary_deduction_posting_accounts_deduction_key_check
    check (deduction_key in (
        'gosiDeduction', 'lateDeductions', 'underWorkedDeductions',
        'incompleteDeductions', 'unapprovedLeaveDeductions',
        'penaltiesDeductions', 'otherDeductions', 'foodAllowanceDeduction',
        'mainSalaryAccount'
    ));

commit;
