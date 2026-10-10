begin;

create table if not exists public.boarding_transfer_logs (
  id bigint generated always as identity primary key,
  event_type text not null check (event_type in ('onboarding', 'transfer')),
  employee_id text not null references public.hr_employee_master(id),
  employee_user_id uuid references public.users(id) on delete set null,
  effective_date date,
  source_company_id bigint references public.company_master(id) on delete set null,
  source_branch_id bigint references public.branches(id) on delete set null,
  destination_company_id bigint references public.company_master(id) on delete set null,
  destination_branch_id bigint references public.branches(id) on delete set null,
  performed_by uuid references public.users(id) on delete set null,
  performed_at timestamptz not null default now(),
  details jsonb not null default '{}'::jsonb
);

create index if not exists boarding_transfer_logs_employee_time_idx
  on public.boarding_transfer_logs(employee_id, performed_at desc);
create index if not exists boarding_transfer_logs_type_time_idx
  on public.boarding_transfer_logs(event_type, performed_at desc);
create index if not exists boarding_transfer_logs_actor_time_idx
  on public.boarding_transfer_logs(performed_by, performed_at desc);

alter table public.boarding_transfer_logs enable row level security;
drop policy if exists boarding_transfer_logs_read on public.boarding_transfer_logs;
create policy boarding_transfer_logs_read
  on public.boarding_transfer_logs
  for select to authenticated
  using (public.aqura_current_user_id() is not null);

revoke all on public.boarding_transfer_logs from public, anon, authenticated;
grant select on public.boarding_transfer_logs to authenticated;
grant all on public.boarding_transfer_logs to service_role;

create or replace function public.log_boarding_transfer_branch_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := public.aqura_current_user_id();
  v_source_company_id bigint;
  v_destination_company_id bigint;
begin
  if old.current_branch_id is null
     or new.current_branch_id is not distinct from old.current_branch_id then
    return new;
  end if;

  select b.company_id into v_source_company_id
  from public.branches b
  where b.id = old.current_branch_id;

  select b.company_id into v_destination_company_id
  from public.branches b
  where b.id = new.current_branch_id;

  insert into public.boarding_transfer_logs (
    event_type,
    employee_id,
    employee_user_id,
    effective_date,
    source_company_id,
    source_branch_id,
    destination_company_id,
    destination_branch_id,
    performed_by,
    details
  ) values (
    'transfer',
    new.id,
    new.user_id,
    (now() at time zone 'Asia/Riyadh')::date,
    v_source_company_id,
    old.current_branch_id,
    v_destination_company_id,
    new.current_branch_id,
    v_actor,
    jsonb_build_object('source', 'employee_branch_change')
  );

  return new;
end;
$$;

drop trigger if exists log_boarding_transfer_branch_change_trigger
  on public.hr_employee_master;
create trigger log_boarding_transfer_branch_change_trigger
after update of current_branch_id on public.hr_employee_master
for each row
execute function public.log_boarding_transfer_branch_change();

create or replace function public.set_boarding_transfer_employee_status(
  p_employee_id text,
  p_new_status text,
  p_effective_date date,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := public.aqura_current_user_id();
  v_current_status text;
  v_result record;
  v_employee_user_id uuid;
  v_branch_id bigint;
  v_company_id bigint;
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

  select m.user_id, m.current_branch_id, b.company_id
  into v_employee_user_id, v_branch_id, v_company_id
  from public.hr_employee_master m
  left join public.branches b on b.id = m.current_branch_id
  where m.id = p_employee_id;
  if not found then raise exception 'Employee not found'; end if;

  if p_new_status not in ('Job (With Finger)', 'Remote Job') then
    raise exception 'Onboarding status must be Job (With Finger) or Remote Job';
  end if;
  if p_effective_date is null then raise exception 'Effective Date is required'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Reason is required'; end if;

  select h.status into v_current_status
  from public.hr_employee_status_history h
  where h.employee_id = p_employee_id and h.effective_to is null
  order by h.effective_from desc nulls last, h.id desc
  limit 1;

  if v_current_status = p_new_status then
    select * into v_result
    from public.update_current_status_effective_date(
      p_employee_id, p_effective_date, trim(p_reason)
    ) limit 1;
  else
    select * into v_result
    from public.change_employee_status(
      p_employee_id, p_new_status, p_effective_date, trim(p_reason), v_actor
    ) limit 1;
  end if;

  insert into public.boarding_transfer_logs (
    event_type,
    employee_id,
    employee_user_id,
    effective_date,
    destination_company_id,
    destination_branch_id,
    performed_by,
    details
  ) values (
    'onboarding',
    p_employee_id,
    v_employee_user_id,
    p_effective_date,
    v_company_id,
    v_branch_id,
    v_actor,
    jsonb_build_object(
      'employment_status', p_new_status,
      'reason', trim(p_reason)
    )
  );

  return jsonb_build_object(
    'employee_id', p_employee_id,
    'status', p_new_status,
    'effective_from', p_effective_date,
    'reason', trim(p_reason)
  );
end;
$$;

revoke all on function public.set_boarding_transfer_employee_status(text, text, date, text)
  from public, anon;
grant execute on function public.set_boarding_transfer_employee_status(text, text, date, text)
  to authenticated, service_role;

commit;
