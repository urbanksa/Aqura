begin;
-- Historical statement participants remain available for payroll previews even
-- after removal. This does not change employee-master RLS or normal HR lists.
create function public.get_saved_salary_employee_context(p_statement_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.salary_company_adjustment_can_access() then
    raise exception 'Salary Statement permission required.';
  end if;
  if not exists(select 1 from public.hr_salary_statements where id = p_statement_id) then
    raise exception 'Saved salary statement not found.';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', e.id, 'name_en', e.name_en, 'name_ar', e.name_ar, 'id_number', e.id_number,
    'sponsor_id', e.sponsor_id, 'erp_employee_id_mapping', e.erp_employee_id_mapping,
    'sponsor_name_en', c.name_en, 'sponsor_name_ar', c.name_ar
  ) order by e.id)
  from public.hr_employee_master e left join public.company_master c on c.id = e.sponsor_id
  where e.id in (
    select r->>'employeeId' from public.hr_salary_statements s
    cross join lateral jsonb_array_elements(s.data_json->'analysisData') r
    where s.id = p_statement_id
  )), '[]'::jsonb);
end;
$$;
revoke all on function public.get_saved_salary_employee_context(uuid) from public,anon;
grant execute on function public.get_saved_salary_employee_context(uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
