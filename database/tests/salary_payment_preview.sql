begin;
do $$
declare
  v_actor uuid;
  v_employee record;
  v_result jsonb;
  v_bank_branch bigint;
  v_branch bigint;
  v_branch_company bigint;
  v_expected_provider text;
begin
  perform set_config('request.jwt.claims', '{}', true);
  begin
    perform public.get_salary_payment_preview_accounts('EMP3', 1);
    raise exception 'Expected denied salary access';
  exception when raise_exception then
    if sqlerrm <> 'Salary Statement permission required.' then raise; end if;
  end;
  if has_function_privilege('anon', 'public.get_salary_payment_preview_accounts(text,bigint)', 'execute') then
    raise exception 'Anonymous access must be denied';
  end if;
  select id into strict v_actor from public.users where status = 'active' and is_master_admin limit 1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub',v_actor)::text, true);
  select b.id, b.company_id, c.erp_provider into strict v_branch, v_branch_company, v_expected_provider
  from public.branches b join public.company_master c on c.id = b.company_id
  where b.is_active and c.erp_provider = 'polosys' order by b.id limit 1;
  for v_employee in select e.id, e.sponsor_id, c.erp_provider from public.hr_employee_master e
    left join public.company_master c on c.id = e.sponsor_id
  loop
    v_result := public.get_salary_payment_preview_accounts(v_employee.id, v_branch);
    if (v_result->>'provider') is distinct from (case when v_employee.sponsor_id is null then null else v_expected_provider end) then
      raise exception 'Provider must come from the statement branch company for sponsored employees';
    end if;
    if v_employee.sponsor_id is null then
      if v_result ? 'bank' or v_result ? 'cross_branch_accounts' then
        raise exception 'Non-sponsored employees must not receive these payment accounts';
      end if;
    else
      select branch_id into v_bank_branch from public.salary_sponsor_bank_accounts where company_id = v_branch_company;
      if (v_result->'bank'->>'branch_id')::bigint is distinct from v_bank_branch then
        raise exception 'Bank must belong to the statement branch company';
      end if;
      if exists(select 1 from jsonb_array_elements(v_result->'cross_branch_accounts') a where not (
        ((a->>'source_branch_id')::bigint = v_bank_branch and (a->>'target_branch_id')::bigint = v_branch)
        or ((a->>'source_branch_id')::bigint = v_branch and (a->>'target_branch_id')::bigint = v_bank_branch)
      )) then raise exception 'Unrelated branch account returned'; end if;
    end if;
  end loop;
  -- Regression: EMP15 has a Vikin sponsor but works in a Polosys branch.
  v_result := public.get_salary_payment_preview_accounts('EMP15', 3);
  if v_result->>'provider' <> 'polosys' or (v_result->'bank'->>'branch_id')::bigint <> 1
    or jsonb_array_length(v_result->'cross_branch_accounts') <> 2 then
    raise exception 'EMP15 must receive the Polosys bank and both reciprocal accounts';
  end if;
  if v_result->>'sponsor_provider' is distinct from 'vikin' or nullif(v_result->>'sponsor_name', '') is null then
    raise exception 'EMP15 must receive Vikin sponsor metadata for the credit placeholder';
  end if;
  -- A Vikin statement branch must not receive Polosys payment previews.
  select b.id into v_branch from public.branches b join public.company_master c on c.id = b.company_id
  where c.erp_provider = 'vikin' limit 1;
  if v_branch is not null then
    v_result := public.get_salary_payment_preview_accounts('EMP15', v_branch);
    if v_result->>'provider' <> 'vikin' or v_result ? 'bank' then
      raise exception 'Vikin branch must not receive Polosys bank accounts';
    end if;
  end if;
end;
$$;
rollback;
