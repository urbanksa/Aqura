-- Run with an administrative database connection. All updates are rolled back.
begin;
do $$
declare
  v_company public.company_master%rowtype;
  v_actor uuid;
begin
  select * into strict v_company from public.company_master order by id limit 1;
  select id into strict v_actor from public.users order by id limit 1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor)::text, true);

  perform public.update_company(v_company.id, v_company.name_ar, v_company.name_en,
    v_company.owner_emails, v_company.owner_whatsapp_numbers, ' Polosys ');
  if (select erp_provider from public.company_master where id = v_company.id) <> 'polosys' then
    raise exception 'Polosys provider did not save';
  end if;

  perform public.update_company(v_company.id, v_company.name_ar, v_company.name_en,
    v_company.owner_emails, v_company.owner_whatsapp_numbers, 'vikin');
  if (select erp_provider from public.company_master where id = v_company.id) <> 'vikin' then
    raise exception 'Vikin provider did not save';
  end if;

  -- Older clients can still edit company details without resetting the provider.
  perform public.update_company(v_company.id, v_company.name_ar, v_company.name_en,
    v_company.owner_emails, v_company.owner_whatsapp_numbers);
  if (select erp_provider from public.company_master where id = v_company.id) <> 'vikin' then
    raise exception 'Legacy company update reset the provider';
  end if;

  begin
    perform public.update_company(v_company.id, v_company.name_ar, v_company.name_en,
      v_company.owner_emails, v_company.owner_whatsapp_numbers, 'unsupported');
    raise exception 'Expected unsupported provider rejection';
  exception when raise_exception then
    if sqlerrm <> 'Unsupported ERP provider' then raise; end if;
  end;

  begin
    perform public.create_company('test', 'test', array['test@example.test'], array['123'], 'unsupported');
    raise exception 'Expected unsupported provider rejection on creation';
  exception when raise_exception then
    if sqlerrm <> 'Unsupported ERP provider' then raise; end if;
  end;

  -- New overloads must still enforce the existing owner-contact requirement.
  begin
    perform public.create_company('test', 'test', '{}'::text[], array['123'], 'polosys');
    raise exception 'Expected owner-contact validation';
  exception when raise_exception then
    if sqlerrm <> 'At least one owner email is required' then raise; end if;
  end;

  perform public.update_company(v_company.id, v_company.name_ar, v_company.name_en,
    v_company.owner_emails, v_company.owner_whatsapp_numbers, null);
  if (select erp_provider from public.company_master where id = v_company.id) is not null then
    raise exception 'ERP provider did not unlink';
  end if;

  perform set_config('request.jwt.claims', '{}', true);
  begin
    perform public.update_company(v_company.id, v_company.name_ar, v_company.name_en,
      v_company.owner_emails, v_company.owner_whatsapp_numbers, 'polosys');
    raise exception 'Expected authentication requirement';
  exception when raise_exception then
    if sqlerrm <> 'Authentication required' then raise; end if;
  end;

  raise notice 'Company ERP provider validation and compatibility checks passed';
end;
$$;
rollback;
