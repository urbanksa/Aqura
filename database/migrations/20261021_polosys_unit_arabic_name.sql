begin;

alter table public."Polosys_units"
  add column name_ar text check (name_ar is null or (name_ar = btrim(name_ar) and name_ar <> ''));

comment on column public."Polosys_units".name_ar is 'Arabic unit name. The existing name remains the English ERP unit name.';

update public."Polosys_units" u set name_ar = seed.name_ar
from (values
  (1, 'كيلو'), (2, 'حبة'), (3, 'باكيت'), (4, 'باكيت-1'),
  (5, 'باكيت-2'), (6, 'باكيت-3'), (7, 'باكيت-4'), (8, 'كرتون'),
  (9, 'كرتون-1'), (10, 'كرتون-2'), (11, 'كرتون-3'), (12, 'كرتون-4'),
  (13, 'كيس'), (14, 'عبوة'), (15, 'علبة'), (16, 'لتر'), (17, 'مل'), (18, 'دزينة')
) as seed(unit_code, name_ar) where u.unit_code = seed.unit_code;

notify pgrst, 'reload schema';
commit;
