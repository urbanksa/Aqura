begin;

create table if not exists public.hr_employee_status_audit_log (
  id bigint generated always as identity primary key,
  employee_id text not null references public.hr_employee_master(id),
  history_id bigint,
  action text not null check (action in ('create','update','delete')),
  old_values jsonb,
  new_values jsonb,
  changed_by uuid references public.users(id) on delete set null,
  changed_at timestamptz not null default now()
);
create index if not exists hr_employee_status_audit_employee_time_idx
  on public.hr_employee_status_audit_log(employee_id, changed_at desc);

create or replace function public.audit_hr_employee_status_history()
returns trigger language plpgsql security definer set search_path=public as $f$
begin
  insert into public.hr_employee_status_audit_log
    (employee_id,history_id,action,old_values,new_values,changed_by)
  values (
    coalesce(new.employee_id,old.employee_id), coalesce(new.id,old.id),
    case tg_op when 'INSERT' then 'create' when 'UPDATE' then 'update' else 'delete' end,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end,
    public.aqura_current_user_id()
  );
  return coalesce(new,old);
end $f$;
drop trigger if exists audit_hr_employee_status_history_trigger on public.hr_employee_status_history;
create trigger audit_hr_employee_status_history_trigger
after insert or update or delete on public.hr_employee_status_history
for each row execute function public.audit_hr_employee_status_history();

create or replace function public.change_employee_status(
  p_employee_id text, p_new_status text, p_start_date date, p_reason text,
  p_created_by uuid default null
) returns table(id bigint,employee_id text,status text,effective_from date,effective_to date,reason text)
language plpgsql security definer set search_path=public as $f$
declare
  v_valid text[]:=array['Job (With Finger)','Remote Job','Vacation','Resigned'];
  v_open record; v_conflict record;
  v_actor uuid:=public.aqura_current_user_id();
begin
  if auth.role()='service_role' and v_actor is null then v_actor:=p_created_by; end if;
  if coalesce(trim(p_employee_id),'')='' then raise exception 'Employee ID is required'; end if;
  if not (p_new_status=any(v_valid)) then raise exception 'Invalid employment status value: %',p_new_status; end if;
  if p_start_date is null then raise exception 'Start date is required'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'Reason is required'; end if;
  if not exists(select 1 from public.hr_employee_master m where m.id=p_employee_id) then raise exception 'Employee not found'; end if;

  select h.* into v_open from public.hr_employee_status_history h
   where h.employee_id=p_employee_id and h.effective_to is null limit 1 for update;
  if v_open.id is not null and v_open.effective_from is not null and p_start_date<=v_open.effective_from then
    raise exception 'New start date must be after % (%), when the current status began',v_open.effective_from,v_open.status;
  end if;
  select h.* into v_conflict from public.hr_employee_status_history h
   where h.employee_id=p_employee_id and h.effective_to is not null
     and (h.effective_from is null or h.effective_from<=p_start_date)
     and h.effective_to>=p_start_date limit 1;
  if v_conflict.id is not null then
    raise exception 'This date falls within an existing "%" period (% to %)',v_conflict.status,coalesce(v_conflict.effective_from::text,'unknown'),v_conflict.effective_to;
  end if;
  if v_open.id is not null then
    update public.hr_employee_status_history set effective_to=p_start_date-1 where hr_employee_status_history.id=v_open.id;
  end if;
  return query insert into public.hr_employee_status_history
    (employee_id,status,effective_from,effective_to,reason,created_by)
    values(p_employee_id,p_new_status,p_start_date,null,trim(p_reason),v_actor)
    returning hr_employee_status_history.id,hr_employee_status_history.employee_id,
      hr_employee_status_history.status,hr_employee_status_history.effective_from,
      hr_employee_status_history.effective_to,hr_employee_status_history.reason;
end $f$;

create table if not exists public.hr_shift_audit_log (
  id bigint generated always as identity primary key,
  employee_id text references public.hr_employee_master(id),
  table_name text not null,
  record_id bigint,
  parent_version_id bigint,
  action text not null check (action in ('create','update','delete')),
  old_values jsonb,
  new_values jsonb,
  changed_by uuid references public.users(id) on delete set null,
  changed_at timestamptz not null default now()
);
create index if not exists hr_shift_audit_employee_time_idx on public.hr_shift_audit_log(employee_id,changed_at desc);
create index if not exists hr_shift_audit_source_idx on public.hr_shift_audit_log(table_name,record_id,changed_at desc);

create or replace function public.audit_hr_shift_change()
returns trigger language plpgsql security definer set search_path=public as $f$
declare
  v_row jsonb:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_employee text; v_parent bigint;
begin
  if tg_argv[0]='version' then
    v_employee:=v_row->>'employee_id';
  else
    v_parent:=nullif(v_row->>'version_id','')::bigint;
    execute format('select employee_id from public.%I where id=$1',tg_argv[1]) into v_employee using v_parent;
    if v_employee is null then
      select a.employee_id into v_employee from public.hr_shift_audit_log a
       where a.table_name=tg_argv[1] and a.record_id=v_parent order by a.changed_at desc,a.id desc limit 1;
    end if;
  end if;
  insert into public.hr_shift_audit_log
    (employee_id,table_name,record_id,parent_version_id,action,old_values,new_values,changed_by)
  values(v_employee,tg_table_name,nullif(v_row->>'id','')::bigint,v_parent,
    case tg_op when 'INSERT' then 'create' when 'UPDATE' then 'update' else 'delete' end,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end,
    public.aqura_current_user_id());
  return coalesce(new,old);
end $f$;

drop trigger if exists audit_hr_regular_shift_versions_trigger on public.hr_regular_shift_versions;
create trigger audit_hr_regular_shift_versions_trigger after insert or update or delete on public.hr_regular_shift_versions for each row execute function public.audit_hr_shift_change('version');
drop trigger if exists audit_hr_regular_shift_slots_trigger on public.hr_regular_shift_slots;
create trigger audit_hr_regular_shift_slots_trigger after insert or update or delete on public.hr_regular_shift_slots for each row execute function public.audit_hr_shift_change('slot','hr_regular_shift_versions');
drop trigger if exists audit_hr_special_shift_weekday_versions_trigger on public.hr_special_shift_weekday_versions;
create trigger audit_hr_special_shift_weekday_versions_trigger after insert or update or delete on public.hr_special_shift_weekday_versions for each row execute function public.audit_hr_shift_change('version');
drop trigger if exists audit_hr_special_shift_weekday_slots_trigger on public.hr_special_shift_weekday_slots;
create trigger audit_hr_special_shift_weekday_slots_trigger after insert or update or delete on public.hr_special_shift_weekday_slots for each row execute function public.audit_hr_shift_change('slot','hr_special_shift_weekday_versions');
drop trigger if exists audit_hr_special_shift_date_wise_versions_trigger on public.hr_special_shift_date_wise_versions;
create trigger audit_hr_special_shift_date_wise_versions_trigger after insert or update or delete on public.hr_special_shift_date_wise_versions for each row execute function public.audit_hr_shift_change('version');
drop trigger if exists audit_hr_special_shift_date_wise_slots_trigger on public.hr_special_shift_date_wise_slots;
create trigger audit_hr_special_shift_date_wise_slots_trigger after insert or update or delete on public.hr_special_shift_date_wise_slots for each row execute function public.audit_hr_shift_change('slot','hr_special_shift_date_wise_versions');

alter table public.hr_employee_status_audit_log enable row level security;
alter table public.hr_shift_audit_log enable row level security;
drop policy if exists hr_employee_status_audit_read on public.hr_employee_status_audit_log;
create policy hr_employee_status_audit_read on public.hr_employee_status_audit_log for select to authenticated using(public.aqura_current_user_id() is not null);
drop policy if exists hr_shift_audit_read on public.hr_shift_audit_log;
create policy hr_shift_audit_read on public.hr_shift_audit_log for select to authenticated using(public.aqura_current_user_id() is not null);
revoke all on public.hr_employee_status_audit_log from public,anon,authenticated;
revoke all on public.hr_shift_audit_log from public,anon,authenticated;
grant select on public.hr_employee_status_audit_log to authenticated;
grant select on public.hr_shift_audit_log to authenticated;
grant all on public.hr_employee_status_audit_log to service_role;
grant all on public.hr_shift_audit_log to service_role;
revoke insert,update,delete on public.hr_employee_status_history from anon,authenticated;
revoke execute on function public.change_employee_status(text,text,date,text,uuid) from public,anon;
revoke execute on function public.update_current_status_effective_date(text,date,text) from public,anon;
grant execute on function public.change_employee_status(text,text,date,text,uuid) to authenticated,service_role;
grant execute on function public.update_current_status_effective_date(text,date,text) to authenticated,service_role;

-- Anonymous writes cannot be attributed to a user, so all audited shift
-- mutations require an authenticated session. Existing read access is intact.
revoke insert,update,delete on public.hr_regular_shift_versions from anon;
revoke insert,update,delete on public.hr_regular_shift_slots from anon;
revoke insert,update,delete on public.hr_special_shift_weekday_versions from anon;
revoke insert,update,delete on public.hr_special_shift_weekday_slots from anon;
revoke insert,update,delete on public.hr_special_shift_date_wise_versions from anon;
revoke insert,update,delete on public.hr_special_shift_date_wise_slots from anon;

commit;
