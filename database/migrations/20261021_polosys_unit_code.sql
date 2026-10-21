begin;

alter table public."Polosys_units"
  add column unit_code bigint generated always as identity (
    sequence name public."Polosys_units_unit_code_seq"
    start with 1 increment by 1
  );

alter table public."Polosys_units"
  add constraint "Polosys_units_unit_code_unique" unique (unit_code);

comment on column public."Polosys_units".unit_code
  is 'Numeric unit code generated automatically on insert, starting at 1. The UUID id remains the primary key.';

revoke all on sequence public."Polosys_units_unit_code_seq" from public, anon;
grant usage, select on sequence public."Polosys_units_unit_code_seq" to authenticated, service_role;

notify pgrst, 'reload schema';
commit;
