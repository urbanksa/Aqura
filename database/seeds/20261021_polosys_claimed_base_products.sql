-- One-time staging import. Original ERP products and claims are not modified.
begin;
set local lock_timeout = '10s';
lock table public."Polosys_products" in share row exclusive mode;

create temporary table polosys_claimed_base_source on commit drop as
select p.id, p.barcode, p.product_name_en, p.product_name_ar
from public.erp_synced_products p
where p.is_base_unit is true
  and exists (
    select 1 from jsonb_array_elements(p.managed_by) e
    where nullif(btrim(e->>'employee_id'), '') is not null
      and e->>'branch_id' is not null
  );

do $$
begin
  if (select count(*) from polosys_claimed_base_source) <> 13725 then
    raise exception 'Claimed base-unit source count changed; expected 13725.';
  end if;
  if not exists (select 1 from public.users where is_master_admin and status = 'active') then
    raise exception 'No active master admin available for seed attribution.';
  end if;
end;
$$;

insert into public."Polosys_units" (name, name_ar)
values ('Temporary Unit', 'وحدة مؤقتة')
on conflict (name) do nothing;

insert into public."Polosys_product_groups" (name, name_ar)
values ('Temporary Group', 'مجموعة مؤقتة')
on conflict (name) do nothing;

-- The required created_by FK uses a stable active master-admin seed actor.
-- Import provenance is recorded separately from that attribution.
with inserted as (
  insert into public."Polosys_products" (product_group_id, base_unit_id, data, created_by)
  select g.id, u.id,
    jsonb_build_object(
      'name', s.product_name_en,
      'arabic_name', coalesce(s.product_name_ar, ''),
      'barcode', s.barcode,
      'multi_units', '[]'::jsonb,
      'import_source', 'erp_synced_products',
      'import_source_id', s.id,
      'import_batch', '20261021_claimed_base_units'
    ),
    (select id from public.users where is_master_admin and status = 'active' order by id limit 1)
  from polosys_claimed_base_source s
  cross join public."Polosys_units" u
  cross join public."Polosys_product_groups" g
  where u.name = 'Temporary Unit' and g.name = 'Temporary Group'
    and not exists (
      select 1 from public."Polosys_products" p where p.data->>'barcode' = s.barcode
    )
  returning id
)
select json_build_object('inserted_products', count(*)) from inserted;

do $$
begin
  if exists (
    select 1 from polosys_claimed_base_source s
    where not exists (
      select 1 from public."Polosys_products" p
      join public."Polosys_units" u on u.id = p.base_unit_id
      join public."Polosys_product_groups" g on g.id = p.product_group_id
      where p.data->>'barcode' = s.barcode
        and u.name = 'Temporary Unit' and g.name = 'Temporary Group'
        and p.data->'multi_units' = '[]'::jsonb
    )
  ) then
    raise exception 'Imported products do not match the requested temporary unit/group.';
  end if;
end;
$$;

select json_build_object(
  'imported_base_products', count(*),
  'additional_units', sum(jsonb_array_length(p.data->'multi_units')),
  'unit', min(u.name), 'group', min(g.name),
  'unit_code', min(u.unit_code)
)
from public."Polosys_products" p
join public."Polosys_units" u on u.id = p.base_unit_id
join public."Polosys_product_groups" g on g.id = p.product_group_id
where p.data->>'import_batch' = '20261021_claimed_base_units';
commit;
