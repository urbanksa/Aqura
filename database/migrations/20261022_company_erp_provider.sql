begin;

alter table public.company_master
  add column erp_provider text
  check (erp_provider in ('polosys', 'vikin'));

-- Keep existing RPC signatures available for older clients. The new overloads
-- delegate to them so authentication and company/contact validation stay intact.
create function public.create_company(
  p_name_ar text, p_name_en text, p_owner_emails text[],
  p_owner_whatsapp_numbers text[], p_erp_provider text
)
returns bigint language plpgsql security definer set search_path = public
as $$
declare v_id bigint; v_provider text := nullif(lower(btrim(p_erp_provider)), '');
begin
  if v_provider is not null and v_provider not in ('polosys', 'vikin') then
    raise exception 'Unsupported ERP provider';
  end if;
  v_id := public.create_company(p_name_ar, p_name_en, p_owner_emails, p_owner_whatsapp_numbers);
  update public.company_master set erp_provider = v_provider where id = v_id;
  return v_id;
end;
$$;

create function public.update_company(
  p_company_id bigint, p_name_ar text, p_name_en text, p_owner_emails text[],
  p_owner_whatsapp_numbers text[], p_erp_provider text
)
returns void language plpgsql security definer set search_path = public
as $$
declare v_provider text := nullif(lower(btrim(p_erp_provider)), '');
begin
  if v_provider is not null and v_provider not in ('polosys', 'vikin') then
    raise exception 'Unsupported ERP provider';
  end if;
  perform public.update_company(p_company_id, p_name_ar, p_name_en, p_owner_emails, p_owner_whatsapp_numbers);
  update public.company_master set erp_provider = v_provider where id = p_company_id;
end;
$$;

revoke all on function public.create_company(text, text, text[], text[], text) from public, anon;
revoke all on function public.update_company(bigint, text, text, text[], text[], text) from public, anon;
grant execute on function public.create_company(text, text, text[], text[], text) to authenticated, service_role;
grant execute on function public.update_company(bigint, text, text, text[], text[], text) to authenticated, service_role;

notify pgrst, 'reload schema';
commit;
