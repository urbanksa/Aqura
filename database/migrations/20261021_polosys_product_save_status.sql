begin;
create or replace function public."Polosys_mark_product_saving"(
  p_product_id uuid, p_branch_id bigint, p_run_id uuid
) returns jsonb language plpgsql security definer set search_path = public as $$
declare product public."Polosys_products"%rowtype; previous jsonb; entry jsonb;
begin
  if not public."Polosys_is_master_admin"() then raise exception 'Master Admin access required'; end if;
  select * into product from public."Polosys_products" where id=p_product_id for update;
  previous := product.creation_status->p_branch_id::text;
  if previous is null or previous->>'run_id' is distinct from p_run_id::text
    or previous->>'started_by' is distinct from public.aqura_current_user_id()::text
    or previous->>'status' <> 'filling' then raise exception 'Product run does not match'; end if;
  if previous->>'source_fingerprint' is distinct from md5(jsonb_build_object('data',product.data,'group',product.product_group_id,'unit',product.base_unit_id)::text) then
    raise exception 'Product changed before Save; refresh and prepare again';
  end if;
  entry := previous || jsonb_build_object('status','saving','mode','save','save_attempted',true,'updated_at',now());
  update public."Polosys_products" set creation_status=jsonb_set(creation_status,array[p_branch_id::text],entry,true) where id=p_product_id;
  return entry;
end; $$;

create or replace function public."Polosys_finish_product_save"(
  p_product_id uuid, p_branch_id bigint, p_run_id uuid, p_status text,
  p_error text default '', p_erp_product_code text default '', p_confirmation text default ''
) returns jsonb language plpgsql security definer set search_path = public as $$
declare product public."Polosys_products"%rowtype; previous jsonb; entry jsonb;
begin
  if not public."Polosys_is_master_admin"() then raise exception 'Master Admin access required'; end if;
  if p_status not in ('created','needs_verification') then raise exception 'Invalid Save result'; end if;
  if p_status='created' and (btrim(coalesce(p_erp_product_code,''))='' or btrim(coalesce(p_confirmation,''))='') then
    raise exception 'ERP product code and observed Save confirmation required';
  end if;
  select * into product from public."Polosys_products" where id=p_product_id for update;
  previous := product.creation_status->p_branch_id::text;
  if previous is null or previous->>'run_id' is distinct from p_run_id::text
    or previous->>'started_by' is distinct from public.aqura_current_user_id()::text then raise exception 'Product run does not match'; end if;
  if previous->>'status'=p_status then return previous; end if;
  if previous->>'status'<>'saving' then raise exception 'Save run already finished or not started'; end if;
  entry := previous || jsonb_build_object('status',p_status,'saved_in_erp',p_status='created','updated_at',now(),
    'erp_created_at',case when p_status='created' then now() else null end,
    'erp_product_code',left(coalesce(p_erp_product_code,''),100),'save_confirmation',left(coalesce(p_confirmation,''),1500),
    'error',left(coalesce(p_error,''),1500));
  update public."Polosys_products" set creation_status=jsonb_set(creation_status,array[p_branch_id::text],entry,true) where id=p_product_id;
  return entry;
end; $$;
revoke all on function public."Polosys_mark_product_saving"(uuid,bigint,uuid) from public,anon;
revoke all on function public."Polosys_finish_product_save"(uuid,bigint,uuid,text,text,text,text) from public,anon;
grant execute on function public."Polosys_mark_product_saving"(uuid,bigint,uuid) to authenticated;
grant execute on function public."Polosys_finish_product_save"(uuid,bigint,uuid,text,text,text,text) to authenticated;
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
  if previous->>'status' in ('filling', 'saving', 'created') or (previous->>'status'='needs_verification' and previous->>'save_attempted'='true') then
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
