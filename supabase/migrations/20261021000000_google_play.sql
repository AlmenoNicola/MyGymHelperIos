-- =====================================================================
-- MyGymHelper - versione Android (Google Play). Eseguire DOPO le migrazioni precedenti.
-- Aggiorna licensing_apply_entitlement: una notifica "senza accesso" che riguarda un abbonamento
-- diverso da quello attivo dell'utente viene ignorata. Serve per i cambi di piano su Google Play
-- (Mid -> Full crea un nuovo acquisto e fa scadere il vecchio: la scadenza del vecchio non deve
-- togliere il piano nuovo) e per chi ha abbonamenti su entrambi gli store.
-- =====================================================================

create or replace function public.licensing_apply_entitlement(
  p_user_id uuid,
  p_tier text,
  p_status text,
  p_in_trial boolean,
  p_source text,
  p_product_id text,
  p_original_transaction_id text,
  p_environment text,
  p_current_period_end timestamptz
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := p_user_id;
  v_current licensing.entitlements%rowtype;
begin
  if v_user is null then
    select e.user_id into v_user
    from licensing.entitlements e
    where e.source = p_source and e.original_transaction_id = p_original_transaction_id;
  end if;
  if v_user is null then
    return; -- acquisto non collegato a un account: niente da aggiornare sul server
  end if;

  select * into v_current from licensing.entitlements where user_id = v_user;
  if found
     and p_tier = 'free'
     and v_current.original_transaction_id is distinct from p_original_transaction_id
     and v_current.status in ('active', 'trial', 'grace')
     and (v_current.current_period_end is null or v_current.current_period_end > now()) then
    return; -- l'utente ha un altro abbonamento ancora valido: questa notifica non lo tocca
  end if;

  -- la stessa transazione originale non puo' restare collegata a due utenti
  update licensing.entitlements
     set original_transaction_id = null
   where source = p_source and original_transaction_id = p_original_transaction_id and user_id <> v_user;

  insert into licensing.entitlements as e
    (user_id, tier, status, in_trial, source, product_id, original_transaction_id, environment, current_period_end)
  values
    (v_user, p_tier, p_status, p_in_trial, p_source, p_product_id, p_original_transaction_id, p_environment, p_current_period_end)
  on conflict (user_id) do update set
    tier = excluded.tier,
    status = excluded.status,
    in_trial = excluded.in_trial,
    source = excluded.source,
    product_id = excluded.product_id,
    original_transaction_id = excluded.original_transaction_id,
    environment = excluded.environment,
    current_period_end = excluded.current_period_end;
end;
$$;

revoke all on function public.licensing_apply_entitlement(uuid, text, text, boolean, text, text, text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.licensing_apply_entitlement(uuid, text, text, boolean, text, text, text, text, timestamptz) to service_role;
