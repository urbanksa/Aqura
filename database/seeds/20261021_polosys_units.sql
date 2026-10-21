begin;

lock table public."Polosys_units" in access exclusive mode;

insert into public."Polosys_units" (unit_code, name, name_ar) overriding system value values
  (1, 'Kg', 'كيلو'),
  (2, 'Pcs', 'حبة'),
  (3, 'Packet', 'باكيت'),
  (4, 'Packet-1', 'باكيت-1'),
  (5, 'Packet-2', 'باكيت-2'),
  (6, 'Packet-3', 'باكيت-3'),
  (7, 'Packet-4', 'باكيت-4'),
  (8, 'Ctn', 'كرتون'),
  (9, 'Ctn-1', 'كرتون-1'),
  (10, 'Ctn-2', 'كرتون-2'),
  (11, 'Ctn-3', 'كرتون-3'),
  (12, 'Ctn-4', 'كرتون-4'),
  (13, 'Bag', 'كيس'),
  (14, 'Bottle', 'عبوة'),
  (15, 'Can', 'علبة'),
  (16, 'Liter', 'لتر'),
  (17, 'Ml', 'مل'),
  (18, 'Dozen', 'دزينة');

select setval('public."Polosys_units_unit_code_seq"'::regclass, (select max(unit_code) from public."Polosys_units"), true);

commit;
