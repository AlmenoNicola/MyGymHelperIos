-- =====================================================================
-- MyGymHelper - schema database per Supabase (PostgreSQL)
-- Esegui l'intero file nel SQL Editor di Supabase.
-- Due parti: (1) database dell'app nello schema public,
--            (2) database delle licenze nello schema licensing (non esposto all'app).
-- I dati sanitari (peso, schede, piani alimentari, storico) NON stanno qui:
-- restano solo sul telefono dell'utente.
-- =====================================================================

-- ---------- Funzione comune ----------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- =====================================================================
-- 1) DATABASE DELL'APP (schema public)
-- =====================================================================

-- Profilo account: solo dati non sanitari.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  language text,                         -- lingua preferita (es. 'it', 'en')
  disclaimer_version text,               -- versione del disclaimer accettata
  disclaimer_accepted_at timestamptz,    -- prova di accettazione
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Elenchi di esercizi salvati dall'utente (piani Mid e Full).
create table public.exercise_lists (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  exercise_ids integer[] not null default '{}',   -- id degli esercizi del catalogo
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index exercise_lists_user_idx on public.exercise_lists (user_id);

-- Elenchi precaricati uguali per tutti.
create table public.preset_lists (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,                       -- es. 'chest', 'legs'
  names jsonb not null,                            -- es. {"it":"Petto","en":"Chest"}
  exercise_ids integer[] not null default '{}',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Cache del catalogo costruito dal backend a partire dall'API MuscleWiki.
-- Le condizioni MuscleWiki permettono di tenere i metadati in cache al massimo 30 giorni:
-- il vincolo sotto lo impone. Qui non si salvano mai video o immagini.
create table public.catalog_cache (
  language text primary key,                       -- es. 'it', 'en-us'
  exercises jsonb not null,
  fetched_at timestamptz not null default now(),
  expires_at timestamptz not null,
  constraint catalog_cache_max_30_days
    check (expires_at <= fetched_at + interval '30 days')
);

-- Trigger updated_at
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();
create trigger exercise_lists_updated_at before update on public.exercise_lists
  for each row execute function public.set_updated_at();
create trigger preset_lists_updated_at before update on public.preset_lists
  for each row execute function public.set_updated_at();

-- ---------- Sicurezza a livello di riga (app) ----------
alter table public.profiles enable row level security;
alter table public.exercise_lists enable row level security;
alter table public.preset_lists enable row level security;
alter table public.catalog_cache enable row level security;

create policy "profilo: lettura propria" on public.profiles
  for select to authenticated using ((select auth.uid()) = id);
create policy "profilo: modifica propria" on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create policy "elenchi: lettura propria" on public.exercise_lists
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "elenchi: inserimento proprio" on public.exercise_lists
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "elenchi: modifica propria" on public.exercise_lists
  for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "elenchi: cancellazione propria" on public.exercise_lists
  for delete to authenticated using ((select auth.uid()) = user_id);

create policy "elenchi precaricati: lettura per tutti" on public.preset_lists
  for select to authenticated using (true);

create policy "catalogo: lettura se non scaduto" on public.catalog_cache
  for select to authenticated using (expires_at > now());
-- Scrittura su preset_lists e catalog_cache: solo service role (backend), nessuna policy per l'app.

-- =====================================================================
-- 2) DATABASE DELLE LICENZE (schema licensing)
--    Non va esposto nelle API dati: l'app legge solo la funzione get_my_entitlement().
--    Il backend (Edge Function) scrive usando la connessione diretta o la service role.
-- =====================================================================
create schema if not exists licensing;

-- Diritto attuale di ogni utente (uno per utente).
create table licensing.entitlements (
  user_id uuid primary key references auth.users (id) on delete cascade,
  tier text not null default 'free' check (tier in ('free', 'mid', 'full')),
  status text not null default 'none'
    check (status in ('none', 'trial', 'active', 'grace', 'expired', 'revoked')),
  in_trial boolean not null default false,          -- prova gratuita di 7 giorni
  source text check (source in ('apple', 'google', 'manual')),
  product_id text,                                  -- es. app.mygymhelper.full.yearly
  original_transaction_id text,                     -- id originale dello store
  environment text check (environment in ('production', 'sandbox')),
  current_period_end timestamptz,
  updated_at timestamptz not null default now()
);
create unique index entitlements_store_tx_uidx
  on licensing.entitlements (source, original_transaction_id)
  where original_transaction_id is not null;

-- Registro delle notifiche degli store (App Store Server Notifications V2, Google Play RTDN):
-- serve per controllo e per non elaborare due volte la stessa notifica.
create table licensing.store_events (
  id bigint generated always as identity primary key,
  source text not null check (source in ('apple', 'google')),
  notification_id text not null,
  notification_type text,
  original_transaction_id text,
  user_id uuid references auth.users (id) on delete set null,
  payload jsonb not null,
  received_at timestamptz not null default now(),
  unique (source, notification_id)
);
create index store_events_tx_idx on licensing.store_events (original_transaction_id);

create trigger entitlements_updated_at before update on licensing.entitlements
  for each row execute function public.set_updated_at();

-- Tutto chiuso per l'app: nessuna policy = nessun accesso da anon e authenticated.
alter table licensing.entitlements enable row level security;
alter table licensing.store_events enable row level security;

revoke all on schema licensing from anon, authenticated;
revoke all on all tables in schema licensing from anon, authenticated;
alter default privileges in schema licensing revoke all on tables from anon, authenticated;
grant usage on schema licensing to service_role;
grant all on all tables in schema licensing to service_role;

-- L'app legge SOLO il proprio livello tramite questa funzione.
create or replace function public.get_my_entitlement()
returns table (tier text, status text, in_trial boolean, current_period_end timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select e.tier, e.status, e.in_trial, e.current_period_end
  from licensing.entitlements e
  where e.user_id = auth.uid();
$$;
revoke all on function public.get_my_entitlement() from public, anon;
grant execute on function public.get_my_entitlement() to authenticated;

-- =====================================================================
-- 3) Nuovo utente: crea profilo e licenza Free in automatico
-- =====================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1))
  );
  insert into licensing.entitlements (user_id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
