-- Controllo dello stato del database di produzione (da eseguire in Supabase > SQL Editor).
-- Ogni riga deve avere ok = true; le righe false indicano la migrazione da eseguire.
select controllo, ok, migrazione from (values
  ('schema licensing',            exists (select 1 from information_schema.schemata where schema_name = 'licensing'), '20261018000000_schema.sql'),
  ('tabella profiles',            to_regclass('public.profiles') is not null,                                    '20261018000000_schema.sql'),
  ('tabella catalog_cache',       to_regclass('public.catalog_cache') is not null,                               '20261018000000_schema.sql'),
  ('tabella entitlements',        to_regclass('licensing.entitlements') is not null,                             '20261018000000_schema.sql'),
  ('trigger nuovo utente',        exists (select 1 from pg_trigger where tgname = 'on_auth_user_created'),        '20261018000000_schema.sql'),
  ('funzione record_event',       exists (select 1 from pg_proc where proname = 'licensing_record_event'),        '20261020000000_licensing_functions.sql'),
  ('cambio piano Google Play',    exists (select 1 from pg_proc where proname = 'licensing_apply_entitlement'
                                          and prosrc like '%questa notifica non lo tocca%'),                      '20261021000000_google_play.sql'),
  ('bucket immagini esercizi',    exists (select 1 from storage.buckets where id = 'exercise-images'),            '20261028090000_exercise_images.sql'),
  ('licenze gratuite manuali',    to_regclass('licensing.manual_grants') is not null,                            '20261103000000_manual_licenses.sql'),
  ('funzione grant_free_license', exists (select 1 from pg_proc where proname = 'grant_free_license'),            '20261103000000_manual_licenses.sql'),
  ('get_my_entitlement con source', exists (select 1 from pg_proc p where p.proname = 'get_my_entitlement'
                                          and pg_get_function_result(p.oid) like '%source%'),                     '20261103000000_manual_licenses.sql')
) as t(controllo, ok, migrazione);
