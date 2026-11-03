-- =====================================================================
-- MyGymHelper - licenze gratuite assegnate a mano (eseguire DOPO le migrazioni precedenti).
--
-- Una licenza gratuita da' un piano (Mid o Full) a un utente fino a una data di fine, senza passare
-- dagli store. Si gestisce SOLO dal SQL Editor di Supabase (ruolo postgres): le funzioni stanno nello
-- schema "licensing", che non e' esposto nelle API, e nessun utente dell'app puo' chiamarle.
--
-- Le licenze manuali sono in una tabella a parte: gli abbonamenti degli store (licensing.entitlements)
-- non le toccano e non vengono toccati. L'app riceve da get_my_entitlement() il piano migliore tra
-- abbonamento dello store ancora valido e licenza gratuita ancora valida.
--
-- USO (SQL Editor):
--   -- assegna (o rinnova/modifica) una licenza Full gratuita fino al 31/12/2026 compreso
--   select * from licensing.grant_free_license('mario.rossi@gmail.com', '2026-12-31');
--   -- licenza Mid, con una nota
--   select * from licensing.grant_free_license('mario.rossi@gmail.com', '2027-06-30', 'mid', 'tester');
--   -- l'utente si puo' indicare anche con il suo id (Authentication > Users > UID)
--   select * from licensing.grant_free_license('8f0c...-....', '2026-12-31');
--   -- revoca subito
--   select * from licensing.revoke_free_license('mario.rossi@gmail.com');
--   -- elenco
--   select * from licensing.free_licenses;
--
-- La data di fine e' compresa: la licenza vale fino alle 23:59:59 di quel giorno, ora italiana.
-- L'utente deve aver gia' fatto l'accesso almeno una volta nell'app (deve esistere in auth.users).
-- =====================================================================

create table if not exists licensing.manual_grants (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  tier text not null default 'full' check (tier in ('mid', 'full')),
  valid_until timestamptz not null,                 -- fine della licenza (esclusa): mezzanotte dopo la data indicata
  note text,                                        -- facoltativa: motivo, chi l'ha chiesta...
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revoked_at timestamptz                            -- valorizzata da revoke_free_license
);
-- Al massimo una licenza manuale non revocata per utente (le revocate restano come storico).
create unique index if not exists manual_grants_one_open_uidx
  on licensing.manual_grants (user_id) where revoked_at is null;

drop trigger if exists manual_grants_updated_at on licensing.manual_grants;
create trigger manual_grants_updated_at before update on licensing.manual_grants
  for each row execute function public.set_updated_at();

-- Chiusa per l'app, come il resto dello schema licensing.
alter table licensing.manual_grants enable row level security;
revoke all on licensing.manual_grants from anon, authenticated;
grant all on licensing.manual_grants to service_role;

-- Trova l'utente da e-mail o da id (testo). Errore se non esiste.
create or replace function licensing.find_user(p_user text)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_id uuid;
  v_text text := btrim(coalesce(p_user, ''));
begin
  if v_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select u.id into v_id from auth.users u where u.id = v_text::uuid;
  else
    select u.id into v_id from auth.users u where lower(u.email) = lower(v_text);
  end if;
  if v_id is null then
    raise exception 'Utente non trovato: %. Deve aver fatto l''accesso almeno una volta nell''app.', v_text;
  end if;
  return v_id;
end;
$$;

-- Assegna una licenza gratuita, oppure aggiorna quella gia' aperta dell'utente (nuova data, piano, nota).
create or replace function licensing.grant_free_license(
  p_user text,                 -- e-mail oppure id dell'utente
  p_end_date date,             -- ultimo giorno di validita' (compreso)
  p_tier text default 'full',  -- 'mid' oppure 'full'
  p_note text default null
) returns table (email text, tier text, valid_until_date date, valid_until timestamptz, note text)
language plpgsql
set search_path = ''
as $$
declare
  v_user uuid := licensing.find_user(p_user);
  v_tier text := lower(btrim(coalesce(p_tier, 'full')));
  v_until timestamptz;
begin
  if v_tier not in ('mid', 'full') then
    raise exception 'Piano non valido: % (usa ''mid'' o ''full'')', p_tier;
  end if;
  if p_end_date is null or p_end_date < (now() at time zone 'Europe/Rome')::date then
    raise exception 'La data di fine deve essere oggi o nel futuro';
  end if;
  -- fine compresa: vale fino a mezzanotte (ora italiana) del giorno dopo
  v_until := ((p_end_date + 1)::timestamp) at time zone 'Europe/Rome';

  update licensing.manual_grants g
     set tier = v_tier, valid_until = v_until, note = coalesce(p_note, g.note)
   where g.user_id = v_user and g.revoked_at is null;
  if not found then
    insert into licensing.manual_grants (user_id, tier, valid_until, note)
    values (v_user, v_tier, v_until, p_note);
  end if;

  return query
    select u.email::text, g.tier, p_end_date, g.valid_until, g.note
    from licensing.manual_grants g join auth.users u on u.id = g.user_id
    where g.user_id = v_user and g.revoked_at is null;
end;
$$;

-- Revoca subito la licenza gratuita aperta dell'utente. Restituisce quante licenze sono state revocate (0 o 1).
create or replace function licensing.revoke_free_license(p_user text)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_user uuid := licensing.find_user(p_user);
  v_count integer;
begin
  update licensing.manual_grants
     set revoked_at = now()
   where user_id = v_user and revoked_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Elenco delle licenze gratuite (le piu' recenti prima). "attiva" = non revocata e non scaduta.
create or replace view licensing.free_licenses as
  select u.email::text as email,
         g.user_id,
         g.tier,
         ((g.valid_until at time zone 'Europe/Rome') - interval '1 day')::date as ultimo_giorno,
         (g.revoked_at is null and g.valid_until > now()) as attiva,
         g.note,
         g.created_at,
         g.revoked_at
  from licensing.manual_grants g
  join auth.users u on u.id = g.user_id
  order by g.created_at desc;

revoke all on licensing.free_licenses from anon, authenticated;
revoke all on function licensing.find_user(text) from public, anon, authenticated;
revoke all on function licensing.grant_free_license(text, date, text, text) from public, anon, authenticated;
revoke all on function licensing.revoke_free_license(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- get_my_entitlement(): ora restituisce il piano EFFETTIVO dell'utente collegato:
-- il migliore tra abbonamento dello store ancora valido e licenza gratuita ancora valida.
-- Nuova colonna "source" ('apple', 'google', 'manual' o null): l'app la usa per mostrare
-- "Licenza gratuita fino al ..." nella schermata dei piani. Senza nulla di valido: free / none.
-- ---------------------------------------------------------------------
drop function if exists public.get_my_entitlement();
create function public.get_my_entitlement()
returns table (tier text, status text, in_trial boolean, current_period_end timestamptz, source text)
language sql
stable
security definer
set search_path = ''
as $$
  with candidates as (
    select e.tier, e.status, e.in_trial, e.current_period_end, e.source
    from licensing.entitlements e
    where e.user_id = auth.uid()
      and e.tier <> 'free'
      and e.status in ('active', 'trial', 'grace')
      and (e.current_period_end is null or e.current_period_end > now())
    union all
    select g.tier, 'active', false, g.valid_until, 'manual'
    from licensing.manual_grants g
    where g.user_id = auth.uid()
      and g.revoked_at is null
      and g.valid_until > now()
    union all
    select 'free', 'none', false, null::timestamptz, null::text
    where auth.uid() is not null
  )
  select c.tier, c.status, c.in_trial, c.current_period_end, c.source
  from candidates c
  order by case c.tier when 'full' then 2 when 'mid' then 1 else 0 end desc,
           c.current_period_end desc nulls first
  limit 1;
$$;
revoke all on function public.get_my_entitlement() from public, anon;
grant execute on function public.get_my_entitlement() to authenticated;
