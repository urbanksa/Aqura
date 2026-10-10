begin;

create or replace function public.get_boarding_transfer_companies()
returns table (
  id bigint,
  name_en text,
  name_ar text
)
language sql
stable
security invoker
set search_path = public
as $$
  select c.id, c.name_en::text, c.name_ar::text
  from public.company_master c
  order by c.name_en nulls last, c.name_ar nulls last;
$$;

create or replace function public.get_boarding_transfer_branches(p_company_id bigint)
returns table (
  id bigint,
  name_en text,
  name_ar text,
  location_en text,
  location_ar text
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    b.id,
    b.name_en::text,
    b.name_ar::text,
    b.location_en::text,
    b.location_ar::text
  from public.branches b
  where b.company_id = p_company_id
    and b.is_active = true
  order by b.name_en nulls last, b.name_ar nulls last;
$$;

create or replace function public.get_boarding_transfer_nationalities()
returns table (
  id text,
  name_en text,
  name_ar text
)
language sql
stable
security invoker
set search_path = public
as $$
  select n.id::text, n.name_en::text, n.name_ar::text
  from public.nationalities n
  order by n.name_en nulls last, n.name_ar nulls last;
$$;

drop function if exists public.get_boarding_transfer_branch_users(bigint);

create function public.get_boarding_transfer_branch_users(p_branch_id bigint)
returns table (
  id uuid,
  username text,
  employee_id text,
  name_en text,
  name_ar text
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    u.id,
    u.username::text,
    u.employee_id::text,
    m.name_en::text,
    m.name_ar::text
  from public.users u
  left join public.hr_employee_master m on m.user_id = u.id
  where u.branch_id = p_branch_id
  order by m.name_en nulls last, m.name_ar nulls last, u.username nulls last;
$$;

create or replace function public.get_boarding_transfer_employee_details(
  p_user_id uuid,
  p_branch_id bigint
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select jsonb_build_object(
    'id', m.id,
    'name_en', coalesce(m.name_en, ''),
    'name_ar', coalesce(m.name_ar, ''),
    'whatsapp_number', coalesce(m.whatsapp_number, ''),
    'email', coalesce(m.email, ''),
    'sponsorship_status', coalesce(m.sponsorship_status, false),
    'sponsor_id', m.sponsor_id,
    'nationality_id', m.nationality_id,
    'id_number', coalesce(m.id_number, ''),
    'id_expiry_date', m.id_expiry_date,
    'biometric_link', case
      when nullif(m.employee_id_mapping ->> p_branch_id::text, '') is null then null
      else jsonb_build_object(
        'branch_id', b.id,
        'branch_name', coalesce(b.name_en, b.name_ar, 'Branch ' || p_branch_id::text),
        'biometric_id', m.employee_id_mapping ->> p_branch_id::text
      )
    end,
    'erp_user', case
      when erp.erp_user_id is null and erp.erp_username is null then null
      else jsonb_build_object(
        'username', coalesce(erp.erp_username, ''),
        'user_id', coalesce(erp.erp_user_id, '')
      )
    end
  )
  from public.hr_employee_master m
  left join public.branches b on b.id = p_branch_id
  left join lateral (
    select c.erp_username::text, c.erp_user_id::text
    from public.user_erp_credentials c
    where c.user_id = p_user_id
      and c.aqura_branch_id = p_branch_id
    limit 1
  ) erp on true
  where m.user_id = p_user_id
  limit 1;
$$;

revoke all on function public.get_boarding_transfer_companies() from public;
revoke all on function public.get_boarding_transfer_branches(bigint) from public;
revoke all on function public.get_boarding_transfer_nationalities() from public;
revoke all on function public.get_boarding_transfer_branch_users(bigint) from public;
revoke all on function public.get_boarding_transfer_employee_details(uuid, bigint) from public;
revoke execute on function public.get_boarding_transfer_branch_users(bigint) from anon;
revoke execute on function public.get_boarding_transfer_employee_details(uuid, bigint) from anon;

grant execute on function public.get_boarding_transfer_companies() to anon, authenticated, service_role;
grant execute on function public.get_boarding_transfer_branches(bigint) to anon, authenticated, service_role;
grant execute on function public.get_boarding_transfer_nationalities() to authenticated, service_role;
grant execute on function public.get_boarding_transfer_branch_users(bigint) to authenticated, service_role;
grant execute on function public.get_boarding_transfer_employee_details(uuid, bigint) to authenticated, service_role;

commit;
