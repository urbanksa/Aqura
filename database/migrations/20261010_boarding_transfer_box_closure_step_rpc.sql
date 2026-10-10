begin;

create or replace function public.get_boarding_transfer_box_closure_handoff(p_user_id uuid, p_source_branch_id bigint)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'has_source_branch_permission', exists (
      select 1 from public.complete_box_closure_permissions p
      join public.complete_box_closure_branch_grants g on g.user_id = p.user_id
      where p.user_id = p_user_id and p.branch_specific_enabled = true
        and p.all_branches_enabled = false and g.branch_id = p_source_branch_id
    ),
    'has_all_branches_permission', coalesce((select p.all_branches_enabled from public.complete_box_closure_permissions p where p.user_id = p_user_id), false),
    'replacement_users', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', u.id, 'employee_id', m.id, 'name_en', m.name_en, 'name_ar', m.name_ar, 'username', u.username)
        order by m.name_en nulls last, m.name_ar nulls last, u.username)
      from public.users u join public.hr_employee_master m on m.user_id = u.id
      where u.branch_id = p_source_branch_id and u.status = 'active' and u.id <> p_user_id
        and m.current_branch_id = p_source_branch_id::integer
        and exists (select 1 from public.button_permissions bp where bp.user_id = u.id and bp.button_code = 'DENOMINATION' and bp.is_enabled = true)
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.get_boarding_transfer_box_closure_handoff(uuid, bigint) from public, anon;
grant execute on function public.get_boarding_transfer_box_closure_handoff(uuid, bigint) to authenticated, service_role;

create or replace function public.complete_boarding_transfer(
  p_employee_id text, p_user_id uuid, p_source_branch_id bigint, p_destination_company_id bigint,
  p_destination_branch_id bigint, p_biometric_id text, p_replacement_employee_id text,
  p_new_position_id uuid, p_default_replacement_user_id uuid, p_entry_task_replacement_user_id uuid,
  p_box_closure_replacement_user_id uuid
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_result jsonb; v_actor uuid := public.aqura_current_user_id(); v_has_grant boolean := false;
begin
  select exists (
    select 1 from public.complete_box_closure_permissions p
    join public.complete_box_closure_branch_grants g on g.user_id = p.user_id
    where p.user_id = p_user_id and p.branch_specific_enabled = true
      and p.all_branches_enabled = false and g.branch_id = p_source_branch_id
  ) into v_has_grant;
  if v_has_grant then
    if p_box_closure_replacement_user_id is null then raise exception 'Select a replacement user for Complete Box Closure'; end if;
    if not exists (
      select 1 from public.users u join public.hr_employee_master m on m.user_id = u.id
      where u.id = p_box_closure_replacement_user_id and u.id <> p_user_id
        and u.branch_id = p_source_branch_id and u.status = 'active'
        and m.current_branch_id = p_source_branch_id::integer
        and exists (select 1 from public.button_permissions bp where bp.user_id = u.id and bp.button_code = 'DENOMINATION' and bp.is_enabled = true)
    ) then raise exception 'Closure replacement must be an eligible active user in the source branch'; end if;
  end if;

  v_result := public.complete_boarding_transfer(p_employee_id, p_user_id, p_source_branch_id,
    p_destination_company_id, p_destination_branch_id, p_biometric_id, p_replacement_employee_id,
    p_new_position_id, p_default_replacement_user_id, p_entry_task_replacement_user_id);

  if v_has_grant then
    delete from public.complete_box_closure_branch_grants where user_id = p_user_id and branch_id = p_source_branch_id;
    insert into public.complete_box_closure_permissions(user_id, all_branches_enabled, branch_specific_enabled, updated_by, updated_at)
    values(p_box_closure_replacement_user_id, false, true, v_actor, now())
    on conflict(user_id) do update set branch_specific_enabled = true, updated_by = v_actor, updated_at = now();
    insert into public.complete_box_closure_branch_grants(user_id, branch_id, granted_by)
    values(p_box_closure_replacement_user_id, p_source_branch_id::integer, v_actor)
    on conflict(user_id, branch_id) do update set granted_by = v_actor;
  end if;
  return v_result || jsonb_build_object('box_closure_permission_reassigned', v_has_grant, 'box_closure_replacement_user_id', p_box_closure_replacement_user_id);
end;
$$;

revoke all on function public.complete_boarding_transfer(text, uuid, bigint, bigint, bigint, text, text, uuid, uuid, uuid, uuid) from public, anon;
grant execute on function public.complete_boarding_transfer(text, uuid, bigint, bigint, bigint, text, text, uuid, uuid, uuid, uuid) to authenticated, service_role;
commit;
