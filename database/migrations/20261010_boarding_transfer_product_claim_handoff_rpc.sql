begin;

create or replace function public.get_boarding_transfer_claim_handoff(
  p_employee_id text,
  p_source_branch_id bigint
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'claim_count', count(*)
  )
  from public.erp_synced_products p,
       jsonb_array_elements(coalesce(p.managed_by, '[]'::jsonb)) entry
  where entry->>'employee_id' = p_employee_id
    and entry->>'branch_id' = p_source_branch_id::text;
$$;

revoke all on function public.get_boarding_transfer_claim_handoff(text, bigint) from public, anon;
grant execute on function public.get_boarding_transfer_claim_handoff(text, bigint) to authenticated, service_role;

create or replace function public.complete_boarding_transfer(
  p_employee_id text,
  p_user_id uuid,
  p_source_branch_id bigint,
  p_destination_company_id bigint,
  p_destination_branch_id bigint,
  p_biometric_id text,
  p_replacement_employee_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := public.aqura_current_user_id();
  v_claim_count integer := 0;
  v_biometric_id text := nullif(trim(p_biometric_id), '');
  v_existing_biometric_id text;
begin
  if v_actor is null or not exists (
    select 1 from public.users u
    where u.id = v_actor
      and u.status = 'active'
      and (
        coalesce(u.is_master_admin, false)
        or exists (
          select 1 from public.button_permissions bp
          where bp.user_id = u.id
            and bp.button_code = 'EMPLOYEE_MASTER'
            and bp.is_enabled = true
        )
      )
  ) then
    raise exception 'Employee Master permission required';
  end if;

  if coalesce(trim(p_employee_id), '') = '' or p_user_id is null then
    raise exception 'Employee and user are required';
  end if;
  if p_source_branch_id is null or p_destination_company_id is null or p_destination_branch_id is null then
    raise exception 'Source and destination details are required';
  end if;
  if p_source_branch_id = p_destination_branch_id then
    raise exception 'Destination branch must be different from the source branch';
  end if;
  if not exists (
    select 1 from public.branches b
    where b.id = p_destination_branch_id
      and b.company_id = p_destination_company_id
      and b.is_active = true
  ) then
    raise exception 'The selected active branch does not belong to the destination company';
  end if;

  perform 1 from public.users u
  where u.id = p_user_id and u.branch_id = p_source_branch_id
  for update;
  if not found then
    raise exception 'The user is no longer connected to the selected source branch';
  end if;

  select nullif(m.employee_id_mapping ->> p_destination_branch_id::text, '')
  into v_existing_biometric_id
  from public.hr_employee_master m
  where m.id = p_employee_id
    and m.user_id = p_user_id
    and m.current_branch_id = p_source_branch_id::integer
  for update;
  if not found then
    raise exception 'Employee is no longer connected to the selected source branch';
  end if;

  v_biometric_id := coalesce(v_existing_biometric_id, v_biometric_id);
  if v_biometric_id is null then
    raise exception 'Select a biometric ID for the destination branch';
  end if;
  if not exists (
    select 1 from public.hr_employees e
    where e.branch_id = p_destination_branch_id
      and e.employee_id = v_biometric_id
      and coalesce(e.status, 'active') = 'active'
  ) then
    raise exception 'Biometric ID not found in the destination branch';
  end if;
  if exists (
    select 1 from public.hr_employee_master other_m
    where other_m.id <> p_employee_id
      and other_m.employee_id_mapping ->> p_destination_branch_id::text = v_biometric_id
  ) then
    raise exception 'Biometric ID is already linked to another employee';
  end if;

  select count(*)::integer into v_claim_count
  from public.erp_synced_products p,
       jsonb_array_elements(coalesce(p.managed_by, '[]'::jsonb)) entry
  where entry->>'employee_id' = p_employee_id
    and entry->>'branch_id' = p_source_branch_id::text;

  if v_claim_count > 0 then
    update public.erp_synced_products p
    set in_process = coalesce(p.in_process, '[]'::jsonb) || (
      select coalesce(jsonb_agg(
        entry.elem || jsonb_build_object(
          'moved_at', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        ) order by entry.ordinality
      ), '[]'::jsonb)
      from jsonb_array_elements(coalesce(p.managed_by, '[]'::jsonb)) with ordinality entry(elem, ordinality)
      where entry.elem->>'employee_id' = p_employee_id
        and entry.elem->>'branch_id' = p_source_branch_id::text
    ),
    managed_by = (
      select coalesce(jsonb_agg(
        entry.elem order by entry.ordinality
      ), '[]'::jsonb)
      from jsonb_array_elements(coalesce(p.managed_by, '[]'::jsonb)) with ordinality entry(elem, ordinality)
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

  update public.users
  set branch_id = p_destination_branch_id, updated_at = now()
  where id = p_user_id;

  update public.hr_employee_master
  set current_branch_id = p_destination_branch_id::integer,
      employee_id_mapping = jsonb_set(
        coalesce(employee_id_mapping, '{}'::jsonb),
        array[p_destination_branch_id::text],
        to_jsonb(v_biometric_id),
        true
      ),
      updated_at = now()
  where id = p_employee_id and user_id = p_user_id;

  return jsonb_build_object(
    'employee_id', p_employee_id,
    'source_branch_id', p_source_branch_id,
    'destination_branch_id', p_destination_branch_id,
    'biometric_id', v_biometric_id,
    'claims_moved_to_in_process', v_claim_count
  );
end;
$$;

revoke all on function public.complete_boarding_transfer(text, uuid, bigint, bigint, bigint, text, text) from public, anon;
grant execute on function public.complete_boarding_transfer(text, uuid, bigint, bigint, bigint, text, text) to authenticated, service_role;

commit;
