# Backend Supabase – configurazione passo per passo

Il backend è facoltativo per far funzionare l'app (senza, l'app usa l'elenco esercizi incluso e non mostra l'account),
ma serve per: account, catalogo MuscleWiki, collegamento degli abbonamenti all'utente, cancellazione dell'account.
I dati sanitari non passano mai dal backend.

Stato: lo schema SQL e le funzioni di licenza sono stati **eseguiti su un PostgreSQL di prova** (con una tabella
`auth.users` simulata); le quattro Edge Functions passano il **controllo dei tipi di Deno** (`deno check`).
Non sono ancora state eseguite su un progetto Supabase vero né chiamate da Apple o MuscleWiki.

## 0. Partenza rapida (per provare l'accesso sui telefoni)
Senza un progetto Supabase l'app funziona, ma la voce **Account** in Info non compare (nelle build di debug c'è
un avviso). Per provare accesso con e-mail, Google, Facebook (e Apple su iPhone):
1. supabase.com > New project (regione UE, es. Francoforte; piano Free). Annota la password del database.
2. SQL Editor: esegui le tre migrazioni della sezione 1 (in ordine).
3. Project Settings > API: copia **Project URL** e chiave **anon public** (MAI la `service_role`).
4. Android, file `android/local.properties`:
   `supabase.url=https://<ref>.supabase.co` e `supabase.anonKey=<chiave anon>`. Ricompila.
5. iOS, file `Support/Info.plist`: `MyGymHelperSupabaseURL` e `MyGymHelperSupabaseAnonKey` con gli stessi valori.
6. Authentication > URL Configuration > Redirect URLs: aggiungi `mygymhelper://login-callback`.
7. Attiva i metodi di accesso (sezione 2): Google, Facebook e Apple (solo iOS) richiedono le chiavi dei rispettivi servizi.
   L'accesso con **e-mail e codice è spento nelle app**: dal 3 giugno 2026 i nuovi progetti Free non possono modificare
   il modello dell'e-mail (che deve contenere `{{ .Token }}`) senza un servizio e-mail proprio (SMTP). Per riattivarlo:
   SMTP proprio in Authentication > Emails > SMTP Settings, modello Magic Link con `{{ .Token }}`, poi
   `auth.email=true` in `local.properties` e `MyGymHelperEmailLogin` = YES in `Support/Info.plist`.
8. Facebook: dopo averlo configurato metti `auth.facebook=true` in `local.properties` (Android) e
   `MyGymHelperFacebookLogin` = YES in `Support/Info.plist` (iOS); finché è spento il pulsante non compare.

## 1. Progetto e database
1. Crea un progetto su supabase.com (regione UE, per esempio Francoforte).
2. SQL Editor: esegui in ordine `supabase/migrations/20261018000000_schema.sql`,
   `supabase/migrations/20261020000000_licensing_functions.sql`, `supabase/migrations/20261021000000_google_play.sql`,
   `supabase/migrations/20261028090000_exercise_images.sql` e `supabase/migrations/20261103000000_manual_licenses.sql`
   (oppure, con la CLI: `supabase link --project-ref <ref>` e `supabase db push`).
3. Lascia lo schema `licensing` **fuori** dalle API esposte (Project Settings > API > Exposed schemas: solo `public`).

## 2. Accesso (Authentication)
- **E-mail con codice**: Authentication > Providers > Email attivo. In Email Templates > "Magic Link" usa un testo
  che contenga il codice `{{ .Token }}` (l'app chiede il codice a 6 cifre, non apre link).
- **Apple**: Providers > Apple attivo; in "Client IDs" metti il bundle id `app.mygymhelper`
  (accesso nativo dall'app: non servono chiave segreta né redirect).
- **Google**: Providers > Google attivo con Client ID e Secret creati in Google Cloud (tipo "Web application",
  redirect `https://<ref>.supabase.co/auth/v1/callback`).
- Authentication > URL Configuration > Redirect URLs: aggiungi `mygymhelper://login-callback`.
- **Facebook** (Android e iOS, senza SDK di Facebook: l'accesso si apre nel browser e torna all'app):
  1. developers.facebook.com > Le mie app > Crea app; caso d'uso "Autenticazione e creazione di account con
     Facebook Login" (i nomi dei menu di Meta cambiano spesso).
  2. Facebook Login > Impostazioni: in "URI di reindirizzamento OAuth validi" metti
     `https://<ref>.supabase.co/auth/v1/callback`.
  3. Impostazioni > Di base: copia **ID app** e **Chiave segreta**; in Supabase > Authentication > Providers >
     Facebook attivalo e incollale. Permessi usati: `email` e `public_profile`.
  4. Finché l'app Meta è in modalità **sviluppo** possono entrare solo gli account aggiunti come amministratori,
     sviluppatori o tester (App roles). Per pubblicarla Meta chiede: URL dell'informativa privacy, URL o istruzioni
     per la **cancellazione dei dati** degli utenti, icona, categoria ed eventualmente la verifica dell'attività.
  5. Nell'app: `auth.facebook=true` (Android, `local.properties`) e `MyGymHelperFacebookLogin` = YES (iOS).
  Nota: chi entra con Facebook senza un'e-mail verificata su Facebook potrebbe non avere l'indirizzo e-mail
  nell'account (Supabase lo mostra vuoto).

## 3. Segreti delle funzioni
```
supabase secrets set MUSCLEWIKI_API_KEY=mw_...        # piano a pagamento MuscleWiki (uso commerciale)
supabase secrets set APPLE_BUNDLE_ID=app.mygymhelper
supabase secrets set APPLE_APP_ID=1234567890           # Apple ID numerico dell'app (App Store Connect > Informazioni app)
supabase secrets set APPLE_TEAM_ID=ABCDE12345          # Team ID dell'account sviluppatore
supabase secrets set APPLE_SIGNIN_KEY_ID=XYZ123ABCD    # Key ID della chiave "Sign in with Apple"
supabase secrets set APPLE_SIGNIN_PRIVATE_KEY="$(cat AuthKey_XYZ123ABCD.p8)"
supabase secrets set CATALOG_CACHE_DAYS=14             # facoltativo, massimo 30
supabase secrets set CATALOG_MAX_EXERCISES=300         # facoltativo
```
`SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` sono già disponibili nelle funzioni.

## 4. Pubblicare le funzioni
```
supabase functions deploy catalog   # solo se AppFlags.MUSCLEWIKI_CATALOG = true (oggi spento)
supabase functions deploy apple-notifications --no-verify-jwt
supabase functions deploy delete-account
supabase functions deploy google-play-notifications --no-verify-jwt
```
- `catalog`: `GET /functions/v1/catalog?lang=it`. Cache in `public.catalog_cache` (massimo 30 giorni, vincolo nel DB);
  se la lingua non è nel tuo piano MuscleWiki ripiega sull'inglese; non salva video o immagini.
- `apple-notifications`: verifica la firma con la libreria ufficiale Apple (`@apple/app-store-server-library`)
  e i certificati radice Apple; aggiorna `licensing.entitlements` dell'utente indicato da `appAccountToken`.
- `delete-account`: elimina l'utente che la chiama (profilo, elenchi e diritto si cancellano a cascata).
  Per chi è entrato con Apple, l'app chiede prima di confermare con Apple e invia il codice di autorizzazione:
  la funzione lo scambia con Apple e **revoca i token Apple** (`/auth/token` + `/auth/revoke`), senza salvarli.
  Se la revoca non riesce l'account viene eliminato comunque e l'errore resta nei log.
  Test della parte Apple: `deno test --allow-env supabase/functions/_shared/apple_test.ts` (3 test, passano).

## 5. Collegare l'app
In `Support/Info.plist`: `MyGymHelperSupabaseURL` = `https://<ref>.supabase.co` e
`MyGymHelperSupabaseAnonKey` = chiave "anon" (Project Settings > API). La chiave anon è pubblica per progetto:
la sicurezza è data dalle regole RLS. **Non mettere mai nell'app la service role key.**

## 6. App Store Connect
App > Informazioni app > App Store Server Notifications: versione 2, URL di produzione e di sandbox =
`https://<ref>.supabase.co/functions/v1/apple-notifications`. Poi "Richiedi notifica di test" e controlla
la tabella `licensing.store_events`.

## 7. Da completare prima del rilascio
- **Chiave "Sign in with Apple"**: Certificates, Identifiers & Profiles > Keys > nuova chiave con "Sign in with Apple"
  collegata all'App ID `app.mygymhelper`; scarica il file .p8 (si scarica una sola volta) e imposta i tre segreti
  `APPLE_TEAM_ID`, `APPLE_SIGNIN_KEY_ID`, `APPLE_SIGNIN_PRIVATE_KEY`. Senza, l'account si elimina ma la revoca non avviene.
- Monitoraggio: Supabase > Edge Functions > Logs.

## 8. Google Play (app Android)
La funzione `google-play-notifications` riceve le notifiche in tempo reale di Google Play tramite Pub/Sub,
verifica il token OIDC di Pub/Sub, rilegge lo stato dell'abbonamento con la Google Play Developer API
(`purchases.subscriptionsv2.get`) e aggiorna `licensing.entitlements` dell'utente indicato da
`obfuscatedExternalAccountId` (= id utente Supabase, impostato dall'app negli acquisti). Stessa tabella degli
abbonamenti Apple: `source = 'google'`.

1. Google Cloud (stesso progetto collegato a Play Console): attiva le API "Google Play Android Developer API" e "Pub/Sub".
2. Pub/Sub: crea l'argomento `play-notifications`; in Autorizzazioni dai a
   `google-play-developer-notifications@system.gserviceaccount.com` il ruolo **Publisher Pub/Sub**.
3. Crea un account di servizio per l'autenticazione push (es. `pubsub-push@<progetto>.iam.gserviceaccount.com`).
4. Crea una sottoscrizione **push** sull'argomento: endpoint
   `https://<ref>.supabase.co/functions/v1/google-play-notifications`, "Abilita autenticazione" con l'account del punto 3,
   pubblico (audience) = lo stesso URL.
5. Play Console > Monetizza > Configurazione della monetizzazione > Notifiche in tempo reale: nome dell'argomento
   `projects/<progetto>/topics/play-notifications`, poi "Invia messaggio di prova" (compare in `licensing.store_events`
   con tipo `TEST`).
6. Account di servizio per la Play Developer API: vedi `docs/ANDROID.md` sezione 5, punto 4 (chiave JSON).
7. Segreti:
```
supabase secrets set GOOGLE_PLAY_PACKAGE=app.mygymhelper
supabase secrets set GOOGLE_PLAY_SERVICE_ACCOUNT="$(cat chiave-account-di-servizio.json)"
supabase secrets set GOOGLE_PUBSUB_SERVICE_ACCOUNT=pubsub-push@<progetto>.iam.gserviceaccount.com
supabase secrets set GOOGLE_PUBSUB_AUDIENCE=https://<ref>.supabase.co/functions/v1/google-play-notifications   # facoltativo
```
- Stati: attivo/prova → accesso; annullato → accesso fino alla scadenza; periodo di tolleranza → accesso;
  sospeso, in pausa, scaduto → nessun accesso; rimborso o revoca → `revoked`.
- La migrazione `20261021000000_google_play.sql` evita che la scadenza del vecchio acquisto, dopo un cambio
  Mid → Full, tolga il piano nuovo (e che un abbonamento scaduto su uno store tolga quello attivo sull'altro).
- `delete-account` dall'app Android invia `{"platform":"android"}`: se l'account era stato creato su iPhone con Apple,
  la revoca dei token Apple non è possibile da Android (l'account si elimina comunque; resta un avviso nei log).
- Test: `deno test supabase/functions/_shared/google_test.ts` (6 test, passano).

## 9. Licenze gratuite assegnate a mano
Per dare a qualcuno Mid o Full gratis fino a una data, senza passare dagli store. Si fa solo dal **SQL Editor**
di Supabase (le funzioni sono nello schema `licensing`, non raggiungibile dall'app). Serve la migrazione
`20261103000000_manual_licenses.sql`.

```sql
-- Full gratis fino al 31/12/2026 compreso (l'utente si indica con l'e-mail dell'account o con il suo UID)
select * from licensing.grant_free_license('nome@esempio.it', '2026-12-31');
-- Mid, con una nota
select * from licensing.grant_free_license('nome@esempio.it', '2027-06-30', 'mid', 'beta tester');
-- Rinnovo o cambio: si richiama grant_free_license con la nuova data/piano (aggiorna la licenza aperta)
-- Revoca immediata
select licensing.revoke_free_license('nome@esempio.it');
-- Elenco (attiva = non revocata e non scaduta)
select * from licensing.free_licenses;
```
- L'utente deve aver già fatto l'accesso almeno una volta nell'app (deve esistere in Authentication > Users).
- La data di fine è compresa: la licenza vale fino alle 23:59:59 di quel giorno, ora italiana. Alla scadenza
  l'app torna da sola al piano dello store (o Free), senza fare nulla.
- Una sola licenza aperta per utente; quelle revocate restano nella tabella `licensing.manual_grants` come storico.
- `get_my_entitlement()` restituisce il piano migliore tra abbonamento dello store valido e licenza gratuita valida,
  con la colonna `source` (`manual` per la licenza gratuita). Le notifiche degli store non toccano le licenze manuali.
- Nell'app: il piano si rilegge all'avvio, all'accesso/uscita e al ritorno nell'app; in Piani compare
  "Licenza gratuita fino al …". Senza rete vale l'ultimo piano letto, fino alla scadenza e per al massimo 14 giorni.

