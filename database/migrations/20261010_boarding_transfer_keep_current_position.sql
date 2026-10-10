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
    'current_position', case
      when m.current_position_id is null then null
      else jsonb_build_object(
        'id', m.current_position_id,
        'title_en', current_p.position_title_en,
        'title_ar', current_p.position_title_ar
      )
    end,
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
  left join public.hr_positions current_p on current_p.id = m.current_position_id
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
  if p_new_position_id is not null and not exists (
    select 1 from public.hr_positions p
    where p.id = p_new_position_id and p.is_active = true
  ) then
    raise exception 'Selected position is not active or does not exist';
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

  if p_new_position_id is not null then
    update public.users
    set position_id = p_new_position_id, updated_at = now()
    where id = p_user_id;

    update public.hr_employee_master
    set current_position_id = p_new_position_id, updated_at = now()
    where id = p_employee_id and user_id = p_user_id;
  end if;

  return v_result || jsonb_build_object(
    'position_changed', p_new_position_id is not null,
    'new_position_id', p_new_position_id
  );
end;
$$;

revoke all on function public.complete_boarding_transfer(text, uuid, bigint, bigint, bigint, text, text, uuid) from public, anon;
grant execute on function public.complete_boarding_transfer(text, uuid, bigint, bigint, bigint, text, text, uuid) to authenticated, service_role;

commit;
