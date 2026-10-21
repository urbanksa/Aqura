begin;

alter table public."Polosys_product_groups"
  add column name_ar text
  check (name_ar is null or (name_ar = btrim(name_ar) and name_ar <> ''));

comment on column public."Polosys_product_groups".name_ar
  is 'Arabic product group name in Aqura. Existing groups remain unset until supplied.';

notify pgrst, 'reload schema';
commit;
