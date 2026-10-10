begin;

create or replace function public.get_boarding_transfer_default_position_handoff(
  p_user_id uuid,
  p_source_branch_id bigint
)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
    'assignment_count', coalesce((
      select
        (case when d.branch_manager_user_id = p_user_id then 1 else 0 end) +
        (case when d.purchasing_manager_user_id = p_user_id then 1 else 0 end) +
        (case when d.inventory_manager_user_id = p_user_id then 1 else 0 end) +
        (case when d.accountant_user_id = p_user_id then 1 else 0 end) +
        (case when p_user_id = any(coalesce(d.night_supervisor_user_ids, '{}'::uuid[])) then 1 else 0 end) +
        (case when d.warehouse_handler_user_id = p_user_id then 1 else 0 end)
      from public.branch_default_positions d where d.branch_id = p_source_branch_id
    ), 0),
    'replacement_users', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', u.id, 'employee_id', m.id, 'name_en', m.name_en,
        'name_ar', m.name_ar, 'username', u.username
      ) order by m.name_en nulls last, m.name_ar nulls last, u.username)
      from public.users u join public.hr_employee_master m on m.user_id = u.id
      where u.branch_id = p_source_branch_id and u.status = 'active'
        and m.current_branch_id = p_source_branch_id::integer and u.id <> p_user_id
    ), '[]'::jsonb)
  );
$$;

create or replace function public.get_boarding_transfer_entry_task_handoff(
  p_user_id uuid,
  p_source_branch_id bigint
)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
    'is_assigned', coalesce((
      select d.entry_task_user_id = p_user_id
      from public.branch_default_positions d where d.branch_id = p_source_branch_id
    ), false),
    'replacement_users', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', u.id, 'employee_id', m.id, 'name_en', m.name_en,
        'name_ar', m.name_ar, 'username', u.username
      ) order by m.name_en nulls last, m.name_ar nulls last, u.username)
      from public.users u join public.hr_employee_master m on m.user_id = u.id
      where u.branch_id = p_source_branch_id and u.status = 'active'
        and m.current_branch_id = p_source_branch_id::integer and u.id <> p_user_id
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.get_boarding_transfer_entry_task_handoff(uuid, bigint) from public, anon;
grant execute on function public.get_boarding_transfer_entry_task_handoff(uuid, bigint) to authenticated, service_role;

create or replace function public.complete_boarding_transfer(
  p_employee_id text, p_user_id uuid, p_source_branch_id bigint,
  p_destination_company_id bigint, p_destination_branch_id bigint,
  p_biometric_id text, p_replacement_employee_id text,
  p_new_position_id uuid, p_default_replacement_user_id uuid
)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare v_result jsonb; v_assignment_count integer := 0;
begin
  select coalesce(
    (case when d.branch_manager_user_id = p_user_id then 1 else 0 end) +
    (case when d.purchasing_manager_user_id = p_user_id then 1 else 0 end) +
    (case when d.inventory_manager_user_id = p_user_id then 1 else 0 end) +
    (case when d.accountant_user_id = p_user_id then 1 else 0 end) +
    (case when p_user_id = any(coalesce(d.night_supervisor_user_ids, '{}'::uuid[])) then 1 else 0 end) +
    (case when d.warehouse_handler_user_id = p_user_id then 1 else 0 end), 0)
  into v_assignment_count from public.branch_default_positions d
  where d.branch_id = p_source_branch_id for update;
  v_assignment_count := coalesce(v_assignment_count, 0);

  if v_assignment_count > 0 then
    if p_default_replacement_user_id is null then raise exception 'Select a replacement user for the source-branch default positions'; end if;
    if not exists (
      select 1 from public.users u join public.hr_employee_master m on m.user_id = u.id
      where u.id = p_default_replacement_user_id and u.id <> p_user_id
        and u.branch_id = p_source_branch_id and u.status = 'active'
        and m.current_branch_id = p_source_branch_id::integer
    ) then raise exception 'Default-position replacement must be active in the source branch'; end if;
  end if;

  v_result := public.complete_boarding_transfer(
    p_employee_id, p_user_id, p_source_branch_id, p_destination_company_id,
    p_destination_branch_id, p_biometric_id, p_replacement_employee_id, p_new_position_id
  );

  if v_assignment_count > 0 then
    update public.branch_default_positions set
      branch_manager_user_id = case when branch_manager_user_id = p_user_id then p_default_replacement_user_id else branch_manager_user_id end,
      purchasing_manager_user_id = case when purchasing_manager_user_id = p_user_id then p_default_replacement_user_id else purchasing_manager_user_id end,
      inventory_manager_user_id = case when inventory_manager_user_id = p_user_id then p_default_replacement_user_id else inventory_manager_user_id end,
      accountant_user_id = case when accountant_user_id = p_user_id then p_default_replacement_user_id else accountant_user_id end,
      night_supervisor_user_ids = array_replace(coalesce(night_supervisor_user_ids, '{}'::uuid[]), p_user_id, p_default_replacement_user_id),
      warehouse_handler_user_id = case when warehouse_handler_user_id = p_user_id then p_default_replacement_user_id else warehouse_handler_user_id end,
      updated_at = now()
    where branch_id = p_source_branch_id;
  end if;
  return v_result || jsonb_build_object('default_positions_reassigned', v_assignment_count, 'default_replacement_user_id', p_default_replacement_user_id);
end;
$$;

create or replace function public.complete_boarding_transfer(
  p_employee_id text, p_user_id uuid, p_source_branch_id bigint,
  p_destination_company_id bigint, p_destination_branch_id bigint,
  p_biometric_id text, p_replacement_employee_id text,
  p_new_position_id uuid, p_default_replacement_user_id uuid,
  p_entry_task_replacement_user_id uuid
)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare v_result jsonb; v_is_entry_task_user boolean := false;
begin
  select coalesce(d.entry_task_user_id = p_user_id, false)
  into v_is_entry_task_user from public.branch_default_positions d
  where d.branch_id = p_source_branch_id for update;
  v_is_entry_task_user := coalesce(v_is_entry_task_user, false);

  if v_is_entry_task_user then
    if p_entry_task_replacement_user_id is null then raise exception 'Select a replacement Entry Task User'; end if;
    if not exists (
      select 1 from public.users u join public.hr_employee_master m on m.user_id = u.id
      where u.id = p_entry_task_replacement_user_id and u.id <> p_user_id
        and u.branch_id = p_source_branch_id and u.status = 'active'
        and m.current_branch_id = p_source_branch_id::integer
    ) then raise exception 'Entry Task replacement must be active in the source branch'; end if;
  end if;

  v_result := public.complete_boarding_transfer(
    p_employee_id, p_user_id, p_source_branch_id, p_destination_company_id,
    p_destination_branch_id, p_biometric_id, p_replacement_employee_id,
    p_new_position_id, p_default_replacement_user_id
  );

  if v_is_entry_task_user then
    update public.branch_default_positions
    set entry_task_user_id = p_entry_task_replacement_user_id, updated_at = now()
    where branch_id = p_source_branch_id and entry_task_user_id = p_user_id;
  end if;
  return v_result || jsonb_build_object('entry_task_user_reassigned', v_is_entry_task_user, 'entry_task_replacement_user_id', p_entry_task_replacement_user_id);
end;
$$;

revoke all on function public.complete_boarding_transfer(text, uuid, bigint, bigint, bigint, text, text, uuid, uuid, uuid) from public, anon;
grant execute on function public.complete_boarding_transfer(text, uuid, bigint, bigint, bigint, text, text, uuid, uuid, uuid) to authenticated, service_role;

commit;
