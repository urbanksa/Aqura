begin;

create or replace function public.process_boarding_transfer_claims(
  p_employee_id text,
  p_source_branch_id bigint
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := public.aqura_current_user_id();
  v_claim_count integer := 0;
  v_now text := to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
begin
  if v_actor is null or not exists (
    select 1
    from public.users u
    where u.id = v_actor
      and u.status = 'active'
      and (
        coalesce(u.is_master_admin, false)
        or exists (
          select 1
          from public.button_permissions bp
          where bp.user_id = u.id
            and bp.button_code = 'EMPLOYEE_MASTER'
            and bp.is_enabled = true
        )
      )
  ) then
    raise exception 'Employee Master permission required';
  end if;

  if coalesce(trim(p_employee_id), '') = '' or p_source_branch_id is null then
    raise exception 'Employee and source branch are required';
  end if;

  select count(*)::integer
  into v_claim_count
  from public.erp_synced_products p,
       jsonb_array_elements(coalesce(p.managed_by, '[]'::jsonb)) entry
  where entry->>'employee_id' = p_employee_id
    and entry->>'branch_id' = p_source_branch_id::text;

  if v_claim_count > 0 then
    update public.erp_synced_products p
    set in_process = coalesce(p.in_process, '[]'::jsonb) || (
      select coalesce(jsonb_agg(
        entry.elem || jsonb_build_object('moved_at', v_now)
        order by entry.ordinality
      ), '[]'::jsonb)
      from jsonb_array_elements(coalesce(p.managed_by, '[]'::jsonb))
        with ordinality entry(elem, ordinality)
      where entry.elem->>'employee_id' = p_employee_id
        and entry.elem->>'branch_id' = p_source_branch_id::text
    ),
    managed_by = (
      select coalesce(jsonb_agg(entry.elem order by entry.ordinality), '[]'::jsonb)
      from jsonb_array_elements(coalesce(p.managed_by, '[]'::jsonb))
        with ordinality entry(elem, ordinality)
      where not (
        entry.elem->>'employee_id' = p_employee_id
        and entry.elem->>'branch_id' = p_source_branch_id::text
      )
    )
    where exists (
      select 1
      from jsonb_array_elements(coalesce(p.managed_by, '[]'::jsonb)) entry
      where entry->>'employee_id' = p_employee_id
        and entry->>'branch_id' = p_source_branch_id::text
    );
  end if;

  return v_claim_count;
end;
$$;

revoke all on function public.process_boarding_transfer_claims(text, bigint) from public, anon;
grant execute on function public.process_boarding_transfer_claims(text, bigint) to authenticated, service_role;

commit;
