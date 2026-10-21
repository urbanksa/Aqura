begin;

insert into public."Polosys_product_groups" (name, name_ar) values
  ('Fruits & Vegetables', 'خضار وفواكه'),
  ('Dates', 'تمور'),
  ('Fresh Dairy', 'ألبان طازجة'),
  ('Cheese', 'أجبان'),
  ('Eggs', 'بيض'),
  ('Urban Bakery', 'مخبوزات ايربن'),
  ('Other Bakery', 'مخبوزات معبأة'),
  ('Fresh Chicken', 'دجاج طازج'),
  ('Fresh Meat', 'لحوم طازجة'),
  ('Frozen Food', 'مجمدات'),
  ('Ice Cream', 'آيس كريم'),
  ('Dry Grocery / Pantry', 'بقالة'),
  ('Snacks', 'وجبات خفيفة'),
  ('Sweets & Chocolate', 'حلويات'),
  ('Coffee Counter', 'ركن القهوة'),
  ('Beverages', 'مشروبات'),
  ('Water', 'مياه'),
  ('Household Cleaning', 'منظفات منزلية'),
  ('Personal Care', 'عناية شخصية'),
  ('Baby Products', 'مستلزمات أطفال'),
  ('Cat Food', 'طعام قطط'),
  ('Electronics', 'إلكترونيات'),
  ('Toys', 'ألعاب')
on conflict (name) do update set name_ar = excluded.name_ar;

commit;
