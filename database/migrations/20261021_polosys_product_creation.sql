-- Temporary product preparation tables. Remove this module after the fresh
-- Polosys database has been populated. Exact ERP group/unit names are required.
-- Details JSON holds name, Arabic name, barcode, purchase_price, sales_price,
-- and multi_units [{unit_id, quantity_in_base_units, barcode, price}].
begin;

create table public."Polosys_units" (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (name = btrim(name) and name <> ''),
  created_at timestamptz not null default now()
);

create table public."Polosys_product_groups" (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (name = btrim(name) and name <> ''),
  created_at timestamptz not null default now()
);

create table public."Polosys_products" (
  id uuid primary key default gen_random_uuid(),
  product_group_id uuid not null references public."Polosys_product_groups"(id),
  base_unit_id uuid not null references public."Polosys_units"(id),
  data jsonb not null check (jsonb_typeof(data) = 'object'),
  created_by uuid not null default public.aqura_current_user_id() references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public."Polosys_units" is 'Temporary Polosys preparation: exact ERP unit names.';
comment on table public."Polosys_product_groups" is 'Temporary Polosys preparation: exact ERP group names.';
comment on table public."Polosys_products" is 'Temporary product data for future Polosys UI creation; not connected to automation yet.';

create function public."Polosys_is_master_admin"() returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.users
    where id = public.aqura_current_user_id()
      and is_master_admin = true and status = 'active'
  );
$$;
revoke all on function public."Polosys_is_master_admin"() from public, anon;
grant execute on function public."Polosys_is_master_admin"() to authenticated, service_role;

alter table public."Polosys_units" enable row level security;
alter table public."Polosys_product_groups" enable row level security;
alter table public."Polosys_products" enable row level security;
revoke all on public."Polosys_units", public."Polosys_product_groups", public."Polosys_products" from public, anon, authenticated;
grant select, insert, update, delete on public."Polosys_units", public."Polosys_product_groups", public."Polosys_products" to authenticated;
grant all on public."Polosys_units", public."Polosys_product_groups", public."Polosys_products" to service_role;

create policy "Polosys_master_admin_only" on public."Polosys_units"
  for all to authenticated using ((select public."Polosys_is_master_admin"()))
  with check ((select public."Polosys_is_master_admin"()));
create policy "Polosys_master_admin_only" on public."Polosys_product_groups"
  for all to authenticated using ((select public."Polosys_is_master_admin"()))
  with check ((select public."Polosys_is_master_admin"()));
create policy "Polosys_master_admin_only" on public."Polosys_products"
  for all to authenticated using ((select public."Polosys_is_master_admin"()))
  with check ((select public."Polosys_is_master_admin"()));

create function public."Polosys_touch_updated_at"() returns trigger
language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger "Polosys_products_updated_at" before update on public."Polosys_products"
for each row execute function public."Polosys_touch_updated_at"();

notify pgrst, 'reload schema';
commit;
