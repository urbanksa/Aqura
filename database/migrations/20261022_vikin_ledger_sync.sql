begin;

-- Codes are unique within a company, not across separate Vikin companies.
-- Stable IDs allow future account mappings to survive a ledger rename.
create table public.vikin_ledgers (
  id uuid primary key default gen_random_uuid(),
  company_id bigint not null references public.company_master(id) on delete restrict,
  ledger_code text not null check (ledger_code = btrim(ledger_code) and length(ledger_code) between 1 and 500),
  ledger_name text not null check (ledger_name = btrim(ledger_name) and length(ledger_name) between 1 and 500),
  account_group_name text not null check (account_group_name = btrim(account_group_name) and length(account_group_name) between 1 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_synced_at timestamptz not null default now(),
  created_by uuid not null references public.users(id),
  updated_by uuid not null references public.users(id),
  last_synced_by uuid not null references public.users(id),
  unique (company_id, ledger_code)
);

comment on table public.vikin_ledgers is
  'Vikin ledger catalogue for future mappings. Sync adds or updates by company and exact ledger code; absent codes are retained.';
comment on column public.vikin_ledgers.updated_at is
  'Changes only when the ledger name or account group changes; last_synced_at records every successful observation.';

create function public.vikin_ledgers_can_sync()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.users
    where id = public.aqura_current_user_id()
      and status = 'active' and is_master_admin = true
  );
$$;
revoke all on function public.vikin_ledgers_can_sync() from public, anon;
grant execute on function public.vikin_ledgers_can_sync() to authenticated, service_role;

alter table public.vikin_ledgers enable row level security;
revoke all on public.vikin_ledgers from public, anon, authenticated;
grant select on public.vikin_ledgers to authenticated;
grant all on public.vikin_ledgers to service_role;
create policy "Vikin ledger catalogue master admin read" on public.vikin_ledgers
  for select to authenticated using ((select public.vikin_ledgers_can_sync()));

create function public.list_vikin_ledger_companies()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.vikin_ledgers_can_sync() then
    raise exception 'Master Admin access is required to sync Vikin ledgers.' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'name_en', name_en, 'name_ar', name_ar)
      order by name_en, id)
    from public.company_master where erp_provider = 'vikin'
  ), '[]'::jsonb);
end;
$$;

create function public.sync_vikin_ledgers(p_company_id bigint, p_ledgers jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := public.aqura_current_user_id();
  v_now timestamptz;
  v_inserted integer;
  v_updated integer;
  v_unchanged integer;
  v_total integer;
begin
  if not public.vikin_ledgers_can_sync() then
    raise exception 'Master Admin access is required to sync Vikin ledgers.' using errcode = '42501';
  end if;

  -- Also serializes simultaneous imports for this company so the counts and
  -- resulting catalogue describe the same successful atomic batch.
  perform 1 from public.company_master
  where id = p_company_id and erp_provider = 'vikin' for update;
  if not found then
    raise exception 'Select an Aqura company linked to Vikin.' using errcode = '22023';
  end if;
  if jsonb_typeof(p_ledgers) is distinct from 'array' then
    raise exception 'A non-empty Vikin ledger array is required.' using errcode = '22023';
  end if;
  v_total := jsonb_array_length(p_ledgers);
  if v_total < 1 or v_total > 50000 then
    raise exception 'Load between 1 and 50000 Vikin ledgers before syncing.' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(p_ledgers) item where jsonb_typeof(item) is distinct from 'object') then
    raise exception 'Each ledger must contain only its name, code and account group.' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_ledgers) item
    where not (item ?& array['ledger_name', 'ledger_code', 'account_group_name'])
      or item - array['ledger_name', 'ledger_code', 'account_group_name'] <> '{}'::jsonb
      or jsonb_typeof(item->'ledger_name') is distinct from 'string'
      or jsonb_typeof(item->'ledger_code') is distinct from 'string'
      or jsonb_typeof(item->'account_group_name') is distinct from 'string'
  ) then
    raise exception 'Each ledger must contain only its name, code and account group as text.' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_ledgers) item
    where length(btrim(item->>'ledger_name')) not between 1 and 500
      or length(btrim(item->>'ledger_code')) not between 1 and 500
      or length(btrim(item->>'account_group_name')) not between 1 and 500
  ) then
    raise exception 'Ledger name, code and account group must each contain 1 to 500 characters.' using errcode = '22023';
  end if;
  if exists (
    select btrim(item->>'ledger_code') from jsonb_array_elements(p_ledgers) item
    group by btrim(item->>'ledger_code') having count(*) > 1
  ) then
    raise exception 'Duplicate ledger codes were loaded. Reload the complete Vikin ledger list.' using errcode = '22023';
  end if;

  v_now := clock_timestamp();

  select count(*) filter (where saved.id is null),
    count(*) filter (where saved.id is not null and
      (saved.ledger_name, saved.account_group_name) is distinct from (btrim(item->>'ledger_name'), btrim(item->>'account_group_name'))),
    count(*) filter (where saved.id is not null and
      (saved.ledger_name, saved.account_group_name) is not distinct from (btrim(item->>'ledger_name'), btrim(item->>'account_group_name')))
  into v_inserted, v_updated, v_unchanged
  from jsonb_array_elements(p_ledgers) item
  left join public.vikin_ledgers saved
    on saved.company_id = p_company_id and saved.ledger_code = btrim(item->>'ledger_code');

  insert into public.vikin_ledgers as saved
    (company_id, ledger_code, ledger_name, account_group_name,
      created_at, updated_at, last_synced_at, created_by, updated_by, last_synced_by)
  select p_company_id, btrim(item->>'ledger_code'), btrim(item->>'ledger_name'), btrim(item->>'account_group_name'),
    v_now, v_now, v_now, v_actor, v_actor, v_actor
  from jsonb_array_elements(p_ledgers) item
  on conflict (company_id, ledger_code) do update set
    ledger_name = excluded.ledger_name,
    account_group_name = excluded.account_group_name,
    updated_at = case when (saved.ledger_name, saved.account_group_name)
      is distinct from (excluded.ledger_name, excluded.account_group_name) then v_now else saved.updated_at end,
    updated_by = case when (saved.ledger_name, saved.account_group_name)
      is distinct from (excluded.ledger_name, excluded.account_group_name) then v_actor else saved.updated_by end,
    last_synced_at = v_now,
    last_synced_by = v_actor;

  return jsonb_build_object('company_id', p_company_id, 'inserted', v_inserted,
    'updated', v_updated, 'unchanged', v_unchanged, 'total', v_total);
end;
$$;

revoke all on function public.list_vikin_ledger_companies() from public, anon;
revoke all on function public.sync_vikin_ledgers(bigint, jsonb) from public, anon;
grant execute on function public.list_vikin_ledger_companies() to authenticated, service_role;
grant execute on function public.sync_vikin_ledgers(bigint, jsonb) to authenticated, service_role;

notify pgrst, 'reload schema';
commit;
