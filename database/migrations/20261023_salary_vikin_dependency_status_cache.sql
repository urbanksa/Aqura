begin;

-- Older Assistant APIs return task select('*') without joining completed
-- parents. Expose an authoritative dependency status in that existing result.
alter table public.assistant_workflow_tasks add column depends_on_status text;
comment on column public.assistant_workflow_tasks.depends_on_status is
  'Database-derived original-task status for Vikin reversals; client values are overwritten.';

create function public.derive_salary_vikin_dependency_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.depends_on_status := null;
  if new.task_type = 'salary_vikin_adjustment_jv' and new.payload->>'entry_kind' = 'reversal' then
    select parent.status into new.depends_on_status
      from public.assistant_workflow_tasks parent
      where parent.id::text = new.payload->>'depends_on_task_id'
        and parent.task_type = 'salary_vikin_adjustment_jv' and parent.payload->>'entry_kind' = 'adjustment'
        and parent.branch_id = new.branch_id and parent.source_record_id = new.source_record_id
        and parent.assigned_to = new.assigned_to and parent.created_by = new.created_by
        and parent.payload->>'company_id' = new.payload->>'company_id';
  end if;
  return new;
end;
$$;
revoke all on function public.derive_salary_vikin_dependency_status() from public, anon, authenticated;
create trigger assistant_vikin_dependency_status before insert or update
  on public.assistant_workflow_tasks for each row execute function public.derive_salary_vikin_dependency_status();

create function public.sync_salary_vikin_dependency_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.task_type = 'salary_vikin_adjustment_jv' and new.payload->>'entry_kind' = 'adjustment'
    and new.status is distinct from old.status then
    update public.assistant_workflow_tasks child set depends_on_status = new.status
      where child.task_type = 'salary_vikin_adjustment_jv' and child.payload->>'entry_kind' = 'reversal'
        and child.payload->>'depends_on_task_id' = new.id::text
        and child.depends_on_status is distinct from new.status;
  end if;
  return new;
end;
$$;
revoke all on function public.sync_salary_vikin_dependency_status() from public, anon, authenticated;
create trigger assistant_vikin_dependency_status_sync after update of status
  on public.assistant_workflow_tasks for each row execute function public.sync_salary_vikin_dependency_status();

-- Backfill reversals whose originals already finished before this column
-- existed. Both triggers preserve task payloads and task posting statuses.
update public.assistant_workflow_tasks child set depends_on_status = parent.status
  from public.assistant_workflow_tasks parent
  where child.task_type = 'salary_vikin_adjustment_jv' and child.payload->>'entry_kind' = 'reversal'
    and parent.id::text = child.payload->>'depends_on_task_id'
    and parent.task_type = 'salary_vikin_adjustment_jv' and parent.payload->>'entry_kind' = 'adjustment'
    and child.depends_on_status is distinct from parent.status;

notify pgrst, 'reload schema';
commit;
