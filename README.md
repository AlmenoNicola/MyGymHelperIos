# MyGymHelper – app iOS e Android

Ex "PalestrApp" (nome provvisorio). Nessun commit è stato fatto: copia i file nella tua repo quando vuoi.
**Il codice Swift NON è mai stato compilato e i test Swift NON sono stati eseguiti** (l'ambiente di lavoro non ha Swift/Xcode):
al primo build potrebbero servire correzioni. L'app Android compila e gira sul telefono (prove dell'utente).

## Struttura
```
MyGymHelper/
├── MyGymHelper.xcodeproj   progetto Xcode 26 pronto (cartella App/ sincronizzata + pacchetto locale Core)
├── project.yml             riserva: rigenera il progetto con XcodeGen se il .xcodeproj non si apre
├── App/                    sorgenti SwiftUI, Assets, Localizable.xcstrings (it/en), exercises_seed.json, Legal/*.md
├── Core/                   Swift Package "MyGymHelperCore": logica pura + test (da riscrivere uguale in Kotlin)
├── Support/                Info.plist (chiavi), MyGymHelper.entitlements (Salute, Accedi con Apple), MyGymHelper.storekit
├── android/                app Android (Kotlin, Jetpack Compose, Android 9+): vedi docs/ANDROID.md
├── supabase/               migrazioni SQL, Edge Functions (catalog, apple-notifications, google-play-notifications,
│                           delete-account), config.toml
└── docs/                   HANDOFF.md, BACKEND.md, ANDROID.md, STORE_TEXTS.md, ADEMPIMENTI_LEGALI.md, mygymhelper_schema.sql
```

## Android
Stesse funzioni e stessi piani, con Google Play (abbonamenti), Health Connect (al posto di Apple Salute) e accesso
con Google, Facebook o e-mail. Guida completa: `docs/ANDROID.md`. Il modulo `android/core` (logica) è compilato e testato
(70 test superati); l'app Android si compila in Android Studio.

## Primo avvio sul Mac
1. Apri `MyGymHelper.xcodeproj` con Xcode 26. Il pacchetto `Core` viene risolto in automatico (pacchetto locale).
   Se il progetto non si apre: `brew install xcodegen && xcodegen generate` nella cartella, poi apri il progetto generato.
2. Target MyGymHelper > Signing & Capabilities: scegli il tuo Team (il bundle id è `app.mygymhelper`, cambialo se serve).
3. Abbonamenti in locale: Product > Scheme > Edit Scheme > Run > Options > StoreKit Configuration = `MyGymHelper.storekit`.
4. Compila (⌘B) e correggi gli eventuali errori. Già impostati: iOS 26, Swift 5, Default Actor Isolation = nonisolated,
   `NSMotionUsageDescription`, nome visualizzato "MyGymHelper", solo iPhone, verticale, tema scuro.
5. Test della logica: `cd Core && swift test` (oppure apri `Core/Package.swift` in Xcode e premi ⌘U).
6. `Support/Info.plist`: contatto reale in `MyGymHelperContactEmail` (User-Agent di Open Food Facts),
   `MyGymHelperPrivacyURL` = pagina web pubblica con l'informativa, `MyGymHelperSupabaseURL` e
   `MyGymHelperSupabaseAnonKey` quando il backend è pronto (vedi `docs/BACKEND.md`; vuote = niente account).
   Xcode scarica da solo il pacchetto `supabase-swift` al primo build (serve internet).
   Signing & Capabilities: devono comparire HealthKit e Sign in with Apple (dal file entitlements).
7. Prova su iPhone vero (il simulatore non ha i sensori di movimento).

## Cosa fa l'app
- **Allenamento**: scelta braccio/gamba, esercizio facoltativo, serie/ripetizioni/pausa/peso (passo 1,25 kg),
  conteggio automatico con i sensori, avvisi a voce/suono/vibrazione, "mi sono fermato", storico (solo con consenso).
  Consigli: Mid a regole fisse, Full adattivi (storico + scheda caricata) con pulsante "Applica".
- **Esercizi**: mappa del corpo fronte/retro e blocchi per zona, catalogo (Free: uno per gruppo muscolare),
  consigli sugli esercizi (Mid+), elenchi preimpostati e salvati (Mid+), schede di allenamento (Full).
- **Schede (Full)**: importazione da PDF, Excel (.xlsx), Word (.docx), CSV, foto o testo, tutto sul telefono (PDFKit, OCR Vision, `OfficeText` nel Core); tabelle con colonne Esercizio/Serie/Ripetizioni/Peso/Recupero, schermata di revisione
  modificabile prima del salvataggio, dettaglio con avvio dell'esercizio, modifica ed eliminazione. AI locale: non attiva.
- **Nutrizione**: profilo (solo con consenso), BMI (Free), fabbisogno calorie/macro e ricerca alimenti Open Food Facts (Mid+),
  pasti per dieta e giorno di allenamento senza ricette (Full), scheda del nutrizionista importata e rivista (Full).
- **Piani**: schermata ufficiale StoreKit (`SubscriptionStoreView`) con prezzo, durata, prova gratuita solo a chi
  ne ha diritto, link a privacy e condizioni, ripristino e gestione dell'abbonamento; confronto Free/Mid/Full.
- **Info**: account (facoltativo: Apple, Google, Facebook, e-mail con codice; uscita ed eliminazione), Apple Salute,
  documenti legali (italiano e inglese), consenso, fonti dei dati, cancellazione dei dati locali.
- **Apple Salute** (facoltativa, con consenso): scrive gli allenamenti di forza, importa peso e altezza su richiesta.
- **Lingue**: interfaccia in inglese e italiano (lingua di sviluppo inglese: chi ha il telefono in altre lingue
  vede l'inglese); testi legali in italiano e inglese (bozze da far verificare).

## Da sapere
- **MuscleWiki**: la chiave non va mai nell'app; serve il backend (vedi `docs/HANDOFF.md`, sezione 7). Cache max 30 giorni,
  niente immagini/video salvati, attribuzione obbligatoria, uso commerciale solo a pagamento.
- **Open Food Facts**: dati ODbL, attribuzione mostrata nella ricerca e in Info; si inviano solo le parole cercate.
- **Soglie del rilevatore** (`RepDetectorConfig`) e **coefficienti nutrizionali**: indicativi, da tarare e far rivedere.
- **Testi legali**: bozze solo in italiano, da far verificare a un legale (`docs/ADEMPIMENTI_LEGALI.md`).
- **Prova gratuita di 7 giorni**: in App Store Connect come offerta introduttiva sul gruppo di abbonamento
  (nel file `.storekit` è già impostata per le prove in locale).
