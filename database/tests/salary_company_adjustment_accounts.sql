begin;
do $$
declare
  v_company bigint;
  v_branch bigint;
  v_wrong_branch bigint;
  v_pol_company bigint;
  v_actor uuid;
  v_result jsonb;
begin
  perform set_config('request.jwt.claims','{}',true);
  if public.salary_company_adjustment_can_access() then raise exception 'Unauthenticated adjustment access must be denied'; end if;
  select e.sponsor_id into strict v_company from public.hr_employee_master e where e.id = 'EMP15';
  v_branch := 3;
  insert into public.salary_company_adjustment_accounts(company_id,branch_id,erp_ledger_id,ledger_code,ledger_name)
  values(v_company,v_branch,1,'test','Temporary sponsor adjustment')
  on conflict(company_id,branch_id) do update set ledger_code = excluded.ledger_code, ledger_name = excluded.ledger_name;
  insert into public.salary_company_adjustment_accounts(company_id,branch_id,erp_ledger_id,ledger_code,ledger_name)
  values(v_company,v_branch,2,'replacement','Replacement sponsor adjustment')
  on conflict(company_id,branch_id) do update set ledger_code = excluded.ledger_code, ledger_name = excluded.ledger_name;
  select id into strict v_actor from public.users where status = 'active' and is_master_admin limit 1;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor)::text,true);
  if not public.salary_company_adjustment_can_access() then raise exception 'Master admin adjustment access required'; end if;
  v_result := public.get_salary_payment_preview_accounts('EMP15',v_branch);
  if v_result->'sponsor_adjustment'->>'ledger_code' is distinct from 'replacement'
    or (v_result->'sponsor_adjustment'->>'branch_id')::bigint is distinct from v_branch then
    raise exception 'Preview must return the selected sponsor and branch ledger';
  end if;
  v_result := public.get_salary_payment_preview_accounts('EMP3',v_branch);
  if v_result->'sponsor_adjustment' <> 'null'::jsonb then
    raise exception 'Another sponsor must not receive this mapping';
  end if;
  select id into strict v_pol_company from public.company_master where erp_provider = 'polosys' limit 1;
  begin
    insert into public.salary_company_adjustment_accounts values(v_pol_company,v_branch,1,'bad','Invalid sponsor',now());
    raise exception 'Expected sponsor validation';
  exception when raise_exception then
    if sqlerrm <> 'Select a Vikin sponsor and an active Polosys ERP branch' then raise; end if;
  end;
  select b.id into strict v_wrong_branch from public.branches b join public.company_master c on c.id=b.company_id
    where c.erp_provider='vikin' limit 1;
  begin
    insert into public.salary_company_adjustment_accounts values(v_company,v_wrong_branch,1,'bad','Invalid branch',now());
    raise exception 'Expected branch validation';
  exception when raise_exception then
    if sqlerrm <> 'Select a Vikin sponsor and an active Polosys ERP branch' then raise; end if;
  end;
end;
$$;
rollback;
