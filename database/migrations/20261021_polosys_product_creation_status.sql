begin;
alter table public."Polosys_products"
  add column if not exists creation_status jsonb not null default '{}'::jsonb
    check (jsonb_typeof(creation_status) = 'object');
comment on column public."Polosys_products".creation_status is
  'Per-Aqura-branch assistant creation state. prepared_unsaved is never a saved ERP product.';

create or replace function public."Polosys_begin_product_preview"(
  p_product_id uuid, p_branch_id bigint, p_expected_updated_at timestamptz
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  product public."Polosys_products"%rowtype;
  previous jsonb;
  entry jsonb;
begin
  if not public."Polosys_is_master_admin"() then raise exception 'Master Admin access required'; end if;
  select * into product from public."Polosys_products" where id = p_product_id for update;
  if not found then raise exception 'Product not found'; end if;
  if product.updated_at is distinct from p_expected_updated_at then
    raise exception 'Product changed; refresh before creating';
  end if;
  if not exists(select 1 from public.branches where id = p_branch_id) then raise exception 'Branch not found'; end if;
  if not (coalesce(product.data->'branch_prices', '{}'::jsonb) ? p_branch_id::text) then
    raise exception 'Fetch prices for the selected branch first';
  end if;
  previous := product.creation_status->p_branch_id::text;
  if previous->>'status' in ('filling', 'created') then
    raise exception 'Product branch status requires verification before another attempt';
  end if;
  entry := jsonb_build_object('status', 'filling', 'mode', 'preview', 'saved_in_erp', false,
    'run_id', gen_random_uuid(), 'branch_id', p_branch_id,
    'branch_name', product.data->'branch_prices'->p_branch_id::text->>'branch_name',
    'erp_branch_id', product.data->'branch_prices'->p_branch_id::text->'erp_branch_id',
    'started_by', public.aqura_current_user_id(), 'started_at', now(), 'updated_at', now(),
    'erp_product_code',null,'erp_created_at',null,
    'source_fingerprint', md5(jsonb_build_object('data',product.data,'group',product.product_group_id,'unit',product.base_unit_id)::text));
  update public."Polosys_products" set creation_status = jsonb_set(creation_status, array[p_branch_id::text], entry, true)
    where id = p_product_id;
  return entry;
end;
$$;

create or replace function public."Polosys_finish_product_preview"(
  p_product_id uuid, p_branch_id bigint, p_run_id uuid, p_status text,
  p_error text default '', p_draft_product_code text default ''
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  product public."Polosys_products"%rowtype;
  previous jsonb;
  entry jsonb;
begin
  if not public."Polosys_is_master_admin"() then raise exception 'Master Admin access required'; end if;
  if p_status not in ('prepared_unsaved','failed','needs_verification') then
    raise exception 'Preview cannot be marked as created or saved';
  end if;
  select * into product from public."Polosys_products"
    where id = p_product_id for update;
  previous := product.creation_status->p_branch_id::text;
  if previous is null or previous->>'run_id' is distinct from p_run_id::text
    or previous->>'started_by' is distinct from public.aqura_current_user_id()::text then
    raise exception 'Preview run does not match';
  end if;
  if previous->>'status' <> 'filling' then
    if previous->>'status' = p_status then return previous; end if;
    raise exception 'Preview run already finished';
  end if;
  if p_status = 'prepared_unsaved' and previous->>'source_fingerprint' is distinct from
    md5(jsonb_build_object('data',product.data,'group',product.product_group_id,'unit',product.base_unit_id)::text) then
    p_status := 'needs_verification';
    p_error := 'Aqura product data changed while the unsaved Polosys form was being filled. Review it before proceeding.';
  end if;
  entry := previous || jsonb_build_object('status',p_status,'saved_in_erp',false,'updated_at',now(),
    'prepared_at',case when p_status='prepared_unsaved' then now() else null end,
    'error',left(coalesce(p_error,''),1500), 'draft_product_code',left(coalesce(p_draft_product_code,''),100));
  update public."Polosys_products" set creation_status = jsonb_set(creation_status, array[p_branch_id::text],entry,true)
    where id = p_product_id;
  return entry;
end;
$$;
revoke all on function public."Polosys_begin_product_preview"(uuid,bigint,timestamptz) from public, anon;
revoke all on function public."Polosys_finish_product_preview"(uuid,bigint,uuid,text,text,text) from public, anon;
grant execute on function public."Polosys_begin_product_preview"(uuid,bigint,timestamptz) to authenticated;
grant execute on function public."Polosys_finish_product_preview"(uuid,bigint,uuid,text,text,text) to authenticated;
notify pgrst, 'reload schema';
commit;
