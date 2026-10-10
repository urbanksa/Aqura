begin;

create or replace function public.get_boarding_transfer_position_options(
  p_employee_id text
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'current_position_id', m.current_position_id,
    'positions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', p.id,
          'title_en', p.position_title_en,
          'title_ar', p.position_title_ar
        ) order by p.position_title_en nulls last, p.position_title_ar nulls last
      )
      from public.hr_positions p
      where p.is_active = true
        and p.id is distinct from m.current_position_id
    ), '[]'::jsonb)
  )
  from public.hr_employee_master m
  where m.id = p_employee_id;
$$;

revoke all on function public.get_boarding_transfer_position_options(text) from public, anon;
grant execute on function public.get_boarding_transfer_position_options(text) to authenticated, service_role;

create or replace function public.complete_boarding_transfer(
  p_employee_id text,
  p_user_id uuid,
  p_source_branch_id bigint,
  p_destination_company_id bigint,
  p_destination_branch_id bigint,
  p_biometric_id text,
  p_replacement_employee_id text,
  p_new_position_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if p_new_position_id is null then
    raise exception 'Select a new position';
  end if;
  if not exists (
    select 1 from public.hr_positions p
    where p.id = p_new_position_id and p.is_active = true
  ) then
    raise exception 'Selected position is not active or does not exist';
  end if;
  if exists (
    select 1 from public.hr_employee_master m
    where m.id = p_employee_id and m.current_position_id = p_new_position_id
  ) then
    raise exception 'Select a position different from the current position';
  end if;

  v_result := public.complete_boarding_transfer(
    p_employee_id,
    p_user_id,
    p_source_branch_id,
    p_destination_company_id,
    p_destination_branch_id,
    p_biometric_id,
    p_replacement_employee_id
  );

  update public.users
  set position_id = p_new_position_id, updated_at = now()
  where id = p_user_id;

  update public.hr_employee_master
  set current_position_id = p_new_position_id, updated_at = now()
  where id = p_employee_id and user_id = p_user_id;

  return v_result || jsonb_build_object('new_position_id', p_new_position_id);
end;
$$;

revoke all on function public.complete_boarding_transfer(text, uuid, bigint, bigint, bigint, text, text, uuid) from public, anon;
grant execute on function public.complete_boarding_transfer(text, uuid, bigint, bigint, bigint, text, text, uuid) to authenticated, service_role;

commit;
