begin;
do $$
declare v_actor uuid; v_statement uuid;
begin
  perform set_config('request.jwt.claims','{}',true);
  begin
    perform public.get_saved_salary_employee_context('00000000-0000-0000-0000-000000000000');
    raise exception 'Expected salary permission denial';
  exception when raise_exception then
    if sqlerrm <> 'Salary Statement permission required.' then raise; end if;
  end;
  if has_function_privilege('anon','public.get_saved_salary_employee_context(uuid)','execute') then
    raise exception 'Anonymous historical access must be denied';
  end if;
  select id into strict v_actor from public.users where status='active' and is_master_admin limit 1;
  select s.id into strict v_statement from public.hr_salary_statements s
  where exists(select 1 from jsonb_array_elements(s.data_json->'analysisData') r where r->>'employeeId'='EMP23')
  order by s.updated_at desc limit 1;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor)::text,true);
  perform set_config('aqura.test_statement_id',v_statement::text,true);
end;
$$;
set local role authenticated;
do $$
declare v_employees jsonb; v_employee jsonb; v_snapshot jsonb;
begin
  v_employees := public.get_saved_salary_employee_context(current_setting('aqura.test_statement_id')::uuid);
  select value into v_employee from jsonb_array_elements(v_employees) where value->>'id'='EMP23';
  if v_employee->>'name_en' is distinct from 'Rashad' or v_employee->>'sponsor_id' is not null then
    raise exception 'EMP23 historical name and no-sponsorship context must load';
  end if;
  if exists(select 1 from public.hr_employee_master where id='EMP23') then
    raise exception 'Normal employee lists must still hide removed EMP23';
  end if;
  select data_json into strict v_snapshot from public.hr_salary_statements where id=current_setting('aqura.test_statement_id')::uuid;
  if exists(select 1 from jsonb_array_elements(v_employees) e where not exists(
    select 1 from jsonb_array_elements(v_snapshot->'analysisData') r where r->>'employeeId'=e->>'id'
  )) then raise exception 'Historical context must be limited to statement participants'; end if;
end;
$$;
rollback;
