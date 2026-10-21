begin;
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
  if not exists(select 1 from public.branches where id = p_branch_id and is_active = true) then raise exception 'Branch not found'; end if;
  previous := product.creation_status->p_branch_id::text;
  if previous->>'status' in ('filling', 'created') then
    raise exception 'Product branch status requires verification before another attempt';
  end if;
  entry := jsonb_build_object('status', 'filling', 'mode', 'preview', 'saved_in_erp', false,
    'run_id', gen_random_uuid(), 'branch_id', p_branch_id,
    'branch_name', (select coalesce(name_en,name_ar) from public.branches where id = p_branch_id),
    'erp_branch_id', (select erp_branch_id from public.erp_connections where branch_id = p_branch_id and is_active = true),
    'started_by', public.aqura_current_user_id(), 'started_at', now(), 'updated_at', now(),
    'erp_product_code',null,'erp_created_at',null,
    'source_fingerprint', md5(jsonb_build_object('data',product.data,'group',product.product_group_id,'unit',product.base_unit_id)::text));
  update public."Polosys_products" set creation_status = jsonb_set(creation_status, array[p_branch_id::text], entry, true)
    where id = p_product_id;
  return entry;
end;
$$;

notify pgrst, 'reload schema';
commit;
