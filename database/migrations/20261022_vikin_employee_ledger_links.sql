begin;

-- Keep Vikin mappings separate from the existing per-branch Polosys employee IDs.
-- Ledger IDs remain stable when the catalogue is synced by company and code.
alter table public.vikin_ledgers
  add constraint vikin_ledgers_id_company_key unique (id, company_id);

create table public.vikin_employee_ledger_links (
  employee_id text primary key references public.hr_employee_master(id) on delete cascade,
  company_id bigint not null references public.company_master(id) on delete restrict,
  vikin_ledger_id uuid not null,
  created_at timestamptz not null default now(),
  created_by uuid not null references public.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references public.users(id),
  foreign key (vikin_ledger_id, company_id)
    references public.vikin_ledgers(id, company_id) on delete restrict
);

comment on table public.vikin_employee_ledger_links is
  'One current Vikin ledger mapping per employee for future entry planning. Does not create accounting entries or change Polosys mappings.';

alter table public.vikin_employee_ledger_links enable row level security;
revoke all on public.vikin_employee_ledger_links from public, anon, authenticated;
grant all on public.vikin_employee_ledger_links to service_role;

create function public.vikin_employee_links_can_access()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.users u
    where u.id = public.aqura_current_user_id() and u.status = 'active'
      and (coalesce(u.is_master_admin, false) or exists (
        select 1 from public.button_permissions bp
        where bp.user_id = u.id and bp.button_code = 'LINK_ID' and bp.is_enabled
      ))
  );
$$;

create function public.get_vikin_employee_link_context(p_employee_id text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_company public.company_master%rowtype;
begin
  if not public.vikin_employee_links_can_access() then
    raise exception 'Link ID permission required.' using errcode = '42501';
  end if;
  select c.* into v_company
  from public.hr_employee_master e join public.company_master c on c.id = e.sponsor_id
  where e.id = p_employee_id and not e.is_removed and c.erp_provider = 'vikin';
  if not found then
    raise exception 'Select an employee whose sponsor company uses Vikin.' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'employee_id', p_employee_id,
    'company', jsonb_build_object('id', v_company.id, 'name_en', v_company.name_en, 'name_ar', v_company.name_ar),
    'ledgers', coalesce((
      select jsonb_agg(jsonb_build_object('id', l.id, 'ledger_code', l.ledger_code,
        'ledger_name', l.ledger_name, 'account_group_name', l.account_group_name)
        order by l.ledger_name, l.ledger_code, l.id)
      from public.vikin_ledgers l where l.company_id = v_company.id
    ), '[]'::jsonb),
    'link', (
      select jsonb_build_object('ledger_id', l.id, 'company_id', saved.company_id,
        'ledger_code', l.ledger_code, 'ledger_name', l.ledger_name,
        'account_group_name', l.account_group_name, 'updated_at', saved.updated_at)
      from public.vikin_employee_ledger_links saved
      join public.vikin_ledgers l on l.id = saved.vikin_ledger_id and l.company_id = saved.company_id
      where saved.employee_id = p_employee_id and saved.company_id = v_company.id
    )
  );
end;
$$;

create function public.set_vikin_employee_ledger_link(p_employee_id text, p_ledger_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := public.aqura_current_user_id();
  v_company_id bigint;
  v_now timestamptz := clock_timestamp();
begin
  if not public.vikin_employee_links_can_access() then
    raise exception 'Link ID permission required.' using errcode = '42501';
  end if;

  -- Serializes relinking and sponsor edits for this employee. Also lock the
  -- company against ERP-provider changes while the selected ledger is checked.
  select e.sponsor_id into v_company_id from public.hr_employee_master e
  where e.id = p_employee_id and not e.is_removed for update;
  if not found or v_company_id is null then
    raise exception 'Select an employee whose sponsor company uses Vikin.' using errcode = '22023';
  end if;
  perform 1 from public.company_master c
  where c.id = v_company_id and c.erp_provider = 'vikin' for share;
  if not found then
    raise exception 'Select an employee whose sponsor company uses Vikin.' using errcode = '22023';
  end if;

  if p_ledger_id is null then
    delete from public.vikin_employee_ledger_links where employee_id = p_employee_id;
  else
    perform 1 from public.vikin_ledgers l
    where l.id = p_ledger_id and l.company_id = v_company_id for key share;
    if not found then
      raise exception 'Select a synced Vikin ledger from this employee''s sponsor company.' using errcode = '22023';
    end if;
    insert into public.vikin_employee_ledger_links as saved
      (employee_id, company_id, vikin_ledger_id, created_at, created_by, updated_at, updated_by)
    values (p_employee_id, v_company_id, p_ledger_id, v_now, v_actor, v_now, v_actor)
    on conflict (employee_id) do update set
      company_id = excluded.company_id,
      vikin_ledger_id = excluded.vikin_ledger_id,
      updated_at = case when (saved.company_id, saved.vikin_ledger_id)
        is distinct from (excluded.company_id, excluded.vikin_ledger_id) then v_now else saved.updated_at end,
      updated_by = case when (saved.company_id, saved.vikin_ledger_id)
        is distinct from (excluded.company_id, excluded.vikin_ledger_id) then v_actor else saved.updated_by end;
  end if;

  return public.get_vikin_employee_link_context(p_employee_id);
end;
$$;

revoke all on function public.vikin_employee_links_can_access() from public, anon;
revoke all on function public.get_vikin_employee_link_context(text) from public, anon;
revoke all on function public.set_vikin_employee_ledger_link(text, uuid) from public, anon;
grant execute on function public.vikin_employee_links_can_access() to authenticated, service_role;
grant execute on function public.get_vikin_employee_link_context(text) to authenticated, service_role;
grant execute on function public.set_vikin_employee_ledger_link(text, uuid) to authenticated, service_role;

notify pgrst, 'reload schema';
commit;
