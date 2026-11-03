-- =====================================================================
-- MyGymHelper - funzioni per il backend delle licenze (eseguire DOPO lo schema).
-- Lo schema "licensing" non e' esposto nelle API: le Edge Functions (service role)
-- lo scrivono tramite queste funzioni, che nessun utente dell'app puo' chiamare.
-- =====================================================================

-- Registra una notifica dello store una sola volta. Restituisce false se era gia' stata elaborata.
create or replace function public.licensing_record_event(
  p_source text,
  p_notification_id text,
  p_notification_type text,
  p_original_transaction_id text,
  p_user_id uuid,
  p_payload jsonb
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into licensing.store_events (source, notification_id, notification_type, original_transaction_id, user_id, payload)
  values (p_source, p_notification_id, p_notification_type, p_original_transaction_id, p_user_id, p_payload);
  return true;
exception when unique_violation then
  return false;
end;
$$;

-- Aggiorna il diritto di un utente. Se l'utente non e' noto (acquisto senza account),
-- si aggiorna la riga gia' collegata alla stessa transazione originale, se esiste.
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
begin
  if v_user is null then
    select e.user_id into v_user
    from licensing.entitlements e
    where e.source = p_source and e.original_transaction_id = p_original_transaction_id;
  end if;
  if v_user is null then
    return; -- acquisto non collegato a un account: niente da aggiornare sul server
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

revoke all on function public.licensing_record_event(text, text, text, text, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.licensing_apply_entitlement(uuid, text, text, boolean, text, text, text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.licensing_record_event(text, text, text, text, uuid, jsonb) to service_role;
grant execute on function public.licensing_apply_entitlement(uuid, text, text, boolean, text, text, text, text, timestamptz) to service_role;
