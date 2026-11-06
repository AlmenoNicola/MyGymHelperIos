# MyGymHelper (ex PalestrApp) – documento di passaggio (handoff)

Scopo: permettere a un altro assistente (o sviluppatore) di capire tutto quello che è stato deciso e fatto, di ricreare
l'app da zero se serve e di completarla. Il codice sorgente della fase 1 era nello zip `PalestrApp-fase1.zip`; quello attuale è la cartella `MyGymHelper`; questo documento spiega
cosa c'è, perché, a che punto è e cosa manca. Data dello stato descritto: 18 ottobre 2026.

> **Aggiornamento 19 ottobre 2026 (fase 2)**: l'app si chiama **MyGymHelper** (pacchetto `MyGymHelperCore`, ID prodotto
> `app.mygymhelper.*`, chiave Info.plist `MyGymHelperBackendURL`). Il blocco 9.A è stato completato e c'è un progetto Xcode
> pronto: vedi la sezione 12. Le sezioni 1–11 descrivono lo stato del 18 ottobre (con i nomi aggiornati).

> Stato in una riga (18 ottobre): la logica (Core) è scritta e coperta da test **mai eseguiti**; l'app SwiftUI è scritta ma **mai
> compilata**; la parte "esercizi/coaching/schede/alimentazione" è **a metà** (vedi sezione 9).

---

## 1. Obiettivo del prodotto

App iOS (Swift) per allenamento personale, con rewrite futuro per Android. Specifiche originali (italiano):

- Il telefono si lega al braccio o alla gamba; in base a velocità e blocchi l'app conta ripetizioni e serie e consiglia
  se cambiare serie, pesi e tempi di riposo. Può contare da sola o farsi dire i dati dall'utente. Avvisa quando
  ricominciare e quando finire; se l'utente si ferma prima, segna quante ripetizioni ha fatto.
- Spiega gli esercizi (API gratuite) e consiglia quelli migliori in base agli esercizi fatti e ai muscoli scelti.
- Prende altezza, sesso, peso per BMI e consiglio di piano alimentare (calcolato + API gratuite).
- Tre livelli di pagamento: Free (solo conteggio impostato dall'utente), Mid (conteggio + consigli sugli esercizi in
  base alle serie fatte), Full (tutta l'app). Gestione di licenze e pagamenti.
- Salvataggio dei piani di allenamento e del tipo di dieta (onnivora, vegetariana, gluten free, vegana, senza lattosio).
- Selezione dei muscoli su modello fronte/retro oppure con blocchi (braccia, gambe, torace...).

## 2. Decisioni prese dall'utente (registro)

Piattaforma e strumenti
- iOS 26 minimo (da iPhone 11 in su), Swift, SwiftUI, SwiftData, StoreKit 2. Ha un Mac con Xcode; sviluppa abitualmente su Windows.
- Repo GitHub privata `andrealmeno/Palestrapp`, attualmente vuota: i commit li fa l'utente. **Non fare commit.**
- Nome provvisorio "MyGymHelper" (sviluppo riservato, verrà cambiato). Nessuna scadenza.
- Lingua dell'app = lingua del telefono; mercato internazionale. UI e commenti del progetto in italiano (con inglese nel catalogo stringhe).

Piani e prezzi
- Free: conteggio con serie/ripetizioni/pausa impostati dall'utente + BMI + catalogo con un esercizio per tipologia.
- Mid: catalogo completo, elenchi salvati, consigli a regole fisse, indicazioni alimentari generali, Apple Watch.
- Full: consigli adattivi, caricamento scheda di allenamento e scheda del nutrizionista, piano alimentare per dieta e
  allenamento, uso offline completo, sincronizzazione cloud (in futuro).
- Prezzi: Mid 4,99 €/mese e 49,99 €/anno; Full 9,99 €/mese e 99,99 €/anno. Prova gratuita di 7 giorni alla prima
  iscrizione (offerta introduttiva sul gruppo di abbonamento in App Store Connect).

Dati e privacy
- Dati sanitari **solo sul telefono** per impostazione predefinita (sincronizzazione cloud da decidere in futuro).
  Condivisione con Apple Salute solo con consenso. Backup e cambio telefono: punto aperto.
- Login con email, Google e Apple ID (Apple solo iOS) su Supabase (piano free all'inizio). Licenze in un database/schema separato.
- Lettura schede con Vision e PDFKit; modello AI **locale** (ipotesi Gemma 3 270M) solo dopo consenso, leggero.
- Disclaimer (non sostituisce nutrizionista, personal trainer, medici) in tre punti: prima installazione, sezione Info,
  descrizione dell'app. Nessuna ricetta (copyright). Testi legali forniti dall'utente (da un'altra AI), da far
  verificare a un legale.

Fonti dati
- Alimenti: Open Food Facts. Esercizi: l'utente voleva l'API MuscleWiki al posto del dataset di opengym.
- opengym (AGPL-3.0): solo come spunto, nessun codice copiato. Immagini/GIF degli esercizi: **proprie** (niente licenza Gym visual).
- Altri smartwatch (altri SDK): in futuro. Apple Watch: previsto già nel Mid.

## 3. Vincoli e scoperte su licenze e servizi (da rispettare)

- **opengym** (alexpcosta/opengym, fork di DuarteSantos8/openGym): AGPL-3.0, React/Node/Capacitor. Copiare o tradurre
  il suo codice renderebbe l'app AGPL con sorgente pubblico: vietato. Non usa API esterne (legge un dataset in locale).
- **Dataset hasaneyldrm/exercises-dataset**: testi e metadati MIT; GIF/immagini © Gym visual (serve licenza a parte).
  Non usato nel codice; possibile riserva solo per i testi.
- **MuscleWiki API** (api.musclewiki.com/api-terms): piano gratuito solo "Playground" (nessuna chiave per l'app); uso
  commerciale solo a pagamento; lingue oltre l'inglese dal piano GROWTH; chiave mai nell'app (serve un backend);
  cache dei metadati max 30 giorni (quindi catalogo offline max 30 giorni); vietato salvare video/immagini e usare i
  contenuti per addestrare modelli AI; attribuzione richiesta ("Exercise data and videos provided by MuscleWiki.com");
  termini revocabili, prezzi modificabili con preavviso. Il nome dei muscoli restituiti va verificato con dati reali
  (`MuscleGroup(apiName:)` è tollerante ma non testato su risposte vere).
- **MuscleMap** (melihcolpan, MIT, Swift): citata dal NOTICE di opengym come origine della geometria del corpo; **non
  verificata né usata**. La mappa del corpo nell'app è disegnata da noi (figura anatomica vettoriale dal 27 ottobre 2026, vedi 17.4 punto 8).
- **Open Food Facts**: dati ODbL (attribuzione/condivisione); richiede User-Agent identificativo. Da verificare prima del rilascio.
- **Gemma 3 270M**: termini d'uso propri (non è una licenza open source standard): da verificare. Su iPhone 11 il
  modello Apple "Foundation Models" di iOS 26 non è disponibile (richiede Apple Intelligence): serve un runtime
  esterno (Core ML, MLX o llama.cpp) da misurare su un iPhone 11 vero.
- **GDPR**: peso/altezza/schede/piani sono dati sanitari; consenso esplicito separato, cancellazione in-app, backup
  esclusi. AI Act e dispositivi medici: vedere `docs/ADEMPIMENTI_LEGALI.md`. Non è consulenza legale.

## 4. Ambiente di lavoro e metodo

- L'assistente lavora in un ambiente Linux **senza Swift/Xcode**: nessun file è stato compilato né i test Swift sono stati
  eseguiti. Per la logica più delicata (rilevatore ripetizioni, macchina a stati della sessione, parser delle schede)
  è stato verificato un equivalente in **Python** sugli stessi casi dei test; è una verifica del ragionamento, non del Swift.
- Primo passo sul Mac: aprire Xcode 26, importare i file, compilare, eseguire `swift test` nel pacchetto Core e correggere gli errori.
- Impostazioni attese: Swift tools 6.2, `swiftLanguageModes: [.v5]` nel pacchetto; nel target app **Default Actor
  Isolation = nonisolated** e Swift Language Mode 5 (il codice dei sensori gira su una coda in background).
- Info.plist: `NSMotionUsageDescription` (obbligatoria); `MyGymHelperBackendURL` (facoltativa: attiva il catalogo da backend).

## 5. Architettura

```
MyGymHelper/
├── Core/                         Pacchetto Swift "MyGymHelperCore" (nessuna dipendenza da UI; da riscrivere identico in Kotlin)
│   ├── Package.swift             iOS 26, macOS 14 (per i test), swiftLanguageModes [.v5]
│   ├── Sources/MyGymHelperCore/   (vedi 5.1)
│   └── Tests/MyGymHelperCoreTests/ CoreTests, SessionEngineTests, FeatureTests
├── App/                          File SwiftUI da mettere nel target iOS (vedi 5.2) + Localizable.xcstrings + exercises_seed.json + Legal/*.md
├── docs/                         ADEMPIMENTI_LEGALI.md, mygymhelper_schema.sql, HANDOFF.md
└── README.md                     passi per mettere tutto in Xcode
```

### 5.1 Core (file, ruolo, stato)

| File | Contenuto | Stato |
| --- | --- | --- |
| Tier.swift | `SubscriptionTier` (free<mid<full), `Feature`, `FeatureGate` | scritto, testato (test) |
| BMI.swift | `BMICalculator` (categorie OMS adulti) | scritto, testato |
| Nutrition.swift | Mifflin-St Jeor, `ActivityLevel`, `Goal`, `DietType`, `DailyTargets` | scritto, testato |
| RepDetector.swift | `Vector3`, `PrincipalAxis`, `RepDetector`, `RepDetectorConfig` | scritto; verificato in Python |
| SessionEngine.swift | macchina a stati: `SessionPhase`, `SessionCue`, `SetRecord`, `SessionEngine` | scritto; verificato in Python |
| Progression.swift | `SetOutcome`, `FixedCoaching` (regole Mid) | scritto, testato |
| Exercises.swift | `Exercise` (DTO API stile MuscleWiki), protocollo `ExerciseProvider` | scritto |
| CachedExerciseProvider.swift | cache su disco (max 30 giorni) + `BackendExerciseProvider` (endpoint `/catalog?lang=`) | scritto, non testato |
| Muscles.swift | `MuscleGroup` (14), `BodyRegion` (6), mappatura dai nomi API | scritto, testato |
| Catalog.swift | `CatalogExercise`, `SeedCatalog`, `Exercise.toCatalog()`, `CatalogAccess` (regola Free), `ExerciseMatcher` | scritto, testato |
| Recommender.swift | `ExerciseRecommender` (consigli esercizi Mid/Full) | scritto, testato |
| AdaptiveCoach.swift | `AdaptiveCoach` (consigli adattivi Full), `PlanTarget`, `SessionSample` | scritto, testato |
| PlanParser.swift | `TrainingPlanParser`, `NutritionPlanParser`, `PlanAIOutput` (validazione JSON dal modello AI) | scritto; regex verificate in Python |
| Diet.swift | `DietPlanner`, alimenti per dieta (solo chiavi, niente ricette), 5 pasti | scritto, testato |
| Disclaimer.swift | chiavi del disclaimer | scritto |

Costanti e regole principali (riprodurle uguali su Android):
- **RepDetector**: segnale 1D = accelerazione utente (gravità rimossa) proiettata sull'asse principale (PCA con 50
  iterazioni di potenza). Filtro passa-basso EMA a 3 Hz; picco = campione con vicini minori (un campione di ritardo);
  soglia = max(0,12 g; 0,5 × media mobile dei picchi); intervallo minimo 0,7 s; isteresi: riarmo sotto 0,3 × soglia;
  `signalConfidence` = 1 − max(CV ampiezze, CV intervalli) (bassa se il telefono è in tasca).
- **MotionService** (app): 50 Hz, calibrazione 3 s a finestra scorrevole; se non c'è movimento ≥ 0,15 g aspetta (evita
  un asse casuale); mantiene l'asse tra le serie; `beginSet()` / `pauseCounting()`.
- **SessionEngine**: fasi `notStarted → working(set) → resting(afterSet, remaining) → … → finished`; avvisi `setStarted,
  targetReached, restStarted, restCountdown(3,2,1), restEnded, sessionFinished`; conteggio ignorato durante la pausa;
  stop manuale con ripetizioni dichiarate; `endNow`; il tempo arriva da fuori (monotonic `systemUptime`).
- **FixedCoaching (Mid)**: tutte le serie completate → +1,25 kg (+2,5 gambe) e, con ≥3 serie, +1 serie (max 5);
  ≥ metà serie interrotte → −10% e −1 serie (min 2), pausa +30 s; altrimenti invariato. Pausa base 120 s (multiarticolare)
  o 75 s (isolamento). Chiavi motivo `coach.*`.
- **AdaptiveCoach (Full)**: usa ultima sessione dell'esercizio: completamento, interruzioni, calo di velocità prima→ultima
  serie. Due sessioni di fila sotto 80% → scarico −10%; completato senza fatica (<20%) → +reps se la scheda ha un
  intervallo, altrimenti +2,5% del carico (arrotondato a 1,25 kg); senza carico (corpo libero) → +1 ripetizione; fatica
  20–35% → +15 s; >35% → +30 s; completamento 70–85% → mantiene; <70% → −8% e −1 serie. Limiti: serie 1–8, rip. 1–50,
  pausa 30–300 s. Gli obiettivi della scheda (`PlanTarget`) prevalgono su serie/pausa.
- **ExerciseRecommender**: punteggio = bisogno (1/(1+serie settimanali/6) mediato sui muscoli primari) + 0,25 se
  multiarticolare + 0,15 se mai fatto − 0,5 se fatto nelle ultime 48 h. Chiavi motivo `rec.*`.
- **Nutrizione**: BMR Mifflin-St Jeor; TDEE = BMR × attività; obiettivo ×0,85/×1,00/×1,10; proteine 1,6 (mantenimento)
  o 1,8 g/kg; grassi 0,9 g/kg; carboidrati = resto. Giorno di allenamento +8% calorie (tutte in carboidrati). Pasti:
  25/10/30/10/25%. Coefficienti **indicativi, da far rivedere a un professionista**. Non gestisce allergie o patologie.
- **Parser schede**: righe tipo "Panca piana 4x8-10 60kg rec 90s", "4 serie da 10", intestazioni giorno/giorni della
  settimana; recupero con unità (min, ', s, ", '') e numero nudo ≤10 = minuti. È euristico: l'utente conferma sempre.

### 5.2 App (file, ruolo, stato)

| File | Ruolo | Stato |
| --- | --- | --- |
| MyGymHelperApp.swift | entrata, `.modelContainer`, onboarding, abbonamenti | scritto; **manca** `.environment(CatalogStore)` |
| ContentView.swift | tab (Allenamento, BMI, Piani, Info) e BMI con blocco senza consenso | scritto; **da aggiornare** (tab Esercizi/Nutrizione) |
| Theme.swift | colori, sfondo, `glassCard`, `ScreenHeader`, `CounterRow`, `RepRing` | scritto |
| DisclaimerView / Onboarding / ConsentStore / LegalDocument / InfoView | disclaimer, consenso separato, documenti legali, Info, cancellazione dati | scritti |
| WorkoutSetupView.swift | scelta braccio/gamba, serie/rip./pausa, avvisi, storico | scritto; **manca** init con esercizio, peso e consigli |
| SessionController / SessionEngine (Core) / MotionService / CueService | sessione: sensori, avvisi (voce, suono, vibrazione) | scritti (controller già con esercizio e peso) |
| WorkoutSessionView.swift | schermate lavoro, pausa, "mi sono fermato", salvataggio con consenso | scritto; **da aggiornare** (nuovi parametri) |
| SessionSummaryView.swift | riepilogo e consigli Mid | scritto; **da aggiornare** (adattivo Full, esercizio) |
| HistoryView.swift | storico (SwiftData) | scritto |
| Persistence.swift | modelli SwiftData: sessioni, serie, elenchi, schede, piano alimentare, profilo salute; archivio escluso dai backup | scritto |
| CatalogStore.swift | catalogo: elenco incluso + backend facoltativo | scritto |
| CoachingService.swift | ponte SwiftData → motori del Core | scritto |
| BodyMapView.swift | mappa corpo fronte/retro + blocchi per zona | scritto |
| ExercisesView.swift | catalogo, dettaglio, elenchi preimpostati e salvati | scritto; **riferisce `TrainingPlansView` non ancora scritta** |
| SubscriptionManager / PaywallView | StoreKit 2, livelli, cache offline 14 giorni | scritti |
| Localizable.xcstrings | italiano e inglese | **incompleto** (vedi 9) |
| exercises_seed.json | 25 esercizi, testi nostri in it/en | scritto |
| Legal/*.md | disclaimer, informativa privacy (con sezione 10 aggiunta da noi), consenso | scritti, solo italiano, con segnaposto |

Flusso all'avvio: disclaimer (accettazione registrata con data e versione) → consenso dati sanitari (casella non
preselezionata, "Non ora" possibile) → app. Senza consenso: BMI, storico, elenchi e import schede sono bloccati;
il conteggio funziona. Revoca consenso e "Elimina tutti i dati locali" in Info (`LocalData.deleteHealthData()` cancella
tutti i modelli SwiftData sanitari).

## 6. Dati

SwiftData (solo locale, escluso dai backup): `WorkoutSessionRecord` (con exerciseID, exerciseName, weightKg),
`SetLogRecord` (ripetizioni previste/fatte, interrotta, durata, `averagePeak` = proxy velocità, `lowConfidence`),
`ExerciseListRecord`, `TrainingPlanRecord` (JSON di `TrainingPlan`), `NutritionPlanRecord` (JSON di
`ParsedNutritionPlan`), `HealthProfileRecord` (sesso, età, altezza, peso, attività, obiettivo, diete).

Supabase: `docs/mygymhelper_schema.sql` (non eseguito, da provare). Schema `public`: `profiles`, `exercise_lists`,
`preset_lists`, `catalog_cache` (vincolo ≤ 30 giorni); schema `licensing` (non esposto): `entitlements`,
`store_events`; RLS su tutto; funzione `get_my_entitlement()`; trigger che alla registrazione crea profilo e licenza
Free. I dati sanitari non vanno nel cloud. Il database delle licenze può essere un secondo progetto (eseguire solo la parte `licensing`).

## 7. Backend ancora da scrivere

- Funzione `catalog` (Edge Function): legge MuscleWiki con la chiave in un segreto, assembla l'elenco `[Exercise]` (formato
  del DTO in `Exercises.swift`), lo salva in `catalog_cache` (≤ 30 giorni), risponde a `GET /catalog?lang=xx`.
- Funzione `apple-notifications`: riceve App Store Server Notifications V2, scrive `licensing.store_events` (idempotente)
  e aggiorna `licensing.entitlements`. Per collegare acquisto e utente, nell'app serve `appAccountToken` = id utente
  Supabase negli acquisti StoreKit (non ancora fatto). Google Play (RTDN) quando arriverà Android.
- Cancellazione account dentro l'app (richiesta da Apple): funzione che chiama la cancellazione utente Supabase.
- Consigliato RevenueCat solo se si vuole unificare iOS e Android (da valutare).

## 8. Cosa è stato verificato

- Python: rilevatore di ripetizioni (6 scenari), macchina a stati della sessione, parser delle schede (esempio realistico),
  parser della scheda alimentare.
- Controlli statici: bilanciamento di parentesi nei file Swift, struttura dello zip.
- **Non verificato**: compilazione, test Swift, SwiftUI/Liquid Glass (`glassEffect`, `.glassProminent`), SwiftData, StoreKit,
  CoreMotion su dispositivo, voce/suoni, soglie di conteggio con movimenti reali, parser su PDF/foto reali, MuscleWiki.

## 9. Lavoro rimasto (in ordine consigliato)

A. **Completare il blocco "esercizi + coaching + schede + alimentazione" (già a metà)**
1. `MyGymHelperApp`: creare e iniettare `CatalogStore` (`.environment(catalog)`).
2. `WorkoutSetupView`: aggiungere `init(exercise: CatalogExercise? = nil)`, riga del peso (passo 1,25 kg), carte di
   consiglio: Full → `CoachingService.adaptive` con pulsante "Applica"; Mid → `CoachingService.fixed`; passare
   esercizio e peso a `WorkoutSessionView`/`SessionController` (il controller li accetta già) e salvare nello storico.
3. `WorkoutSessionView` e `SessionSummaryView`: nuovi parametri; consigli adattivi (Full) calcolati con la sessione appena
   finita; consigli fissi (Mid) con `isCompound`/`isLowerBody` dell'esercizio; spostare la mappa `CoachingAdvice` → testo in un'estensione condivisa.
4. `TrainingPlansView` (elenco/dettaglio/eliminazione schede) e **importazione schede** (Full, con consenso): `UIDocumentPicker`/
   `fileImporter` + `PhotosPicker`; estrazione testo con PDFKit (`PDFDocument.string`) e, se vuoto, OCR Vision
   (`VNRecognizeTextRequest`, `.accurate`, rilevamento lingua); `TrainingPlanParser`; **schermata di revisione modificabile**
   prima di salvare; riga "AI locale" disattivata con nota (non implementata).
5. **Schermata Alimentazione** (tab): profilo (`HealthProfileRecord`), BMI (Free), obiettivi calorie/macro (Mid+), scelta
   diete multiple, pasti con `DietPlanner` e giorno di allenamento (Full), importazione scheda del nutrizionista con
   `NutritionPlanParser` e revisione, ricerca alimenti Open Food Facts (client `URLSession` con User-Agent, decodifica
   tollerante dei numeri) con attribuzione. Eliminare il vecchio `BMIView` o integrarlo.
6. `ContentView`: nuove tab (Allenamento, Esercizi, Nutrizione, Piani, Info); decidere dove sta il BMI.
7. `Localizable.xcstrings`: aggiungere le chiavi mancanti (it/en): `ex.*`, `lists.*`, `map.*`, `mech.*`, `rec.*`,
   chiavi dinamiche `muscle.<nome>` (14), `region.<nome>` (6), `food.*`, `meal.*`, chiavi nuove `coach.*` (progress, morereps,
   addset, keepfatigue, highfatigue, reduce, deload) e le stringhe delle nuove schermate. Uno script può confrontare le
   chiavi usate nel codice con quelle del catalogo (le chiavi dinamiche vanno aggiunte a mano).
8. Aggiornare README e rigenerare lo zip.

B. **Da provare su iPhone vero** (priorità alta): conteggio ripetizioni e soglie con movimenti reali (braccio e gamba),
   calibrazione, avvisi vocali, comportamento a schermo spento.

C. **Altre funzioni**: Apple Salute (peso in lettura, allenamenti in scrittura), app Apple Watch (CoreMotion sul watch,
   `WatchConnectivity`, Mid+), login Supabase (email/Google/Apple) e schermate account, `appAccountToken`, funzioni di backend
   (sezione 7), cancellazione account, AI locale (scelta del runtime, download del modello dopo consenso, uso di
   `PlanAIOutput` per validare l'uscita), illustrazioni proprie degli esercizi, icona e schermata di avvio, traduzioni
   (anche dei testi legali, rivedute da un legale), pagina web della privacy, testi dello store (con il disclaimer),
   prodotti in App Store Connect, test UI, Android (Kotlin + Jetpack Compose, riusando specifiche e test del Core).

D. **Punti aperti con l'utente**: cosa sincronizzare nel cloud e come gestire backup/cambio telefono; conferma della
   divisione Free/Mid/Full (in particolare: la selezione muscoli è nel Mid secondo `FeatureGate`, ma la vista oggi la
   mostra a tutti sul catalogo limitato); offerta di lancio; costo del piano MuscleWiki (serve GROWTH per le lingue) o
   alternativa; modello AI locale definitivo; chi crea le illustrazioni; nome definitivo e identità grafica.

## 10. Come ricreare da zero

1. Creare il pacchetto `Core` con i file della sezione 5.1 nell'ordine: Tier → BMI/Nutrition → Muscles/Catalog/Exercises →
   RepDetector → SessionEngine → Progression → Recommender → AdaptiveCoach → PlanParser → Diet → CachedExerciseProvider,
   scrivendo prima i test descritti (i casi sono nei file `Tests/`), poi l'implementazione. Rispettare le costanti della 5.1.
2. Creare il progetto iOS 26 (SwiftUI) e aggiungere il pacchetto in locale; impostare le opzioni della sezione 4.
3. Scrivere nell'ordine: Theme → Legal/Consent/Onboarding/Info → Persistence → Motion/Cue/SessionController → schermate
   allenamento → catalogo/mappa/elenchi → abbonamenti → import schede → alimentazione → localizzazione.
4. Eseguire lo schema SQL su Supabase e scrivere le funzioni della sezione 7.
5. Collaudare su iPhone, tarare le soglie, far rivedere i testi legali, poi App Store Connect.

## 11. Regole di lavoro per chi continua

- Rispondere e commentare in italiano; chiedere conferma sulle scelte di prodotto prima di cambiarle.
- Non copiare codice da opengym; non salvare immagini/video MuscleWiki; non mettere chiavi API nell'app.
- Non fare commit; consegnare file o zip. Dichiarare sempre cosa non è stato compilato o provato.
- Non presentare i testi legali come definitivi; non fare affermazioni mediche; mantenere i disclaimer.
- Ogni dato sanitario nuovo va in SwiftData (non in UserDefaults), richiede consenso e va incluso in `LocalData.deleteHealthData()`.
- **Dal 23 ottobre 2026**: ogni modifica all'app Android va fatta in parallelo anche sull'app iOS (salvo indicazioni diverse dell'utente).
- **Dal 26 ottobre 2026**: ogni modifica o aggiunta all'app va riportata anche nel **tutorial** (Android e iOS), seguendo `docs/TUTORIAL.md`.

## 12. Fase 2 – 19 ottobre 2026

Stato in una riga: blocco 9.A completato; tutto il codice è scritto ma **ancora mai compilato** e i test Swift **mai eseguiti**.
Controlli fatti: sintassi di tutti i file Swift con un parser (tree-sitter), chiavi di localizzazione usate nel codice
confrontate con il catalogo, riferimenti interni del `project.pbxproj`, revisione del codice da un secondo assistente.

Fatto
- Rinomina completa PalestrApp → MyGymHelper (cartelle, modulo, entrata `MyGymHelperApp`, ID prodotto, cartella dati, schema SQL).
- `MyGymHelper.xcodeproj` (Xcode 26, cartella `App/` sincronizzata, pacchetto locale `Core`, impostazioni della sezione 4),
  `project.yml` per XcodeGen come riserva, `Support/Info.plist` (chiavi personalizzate), `Support/MyGymHelper.storekit`
  (4 abbonamenti in un gruppo, prova di 7 giorni), `App/Assets.xcassets` (icona vuota, colore d'accento).
- Core: `WorkoutParameters` (limiti, arrotondamento a 1,25 kg, applicazione dei consigli Mid e Full; corpo libero = +1 ripetizione
  invece di +carico), `FoodFacts` (client Open Food Facts con User-Agent e decodifica tollerante). Test in `Phase2Tests.swift`.
- App:
  - `MyGymHelperApp`: inietta `CatalogStore`. `ContentView`: schede Allenamento, Esercizi, Nutrizione, Piani, Info
    (il BMI è nella scheda Nutrizione; il vecchio `BMIView` è stato eliminato).
  - `WorkoutSetupView(exercise:)`: scelta esercizio, riga del peso, precompilazione da ultima sessione o scheda,
    consigli Full (adattivi) / Mid (regole fisse) con "Applica"; passa esercizio e peso alla sessione.
  - `WorkoutSessionView`/`SessionSummaryView`: nuovi parametri, consiglio adattivo calcolato con la sessione appena finita,
    regole fisse con `isCompound`/`isLowerBody` reali. Testi dei consigli in `CoachingText.swift`.
  - `TrainingPlansView` + `TextExtractor`: elenco/dettaglio/modifica/eliminazione schede, importazione da file
    (PDF, Excel .xlsx, Word .docx, CSV, immagine, testo) e da Foto, OCR Vision se il PDF non ha testo utile (righe di tabella con celle separate da TAB), revisione modificabile, riga "AI locale" disattivata.
  - `NutritionView` + `FoodSearchView`: profilo, BMI, fabbisogno, diete multiple (onnivora esclusiva), pasti con giorno
    di allenamento, scheda del nutrizionista con revisione (se ne tiene una), ricerca Open Food Facts con attribuzione.
  - `HistoryView` mostra esercizio e peso; `InfoView` ha la sezione "Fonti dei dati".
  - `Localizable.xcstrings`: aggiunte circa 200 chiavi it/en (comprese le dinamiche `muscle.*`, `region.*`, `food.*`,
    `meal.*`, `diet.*`, `coach.*`, `rec.*`).

Punti da verificare al primo build
- API iOS 26 non provate: `glassEffect`, stili `.glass`/`.glassProminent`, `Tab`, `TextField(value:format:)` con opzionali.
- Apertura del `.xcodeproj` scritto a mano (in caso di problemi usare XcodeGen con `project.yml`).
- Le Legal/*.md devono finire tra le risorse del bundle (la cartella sincronizzata dovrebbe farlo da sola).

Ancora da fare: sezioni 9.B, 9.C e 9.D (prova su iPhone, Apple Watch, HealthKit, login Supabase, backend, AI locale,
illustrazioni, traduzioni dei testi legali, App Store Connect, Android). Punto 9.D ancora aperto: la mappa dei muscoli è
visibile anche nel Free, mentre `FeatureGate` mette `muscleSelection` nel Mid (non cambiato, decisione di prodotto).

## 13. Fase 3 – 20 ottobre 2026 (pronta per lo store, Apple Salute, backend)

Scelte dell'utente: preparare l'app per lo store, aggiungere Apple Salute e il backend Supabase (con login);
vendita in **tutto il mondo** (quindi lingua di sviluppo inglese e testi legali anche in inglese).
Stato: codice Swift **mai compilato**; SQL eseguito su PostgreSQL di prova; Edge Functions controllate con `deno check`.

Fatto
- Piani: `SubscriptionStoreView` di StoreKit (conformità 3.1.2 gestita da Apple), confronto Free/Mid/Full con le sole
  funzioni presenti, ripristino e "Gestisci"; acquisti con `appAccountToken` = id utente Supabase se c'è l'accesso;
  aggiornamento dello stato al ritorno nell'app. I blocchi "disponibile con Mid/Full" aprono i Piani.
- `PrivacyInfo.xcprivacy` (UserDefaults CA92.1, tempo di avvio 35F9.1, e-mail/ID utente/acquisti collegati,
  nessun tracciamento), `ITSAppUsesNonExemptEncryption = NO`, icona 1024 provvisoria, versione 1.0.
- Lingua di sviluppo `en`, `InfoPlist.xcstrings` (testi dei permessi in it/en), testi legali `*.en.md`
  (traduzione della bozza), nuova sezione 11 dell'informativa (Salute, Open Food Facts, cancellazione account).
- Apple Salute: `HealthKitService` (lettura peso/altezza su richiesta, scrittura allenamenti), interruttore in Info,
  pulsante "Importa da Salute" nel profilo, entitlement HealthKit. Disattivata alla revoca del consenso.
- Account: `AccountService` (supabase-swift 2.x: e-mail con codice OTP, Accedi con Apple con nonce, Google OAuth),
  `AccountView` con uscita ed eliminazione (funzione `delete-account`). Il catalogo usa le Edge Functions se
  `MyGymHelperSupabaseURL` è impostato, con il token dell'utente o la chiave anon.
- Backend: `supabase/` con migrazioni (schema + funzioni `licensing_record_event`, `licensing_apply_entitlement`
  riservate alla service role) e funzioni `catalog`, `apple-notifications` (libreria ufficiale Apple),
  `delete-account`. Guida: `docs/BACKEND.md`. Testi per lo store: `docs/STORE_TEXTS.md`.
- Bug corretti: controller della sessione creato una sola volta; sensori non riaccesi tornando su una sessione
  finita; cancellazione dei dati con il contesto principale (le liste si aggiornano subito); "Elimina tutti i dati"
  riporta subito a disclaimer e consenso; documenti legali letti una sola volta; ripristino acquisti aggiorna il piano.

Ancora da fare
- Compilare e provare su iPhone (soprattutto conteggio, Salute, accessi, acquisti sandbox).
- Pubblicare informativa privacy su una pagina web e compilare i segnaposto; revisione legale delle bozze (it/en).
- Icona definitiva, screenshot per lo store, eventuale catalogo MuscleWiki (piano a pagamento, GROWTH per le lingue).
- Apple Watch, AI locale: non iniziati. Android: vedi sezione 14.

### 13.1 Aggiornamento: revoca dei token Apple (20 ottobre 2026)
- Eliminando l'account, chi e' entrato con Apple conferma con Apple (`AccountView`); l'app invia il codice di
  autorizzazione a `delete-account`, che lo scambia e revoca i token (`supabase/functions/_shared/apple.ts`).
  Nessun token Apple viene salvato. Test Deno in `_shared/apple_test.ts` (passano). Segreti: `docs/BACKEND.md`.

## 14. Porting Android – 20 ottobre 2026

Scelte dell'utente: porting completo "come iOS" (logica, tutte le schermate, conteggio con i sensori,
abbonamenti Google Play, Health Connect, account Supabase con Google ed e-mail, funzione server per le notifiche
Google Play); Android 9 (API 28) e successivi. Guida operativa: `docs/ANDROID.md`.

Stato
- `android/core`: port Kotlin 1:1 del pacchetto Swift Core, **compilato con Kotlin 2.2 e 53 test JUnit superati**.
  Trovata e corretta in entrambe le versioni una differenza nel parser: `rec 3"` ora vale 180 secondi
  (un valore in secondi sotto 10 si interpreta come minuti).
- `android/app`: Compose + Material 3, **mai compilata** (repository Google/Maven non raggiungibili da qui);
  controllo sintattico e revisione indipendente fatti, correzioni applicate.
- Backend: `google-play-notifications` (Pub/Sub OIDC + Play Developer API v2), migrazione
  `20261021000000_google_play.sql` (provata su PostgreSQL), `delete-account` accetta `platform: android`.
  Test Deno: 9 superati (Apple e Google).

Scelte tecniche
- Navigazione manuale con una pila per scheda (niente navigation-compose), stato con StateFlow e Compose state.
- Dati sanitari in un file JSON in `noBackupFilesDir`, backup disattivato; si scrive solo con il consenso.
- Testi: generati dal catalogo iOS (`tools/xcstrings_to_android.py`), stesse chiavi; testi solo Android in
  `tools/android_strings.json`. Informativa privacy Android adattata (Google Play, Health Connect).
- Prodotti Play: `mygymhelper_mid`, `mygymhelper_full`, piani base `monthly`/`yearly`, offerta `free-trial`.

Ancora da fare (Android)
- Compilare in Android Studio, correggere eventuali errori, provare su telefoni veri (soglie del conteggio).
- Play Console: abbonamenti, notifiche, account di servizio, scheda Sicurezza dei dati, dichiarazione Health Connect.
- Revisione legale dell'informativa Android; pagina web per la richiesta di eliminazione dell'account.

## 15. Prime prove su Android – 21 ottobre 2026

L'utente userà l'app Android per le prove e porterà dopo le modifiche su iOS. Richieste e scelte:
- **Conteggio troppo sensibile** e ripetizione da contare solo dopo "due movimenti dell'arto": nuovo `RepCounter`
  nel core Kotlin (andata e ritorno completi, segnale di inclinazione o spostamento, soglie adattive), 10 test.
  Il vecchio `RepDetector` resta nel core solo per parità con Swift. **Da portare su iOS** (Core Swift + MotionService).
- **Voce più umana, maschile o femminile**: scelta "voci migliori del telefono" (gratis, offline): `VoiceEngine`
  condiviso, scelta della voce, velocità, frasi variate, musica abbassata mentre parla. Voci cloud: scartate per ora.
- **Spiegazione dell'esercizio**: scelta "prima della prima serie", con "Rispiega" nelle pause.
- **Musica**: scelta "entrambi": tasti multimediali per qualsiasi app + Spotify App Remote opzionale
  (sorgenti in `app/src/spotify` compilati solo se l'.aar è in `app/libs`). La musica parte a inizio serie e si ferma
  durante la spiegazione.
- **Piani nei test**: piano simulato solo nelle build di debug (Info), più istruzioni per il test interno di Play.
- Nuove chiavi di testo aggiunte anche a `App/Localizable.xcstrings` (voice.*, explain.*, audio.*, music.*), pronte per iOS.
Stato: core compilato e testato (63 test); app Android non compilata in questo ambiente (revisione indipendente fatta).

## 16. Prove su Android e calibrazione per posizione – 23 ottobre 2026

Risultati delle prime prove (telefono Android):
- Telefono sul **bicipite**: conteggio corretto circa nel 95% dei movimenti. Sulla **parte alta della coscia**: a volte il movimento non viene visto.
- Esercizi in cui si muove solo l'**avambraccio** (curl ecc.) con il telefono sul bicipite: non contati. Non è un difetto del contatore:
  il braccio sopra il gomito quasi non si muove, quindi il telefono deve stare sul segmento che si muove (stessa cosa per
  lo stinco nella leg extension). Da qui le posizioni separate.
- Piani Mid/Full: non si riusciva a provarli. Vibrazione e suono di fine serie/ripartenza: non percepiti.

Scelte dell'utente: (1) per ogni posizione del telefono, calibrazione facoltativa e salvata + sensibilità regolabile a mano;
posizioni: **due per il braccio, due per la gamba, una per gli addominali**; (2) piano Full attivo per tutti i test.

Fatto (solo Android; **core testato, app Android non compilata in questo ambiente**):
- Core Kotlin: `Calibration.kt` (`SensorPosition` con 5 posizioni: braccio sopra il gomito, avambraccio, coscia,
  stinco/caviglia, addome; `PositionTuning` = sensibilità 0,5–2,0 + ampiezza tipica + segnale; `RepCalibrator`;
  `CalibrationResult`). `RepCounterConfig.forcedSignal`: una posizione calibrata usa il segnale già scelto.
  Soglia calibrata = 55% dell'ampiezza mediana misurata, divisa per la sensibilità, con limiti di sicurezza
  (inclinazione 0,10–1,2; spostamento 0,04–0,8). 7 test nuovi in `CalibrationTests.kt` (70 test totali, tutti superati).
- App: scelta delle 5 posizioni nella schermata Allenamento (sostituisce il vecchio Braccio/Gamba; le vecchie sessioni
  "arm"/"leg" si leggono come braccio/coscia), schermata **Calibrazione e sensibilità** (da Allenamento e da Info):
  calibrazione guidata (5 ripetizioni dopo un conto alla rovescia di 5 s), cursore di sensibilità, prova del conteggio in
  diretta, ripristino. Impostazioni in `Prefs` (`tuning.<posizione>.*`), cancellate da "Elimina tutti i dati".
  Non si registrano i movimenti, solo le soglie (non sono dati sanitari).
- Piano di prova: nelle build di debug il piano simulato parte da **Full** (Info > Test permette di cambiarlo).
- Avvisi: il bip usa il volume multimediale (prima era il volume delle notifiche, spesso a zero); la vibrazione usa
  l'uso "sveglia" (funziona anche in silenzioso/Non disturbare) con impulsi più lunghi (prima 60 ms, quasi impercettibili);
  nuovo pulsante **Prova avvisi** nella scheda Avvisi. La causa esatta del problema non è verificata: da riprovare sul telefono.

Da fare / da sapere
- Compilare in Android Studio e provare: calibrazione in ogni posizione, prova avvisi, piano Full.
- **iOS** (superato dalla sezione 17): calibrazione e posizioni non erano ancora portate. Attenzione: nel Core Swift esiste ancora solo il vecchio
  `RepDetector.swift`; il nuovo `RepCounter` (sezione 15) **non è stato portato in Swift**. Va portato prima (RepCounter,
  poi Calibration), insieme alle chiavi `position.*`, `calib.*`, `cue.test*` (oggi solo in `android/tools/android_strings.json`).
- Possibile sviluppo (da decidere con l'utente): suggerire la posizione consigliata per ogni esercizio del catalogo.

## 17. Accesso con Facebook e allineamento di iOS – 23 ottobre 2026

Scelte dell'utente: accesso con e-mail, Google e **Facebook** su entrambe le app, più Apple solo su iOS (e-mail, Google
e Apple esistevano già: non comparivano perché Supabase non è ancora configurato); **iOS allineato ad Android**
in questo giro; guida per creare il progetto Supabase. Nuova regola: ogni modifica Android va fatta anche su iOS.

Fatto
- Facebook (Supabase OAuth, senza SDK Meta): Android `AccountService.signInWithFacebook()` (browser + ritorno
  `mygymhelper://login-callback`, intent-filter nel manifest, `handleDeeplink` in `MainActivity`), interruttore
  `auth.facebook` in `local.properties` → `BuildConfig.FACEBOOK_LOGIN`; iOS `signInWithOAuth(.facebook)` con
  interruttore `MyGymHelperFacebookLogin` in `Support/Info.plist`. Avviso "account non configurato" in Info solo nelle
  build di debug. Informativa privacy (bozze it/en, iOS e Android): aggiunto Facebook tra i metodi di accesso.
- Core Swift: `RepCounter.swift` e `Calibration.swift` (port 1:1 del Kotlin), test `RepCounterTests.swift` e
  `CalibrationTests.swift` con un generatore di rumore con seme (SplitMix64). Gli stessi scenari, con lo stesso
  generatore, sono stati eseguiti sul contatore Kotlin (14 test superati): verifica della logica, **non** del Swift.
- App iOS: `AppSettings` (voce, musica, calibrazioni, piano di prova), `VoiceEngine` (voce maschile/femminile con il
  genere reale delle voci iOS, qualità, velocità, frasi in coda con fine lettura), nuovo `CueService` (frasi variate,
  "ancora una", conto a voce, bip generato che suona anche in silenzioso, vibrazioni lunghe con Core Haptics, prova
  avvisi), `Music` (solo **Apple Music**: su iOS un'app non può comandare Spotify o altre app; con le altre app la
  musica viene solo abbassata), nuovo `MotionService` (gravità + accelerazione, RepCounter, campioni grezzi per la
  calibrazione), `SessionController` (posizione, calibrazione, spiegazione, conto alla rovescia, musica),
  `CalibrationView` (5 posizioni, calibrazione, sensibilità, prova), `AudioSettingsView`, spiegazione dell'esercizio in
  `WorkoutSessionView`, scelta della posizione in `WorkoutSetupView`, piano di prova in Info (solo `#if DEBUG`,
  predefinito Full), `NSAppleMusicUsageDescription`. Il vecchio `BodyLimb` è stato tolto anche da iOS.
- Testi: le chiavi comuni (position.*, calib.*, cue.test*, debug.*, account.facebook, account.notConfigured) ora sono
  in `App/Localizable.xcstrings`; `android_strings.json` contiene solo i testi solo Android.

Non verificato
- **Codice Swift mai compilato** (solo controllo sintattico con tree-sitter). App Android non compilata qui
  (solo controllo sintattico). Accesso con Facebook mai provato (serve il progetto Supabase e l'app Meta).
- Su iOS non c'è Spotify con playlist (l'SDK Spotify iOS non è integrato): da decidere se aggiungerlo.

### 17.1 Accesso con e-mail spento (23 ottobre 2026)
Scelta dell'utente: per ora solo Google, Facebook e Apple (iOS). L'accesso con e-mail resta nel codice ma è nascosto
(`auth.email` in `local.properties` → `BuildConfig.EMAIL_LOGIN`; `MyGymHelperEmailLogin` in `Support/Info.plist`),
perché i nuovi progetti Supabase Free non permettono di mettere il codice nel modello dell'e-mail senza SMTP proprio.

### 17.2 Allenamento a elenco (26 ottobre 2026)
- Scheda Allenamento rifatta (Android e iOS): in alto l'**elenco attuale** (se non ce n'è uno, al primo esercizio si
  crea "Allenamento odierno"; piani Mid/Full possono sceglierne o crearne altri), ogni esercizio con serie,
  ripetizioni, pausa e peso, modificabile ed eliminabile; quelli svolti diventano verdi, **Reset** li azzera.
- Sotto: mappa del corpo + lista di **tutti** gli esercizi; scelti dei muscoli, la lista si filtra (muscolo principale)
  e quelli che allenano tutti i muscoli scelti (almeno due) sono in evidenza (ambra) e in cima. Tocco = editor dei
  parametri (con consigli) → "Aggiungi all'elenco". Logica nel Core: `WorkoutListLogic` / `WorkoutItem` (con test).
- Avvio: schermata **Pronto** (posizione del telefono, calibrazione, "Avvia") → **spiegazione sempre**, con "Salta e
  inizia" (l'impostazione audio ora decide solo se leggerla a voce) → conteggio. Spunta "Esercizio successivo":
  finito un esercizio si propone il prossimo (sempre dalla schermata Pronto, parte solo con "Avvia"); senza spunta
  si torna all'elenco. Rimasto il "Conteggio libero (senza esercizio)".
- Dati: `ExerciseListRecord` ha `items` (+ `autoNext`); i vecchi elenchi con soli id vengono convertiti (parametri
  3×10, 90 s). Senza consenso l'elenco resta solo in memoria (Android: AppStore; iOS: `WorkoutListStore` in
  Persistence.swift). iOS: nuovi campi SwiftData `itemsData` e `autoNext` (migrazione automatica).

### 17.3 Tutorial in sovraimpressione (26 ottobre 2026)
- Tutorial guidato (Android e iOS): oscura l'app, illumina la funzione con bordo pulsante e mano che la indica,
  fumetto con Avanti/Indietro/Salta; passi senza elemento con disegni animati. Parte da solo al primo avvio (dopo
  disclaimer e consenso), si rivede da **Area personale → Tutorial dell'app**. Dettagli e passi: `docs/TUTORIAL.md`.
- Passi nel Core (`Tutorial.kt` / `Tutorial.swift`, con test), sovraimpressione in `ui/Tutorial.kt` e `App/TutorialOverlay.swift`.
- **Regola dell'utente: a ogni modifica o aggiunta all'app va aggiornato anche il tutorial** (procedura in `docs/TUTORIAL.md`).
- Non verificato: nessuna compilazione (né Android né Swift) e test del Core non eseguiti in questo ambiente.

### 17.4 Correzioni dopo le prove sul telefono (26 ottobre 2026)
Segnalazioni dell'utente dopo le prove su Android e cosa è stato fatto (Android e, dove serve, iOS):
1. **PDF testuale non caricato** (Android): prima si usava solo l'OCR delle pagine. Ora, come su iOS, si legge prima il
   testo incorporato con PDFBox (`pdfbox-android` 2.0.27.0) ricostruendo righe e colonne (TAB) dalla posizione dei
   caratteri; l'OCR resta per i PDF scansionati. Log in Logcat con il tag `TextExtractor`. Algoritmo delle colonne
   provato sul file `prova_scheda.pdf` (con pdfplumber, stesso calcolo): righe e colonne corrette.
2. **SDK Spotify non installato** (Android): copiato `spotify-app-remote-release-0.8.0.aar` in `android/app/libs`.
   Manca ancora `spotify.clientId` in `local.properties` (va creata l'app nella dashboard Spotify, vedi ANDROID.md):
   ora l'app distingue i due casi con messaggi diversi.
3. **BMI errato**: in attesa dei valori dall'utente (formula e salvataggio sembrano corretti).
4. **Pulsanti +/− del peso** (Android e iOS): 0,5 kg fino a 4 kg, 1 kg fino a 10 kg, poi 5 kg (`WeightSteps` nel Core,
   con test). `WorkoutParameters.clamped()` ora arrotonda a 0,25 kg (prima 1,25) per non perdere i passi da 0,5 kg; i
   consigli automatici usano ancora passi di 1,25 kg.
5. **Pulsante "Indietro" tolto su Android**: si usa il tasto/gesto Indietro del telefono (BackHandler in AppRoot).
   Su iOS resta la freccia della barra di navigazione (non esiste un tasto Indietro di sistema).
6. **Peso scritto a mano** (richiesta successiva, Android e iOS): il peso dell'esercizio e il peso corporeo del profilo
   si possono scrivere nel campo (tastiera numerica, solo cifre e un separatore, max 3 cifre intere e 2 decimali:
   `WeightInput` nel Core, con test); i pulsanti +/− restano (esercizio: passi WeightSteps; profilo: 1 kg). Valori fuori
   dai limiti: campo rosso, non salvati. Il peso importato da Health Connect / Apple Salute ora tiene un decimale.
7. **Calorie per obiettivo** (27 ottobre, Android e iOS): la scheda "Fabbisogno giornaliero" mostra le kcal per
   dimagrire (−15%), mantenere e aumentare (+10%) affiancate; l'opzione consigliata dal BMI (sottopeso → aumentare,
   normopeso → mantenere, sovrappeso/obesità → dimagrire) è segnata "Consigliato" e resta selezionata finché l'utente
   non ne tocca un'altra ("Usa l'opzione consigliata" per tornare). Il selettore Obiettivo è stato tolto dal profilo.
   Core: `NutritionCalculator.allTargets/recommendedGoal/effectiveGoal` (con test); profilo con nuovo campo
   `goalChosen` (Android: JSON, default false; iOS: SwiftData, migrazione automatica). Calcolo: metabolismo basale
   Mifflin-St Jeor × livello di attività (Basics.kt / Nutrition.swift), tutto sul telefono.
8. **Figura anatomica nuova e muscoli coinvolti** (27 ottobre, Android e iOS): la mappa per scegliere i muscoli non
   usa più rettangoli ma una figura anatomica fronte/retro disegnata da noi (curve vettoriali, nessuna immagine di
   terzi). I dati sono nel Core (`BodyFigure.kt` / `BodyFigure.swift`), **generati** da `android/tools/body_figure.py`
   (per cambiare il disegno: modifica i punti nello script e rilancialo; con un nome file scrive anche un'anteprima SVG).
   Disegno: `ui/MuscleFigure.kt` (Canvas, tocco con Region) e `MuscleFigure` in `App/BodyMapView.swift` (Canvas,
   tocco con Path.contains). Nella scheda di ogni esercizio c'è "Muscoli coinvolti": la figura con i principali in
   arancio pieno e i secondari in arancio tenue, solo sui lati dove si vedono, più la legenda. Test `BodyFigureTests`.
   Stessa figura in miniatura (`MuscleThumbnail`) in ogni riga degli elenchi di esercizi: catalogo, elenchi pronti e
   salvati, lista da aggiungere e elenco attuale della scheda Allenamento.
Tutorial aggiornato: passo "Elenco" (passi del peso, Android e iOS) e, solo su Android, una frase nel benvenuto sul tasto Indietro.
Non verificato: nessuna compilazione (né Android né Swift), test del Core non eseguiti; solo controllo sintattico con tree-sitter.

### 17.5 Spotify completo (27 ottobre 2026, Android e iOS)
Scelte dell'utente: accesso/uscita dall'account Spotify, scelta tra le proprie playlist, ricerca di playlist/album/brani;
anche su iOS (senza lettore con copertina e comandi: la musica si comanda come prima, a inizio serie e in spiegazione).
- Core: `SpotifyWeb.kt` / `SpotifyWeb.swift` (PKCE, URL di login, corpi delle richieste del token, lettura di profilo,
  playlist e ricerca; su Kotlin anche `SpotifyItemCodec`, su Swift anche `SpotifyLinks`), test `SpotifyWebTests`.
- Android: `services/SpotifyAccount.kt` (login nel browser su mygymhelper://spotify-auth, token nelle preferenze
  private "spotify", rinnovo automatico, Web API con HttpURLConnection), `ui/screens/Spotify.kt` (sezione in Voce e
  musica, schermata `SpotifyPicker`), `ui/RemoteImage.kt` (copertine), intent-filter nel manifest, `Graph.spotify`.
  La riproduzione resta `SpotifyBridge` (App Remote) con l'URI scelto (`Prefs.spotifyChoice` / `spotifyPlaylist`).
- iOS: pacchetto Swift `SpotifyiOS` (github.com/spotify/ios-sdk, 5.0.1) aggiunto a `project.pbxproj` e `project.yml`;
  `App/SpotifyService.swift` (login PKCE con ASWebAuthenticationSession, token nel Portachiavi, Web API; `SpotifyRemote`
  con App Remote), `App/SpotifyViews.swift` (sezione e scelta), `SpotifyPlayer` in `Music.swift` (nuova modalità
  "spotify" accanto ad Apple Music e Altra app), `onOpenURL` per mygymhelper://spotify-remote, `Support/Info.plist`
  (`MyGymHelperSpotifyClientID`, `LSApplicationQueriesSchemes` spotify, schema URL mygymhelper).
  Su iPhone, se Spotify non è già attivo, alla prima serie l'app apre Spotify (che parte con la musica scelta) e torna.
- Da configurare: Client ID (Android `local.properties`, iOS Info.plist) e i tre Redirect URI nella dashboard Spotify
  (vedi ANDROID.md, "Musica e Spotify").
- Non verificato: nessuna compilazione, nessuna prova con un account reale (serve il Client ID). Da provare: login,
  rinnovo del token dopo un'ora, playlist e ricerca, partenza della musica scelta con App Remote (Android e iPhone),
  autorizzazione dell'App Remote su Android dopo il cambio di Spotify del 2025 (flusso dell'SDK, non modificabile da noi).
- Correzione dell'utente (28 ottobre, dopo la prima compilazione): `Prefs.setSpotifyChoice(item)` andava in conflitto
  sulla JVM con il setter generato da `var spotifyChoice` (stessa firma `setSpotifyChoice(SpotifyItem)`); risolto con
  `@JvmName("setSpSpotifyChoice")`. Da Kotlin si chiama sempre `setSpotifyChoice(...)`. Ora il progetto Android compila.

### 17.6 Catalogo esteso con il Free Exercise DB (28 ottobre 2026, Android e iOS)
Scelte dell'utente: tutti gli esercizi del Free Exercise DB (github.com/yuhonas/free-exercise-db, licenza Unlicense /
pubblico dominio), tutte le categorie (forza e pesistica, pliometria, stretching, cardio), tutto tradotto in italiano
(nomi e passi), foto scaricate solo quando servono.
- Dati: `App/exercises_seed.json` e `android/app/src/main/assets/exercises_seed.json` (identici, 876 esercizi, ~1,5 MB,
  una riga per esercizio). I 25 nostri ("seed-") restano invariati e ricevono le foto dell'esercizio equivalente del
  dataset (che quindi non è duplicato); gli altri 851 hanno id "fedb-<id del dataset>". Campi nuovi, facoltativi:
  `category` (strength, powerlifting, olympic, strongman, plyometrics, stretching, cardio), `level`
  (beginner/intermediate/expert), `images` (URL completi su raw.githubusercontent.com).
- Muscoli del dataset → gruppi dell'app: quadriceps→quads, abdominals→abs, lower back→lowerBack; dove manca un gruppo
  equivalente: middle back e neck→traps, adductors→quads, abductors→glutes.
  Attrezzi → chiavi `equipment.*`: body only/nessuno→bodyweight, kettlebells→kettlebell, bands→band,
  medicine ball→medicineBall, exercise ball→exerciseBall, foam roll→foamRoll, e-z curl bar→ezBar, other→other.
  Mechanic mancante: compound (isolation per lo stretching). 5 esercizi del dataset non hanno passi.
- Core (Kotlin e Swift): `CatalogExercise` con `category`, `level`, `images`, `kind` (`ExerciseKind`: forza,
  pliometria, stretching, cardio) e `isTraining` (forza o pliometria, non foam roller). `ExerciseRecommender` consiglia
  solo esercizi `isTraining`. `CatalogAccess` (Free): prima i nostri "seed-", solo esercizi `isTraining`.
  `CatalogFilter` (filtro per tipo, `PAGE_SIZE`/`pageSize` = 40). Swift: `CatalogExercise` decodifica i campi nuovi come
  facoltativi. Test nuovi in `FeatureTests` (Kotlin e Swift), compreso un controllo sul file incluso nell'app.
- App: filtro per tipo (`KindChips`) e "Mostra altri" (elenchi a pagine da 40) in Esercizi, nelle raccolte per zona e
  nella scelta degli esercizi di Allenamento; nella scheda dell'esercizio: tipo, attrezzo tradotto, livello e foto
  (Android `RemotePhoto` in `RemoteImage.kt`, iOS `AsyncImage` in `ExercisePhotosCard`); il catalogo online MuscleWiki,
  se attivo, ora si aggiunge a tutto l'elenco incluso (prima teneva solo i "seed-").
  Info → Fonti dei dati cita il Free Exercise DB. Tutorial: testo del passo "Esercizi" aggiornato.
- Foto (28 ottobre, aggiornamento): convertite in WebP (max 640 px, ~30 MB in tutto) e caricate dall'utente con la
  Supabase CLI nel bucket pubblico `exercise-images` (migration `20261028090000_exercise_images.sql`); gli URL nel file
  puntano a https://xydfakxpybmqtbpglipx.supabase.co/storage/v1/object/public/exercise-images/exercises/<id>/0.webp e 1.webp
  (la CLI ha caricato la cartella con il suo nome, `exercises/`, dentro il bucket).
  Per ricaricarle: `supabase storage cp -r . ss:///exercise-images --experimental --linked` dalla cartella delle foto.
- Lavoro aperto: le traduzioni sono state fatte in blocco: conviene una
  rilettura a campione. Su Android l'elenco si legge all'avvio sul thread principale (~1,5 MB con MiniJson): se si nota
  lentezza all'apertura, spostare `loadSeed()` in background.
- Non verificato: nessuna compilazione, nessun test eseguito, nessuna prova su telefono.

### 17.7 Prove di musica e voce (28 ottobre 2026)
- Voce più staccata dalla musica (Android): l'abbassamento della musica lo decide il sistema (audio focus "may duck",
  livello fisso); la voce ora passa da una sessione audio con `LoudnessEnhancer` (+8 dB, `VoiceEngine.VOICE_BOOST_MB`),
  passata al motore TTS con `KEY_PARAM_SESSION_ID`. Su iPhone il livello di `.duckOthers` è fisso e la voce è già al
  massimo: per staccarla di più resta solo la pausa della musica durante la voce (scelta di prodotto da confermare).
- Genere delle voci: l'elenco mostra solo le voci del genere scelto e poi quelle di genere non riconosciuto (mai quelle
  dell'altro genere). Sulla voce scelta i pulsanti "Non è femminile/maschile" (e "È femminile/maschile" per le voci di
  genere sconosciuto) salvano la correzione: Android `Prefs.voiceGenderFixes` (chiave "voice.genderFixes", nome voce →
  genere), iOS `AppSettings.voiceGenderFixes` (identificatore → genere). La correzione vince sulla stima dal nome
  (Android) o sul genere indicato da iOS. La tabella dei codici Google in `VoiceEngine.guessGender` resta da verificare.
- Spotify: "manca il Client ID" è configurazione (local.properties `spotify.clientId`, Info.plist
  `MyGymHelperSpotifyClientID`), vedi ANDROID.md "Musica e Spotify".
- Non verificato: nessuna compilazione né prova sul telefono di queste modifiche.

### 17.8 Allenamento più semplice e schede pronte (28 ottobre 2026, Android e iOS)
Scelte dell'utente: togliere l'elenco degli esercizi dalla prima pagina (pulsante "Aggiungi esercizio"), righe degli
esercizi con la sola miniatura dei muscoli (senza i nomi), schede preimpostate. Free: una scheda generica total body
non modificabile; Mid e Full: Principiante full body, Push/Pull/Legs, Upper/Lower, Corpo libero e stretching e la
scheda consigliata che si aggiorna ogni mese con l'AI sul telefono in base agli esercizi fatti nel mese.
- Allenamento: restano elenco attuale, "Aggiungi esercizio" (Android `Screen.AddExercise` / `AddExerciseScreen` in
  Workout.kt; iOS `AddExerciseView` in WorkoutSetupView.swift: mappa, zone, tipo, ricerca, pagine da 40), "Schede
  pronte", avvisi, conteggio libero, storico. Dopo aver aggiunto un esercizio si torna alla scelta per aggiungerne altri.
- Righe degli esercizi (catalogo, scelta, raccolte): solo nome + miniatura dei muscoli.
- Core: `Presets.kt` / `Presets.swift`. Le 5 schede fisse sono generate da `android/tools/preset_plans.py` (fonte unica,
  controlla gli id nel catalogo; rigenerare dopo ogni modifica). `PresetPlans.isAvailable` (Free solo la base),
  `PresetPlans.items` (il peso viene dall'ultima sessione dell'esercizio). Nuove funzioni `Feature.PRESET_PLANS` e
  `MONTHLY_PLAN` (Mid). `MonthlyPlanner`: scheda del mese a regole fisse dallo storico del mese precedente (frequenza
  → 2/3 giorni total body o 4 upper/lower; esercizi fatti confermati e alternati a nuovi che ruotano ogni mese con un hash
  stabile FNV-1a uguale sulle due piattaforme; solo corpo libero se ci si è allenati solo così; un esercizio in più per
  i muscoli trascurati). Test `PresetsTests` (Kotlin e Swift).
- Usare un allenamento: Mid/Full → elenco "<scheda> · <giorno>" (riusato se esiste: `upsertList`) che diventa
  l'attuale; Free → sostituisce gli esercizi dell'elenco attuale (con conferma se non è vuoto). Poi si torna
  ad Allenamento (Android `nav.showRoot`, iOS `AppSettings.showWorkoutRoot()` che rinnova la pila di navigazione).
- AI sul telefono: solo iPhone con Apple Intelligence (`App/MonthlyPlanAI.swift`, framework FoundationModels,
  generazione guidata `@Generable`): rivede la scheda a regole scegliendo solo tra i candidati di ogni posto
  (`MonthlyPlanner.alternatives`), serie 2-5 e ripetizioni 5-20, più una nota breve; risposta non valida = resta la
  scheda a regole. Il risultato si salva per il mese in Application Support/monthly-plan.json (escluso dai backup, solo
  con il consenso, cancellato con i dati sanitari). Android: regole fisse (nessun modello sul telefono integrato:
  in futuro si può provare Gemini Nano / ML Kit GenAI sui telefoni compatibili). I dati non escono dal telefono,
  coerente con l'informativa privacy.
- Tutorial versione 2 (vedi TUTORIAL.md).
- Non verificato: nessuna compilazione né test eseguiti; da provare in particolare la generazione guidata di
  FoundationModels su un iPhone con Apple Intelligence e la scelta degli esercizi della scheda del mese con uno storico vero.

### 17.9 Schede PDF "a blocchi" (28 ottobre 2026, Android e iOS)
Prova dell'utente: un PDF testuale fatto con Word ("Gambe_e_Glutei-novembre.pdf") non dava esercizi. Il testo veniva letto
bene, ma il parser riconosceva solo il formato "4x8" / "4 serie da 8" e le tabelle. Le schede dei personal trainer spesso
sono a blocchi: "SET 1 DA RIPETERE 4 VOLTE (1.30 MIN DI RECUPERO)" e sotto righe "6 Squat", "10 - 6 - 10 Hip thrust",
"40” Gatto mucca", "10 Abductor + 8 Abductor ...". Aggiunto in `TrainingPlanParser` (Plans.kt e PlanParser.swift):
- intestazioni di blocco (set/serie/blocco/circuito/superserie/giro/round) con le volte e il recupero scritto prima
  della parola ("1.30 MIN" = 90 s, "60”" = 60 s); le righe sotto ne prendono serie e recupero;
- righe che iniziano con le ripetizioni (anche a piramide "10 - 6 - 10": una serie per numero) o con il tempo (il tempo
  va nel nome, es. "Polpacci (60")"); più esercizi separati da "+" diventano esercizi distinti; il nome andato a capo
  (riga che inizia in minuscolo) si unisce all'esercizio prima;
- sezioni con titolo proprio (riscaldamento, defaticamento, stretching, mobilità...) diventano giorni a parte;
- esclusi i numeri seguiti da unità (100 g, 15 minuti...) per non scambiare alimenti o durate per esercizi.
Test `blockPlanFromWord` / `testBlockPlanFromWord` con il testo di quella scheda. Espressioni regolari provate con Java
(stesse regole di Kotlin); nessuna compilazione né prova sul telefono.

### 17.10 Allenamento: dimensioni e foto; Esercizi senza bottoni delle zone (28 ottobre 2026, Android e iOS)
- Allenamento: "Schede pronte" è una scheda grande (icona, titolo, sottotitolo `presets.subtitle`); le righe dell'elenco
  e della scelta degli esercizi sono più compatte (miniatura 42/46).
- Foto dell'esercizio (posizione iniziale e finale) anche in Allenamento: modifica dell'esercizio, schermata "Pronto" e
  spiegazione prima della serie (`ExercisePhotosCard`, `RemotePhoto` su Android, `AsyncImage` su iOS).
- Esercizi: tolti i bottoni delle zone (`RegionChips`); restano corpo, tipo e ricerca.

### 17.11 Rapporto d'errore via e-mail (28 ottobre 2026, Android e iOS)
Quando qualcosa non funziona l'app mostra "Invia" / "Annulla". Con Invia si apre l'app di posta con il rapporto
(dove, messaggio, stack trace, versione dell'app e del sistema, modello) indirizzato a `ErrorReport.EMAIL`
(mygymhelper@gmail.com dal 31 ottobre 2026, prima ngalmeno@gmail.com). Niente parte senza l'utente, che legge e può modificare la mail.
- Core: `ErrorReport` (ErrorReport.kt / ErrorReport.swift): oggetto e testo, toglie token e codici (`redact`), tronca.
- Android: `services/ErrorReporter.kt` (+ `ui/ErrorReportDialog.kt` in AppRoot). `install()` in `MyGymApp.onCreate`
  salva i crash su file (`last-crash.txt`) e li propone al riavvio. Mail con `ACTION_SENDTO mailto:`, poi `ACTION_SEND`.
- iOS: `App/ErrorReporter.swift` (`.errorReportAlert()` su ContentView): `MFMailComposeViewController` se Mail è
  configurata, altrimenti link `mailto:` (testo più corto). Si salvano solo le eccezioni Objective-C: gli arresti di
  Swift restano nei rapporti di Xcode / App Store Connect.
- Lo stesso errore si propone al massimo una volta ogni 10 minuti.
- Collegato a: Spotify (accesso, rinnovo, chiamate Web API: codice HTTP, indirizzo e risposta) e importazione delle schede
  (file illeggibile, eccezioni, nessun esercizio trovato: in quest'ultimo caso il rapporto contiene il testo estratto).
- Spotify: prima ogni risposta di errore diventava "Spotify non risponde. Controlla la connessione". Ora 403 →
  `spotify.error.forbidden` (account da aggiungere in User Management nella dashboard Spotify, app in modalità sviluppo),
  429/5xx → `spotify.error.server`, solo i veri errori di rete → `spotify.error.network`.

### 17.12 Lettura delle schede con l'AI del telefono (28 ottobre 2026, Android e iOS)
Richiesta dell'utente: usare l'AI interna per capire gli esercizi delle schede. L'interruttore "Lettura con l'AI del
telefono" in Schede ora funziona (acceso di base, `import.ai`); il testo non esce mai dal telefono.
- Core `PlanAI` (PlanAI.kt / PlanAI.swift, test `PlanAITests`): testo diviso in pezzi da 1500 caratteri che ripartono
  con l'ultimo titolo e l'ultima intestazione di set; controllo delle voci (`entry`); esercizi non presenti nel testo
  scartati (`ground`); si usa la lettura dell'AI se trova almeno metà degli esercizi delle regole (`choose`), altrimenti
  le regole di sempre (`TrainingPlanParser`); collegamento al catalogo: 6 candidati simili per voce, il modello sceglie
  (`candidates`, `matchPrompt`), senza modello solo se chiaramente uguale (`localMatch`).
- `PlanEntry.exerciseId` / `exerciseID` (nuovo, facoltativo): esercizio del catalogo collegato. Salvato in Store.kt
  (`exerciseId`) e nel Codable di iOS; usato da revisione e dettaglio della scheda (`PlanAI.exerciseFor`) e dagli
  obiettivi dei consigli (`planTarget`: prima la voce collegata, poi il nome simile). Cambiando il nome a mano il
  collegamento si toglie.
- Android: `services/PlanImportAI.kt` con Gemini Nano (ML Kit GenAI Prompt API, `com.google.mlkit:genai-prompt`
  1.0.0-beta2, servizio AICore): solo su alcuni telefoni (Pixel 9 e successivi, Galaxy S24/S25...), il modello si scarica
  la prima volta. Risposta a righe "ES | nome | serie | ...", letta da `PlanAI.decodeLines`.
- iOS: `App/PlanImportAI.swift` con FoundationModels (generazione guidata `@Generable`), serve Apple Intelligence.
- Nessun esercizio trovato: niente revisione vuota, si propone il rapporto d'errore con il testo estratto.
- Sistemati 3 test che fallivano già prima (non erano mai stati eseguiti con le ultime modifiche): 3 esercizi del Free
  Exercise DB senza foto, `WeightInput.sanitize("12,5,3")` = "12,53", arrotondamento del peso (61,3 → 61,25).
- Core Kotlin compilato con kotlinc 2.1 e i 130 test eseguiti (tutti passano); app Android e codice Swift non compilati.

### 17.13 Spotify integrato spento per ora (28 ottobre 2026, Android e iOS)
Le prove hanno dato 403 su `/v1/me` ("the user may not be registered"): in modalità sviluppo Spotify accetta solo
utenti aggiunti a mano in User Management (massimo 5, proprietario con Premium; regole di febbraio 2026). Su richiesta
dell'utente l'integrazione è spenta con `AppFlags.SPOTIFY_INTEGRATION` (Basics.kt) / `AppFlags.spotifyIntegration`
(Tier.swift) = false: in Voce e musica non c'è più l'opzione Spotify, chi l'aveva scelta usa l'app musicale attiva
(Android) o "Altra app" (iOS), all'avvio non si contatta Spotify. Il codice resta tutto. Per riaccenderla: true su
entrambe le piattaforme e ripristinare i testi `tutorial.cues.body` e `music.otherAppNote` (versioni con Spotify nelle
copie in Claude outputs/correzioni_test/originali/28ott_spotify_spento).

### 17.14 Temi grafici: neutro (predefinito), originale, scuro (30 ottobre 2026, Android e iOS)
Richiesta dell'utente: grafica con i colori neutri del telefono come scelta principale; nell'Area personale si può
scegliere tra neutro, quello di prima e una modalità scura.
- Core: `AppAppearance` (`Appearance.kt` / `Appearance.swift`, test `AppearanceTests`): `system` (predefinito),
  `original`, `dark`; salvato con la chiave `appearance.theme` (stessa sulle due piattaforme). "Elimina tutti i dati"
  riporta al tema predefinito.
- **Neutro**: Android usa i colori dinamici del telefono (Material You, Android 12+; prima di Android 12 grigi e blu
  di riserva) e segue la modalità chiara/scura del telefono; iOS usa i colori di sistema (fondo `systemGroupedBackground`,
  schede piene `secondarySystemGroupedBackground` come Impostazioni, accento blu di sistema) e segue il telefono.
  **Scuro**: gli stessi colori neutri, sempre scuri. **Originale**: lo stile di prima (gradiente blu-viola, aloni,
  accento arancio, schede di vetro su iOS).
- Android: `ui/Theme.kt` ora ha `AppColors` (un insieme di colori per tema) e `Palette` restituisce i colori del tema
  attivo (stato osservabile: cambiando tema si ridisegna tutto, anche i Canvas). Nelle schermate non ci sono più
  bianchi fissi: testo = `Palette.content`, testo sopra l'accento = `Palette.onAccent`, veli = `Palette.ink(alpha)`,
  avvisi = `Palette.warning`. `MyGymTheme` imposta anche i colori Material e le icone della barra di stato.
  Sfondo all'avvio: chiaro in `values/colors.xml`, scuro in `values-night/colors.xml`.
- iOS: `ThemeStore` (in `Theme.swift`) con la scelta; `Theme.*` restituisce i colori del tema; `glassCard()` e
  `tintedCard()` passano da `CardModifier` (vetro nel tema originale, fondo pieno nei neutri);
  `ContentView` usa `preferredColorScheme(ThemeStore.shared.preferredScheme)` (prima era sempre `.dark`); i veli
  bianchi sono diventati `Color.primary.opacity(...)`; pulsante "Accedi con Apple" nero sul tema chiaro.
- Area personale: nuova scheda "Aspetto" con la scelta a tre voci; tutorial versione 3 con il passo "appearance".
- **Non compilato né provato** (Android e iOS). Da guardare sul telefono: leggibilità di tutti i testi nel tema neutro
  chiaro (soprattutto ambra "in evidenza", avvisi arancio, figura dei muscoli), fumetto del tutorial, finestre di dialogo.

### 17.15 Foto profilo (30 ottobre 2026, Android e iOS)
- In cima all'Area personale il cerchio con l'icona è diventato la foto profilo, con una piccola macchina fotografica.
  Senza foto il tocco apre la galleria; con la foto compare un menu "Scegli foto" / "Rimuovi foto". La foto compare
  anche nella riga Account.
- Selettore di sistema (Android `PickVisualMedia`, iOS `PhotosPicker`): **nessun permesso** per foto o fotocamera.
  La fotocamera non c'è (servirebbe il permesso: da decidere).
- La foto viene ritagliata quadrata al centro, ridotta a 512 px e salvata in JPEG **solo sul telefono**, esclusa dai
  backup (Android `noBackupFilesDir/profile-photo.jpg`, iOS Application Support `profile-photo.jpg` con
  `isExcludedFromBackup`); non va mai sul server. "Elimina tutti i dati" la cancella.
- Codice: `data/ProfilePhoto.kt` (`ProfilePhotoStore`, in `Graph.profilePhoto`) e `ProfileHeader` in `ui/screens/Info.kt`;
  `App/ProfilePhoto.swift` (`ProfilePhotoStore`, `ProfileAvatar`, `ProfileHeader`). Testi `profile.photo.*`;
  tutorial: aggiornato il testo del passo "Area personale".
- **Non compilato né provato** su nessuna delle due piattaforme.

### 17.16 Scheda Nutrizione disattivata (30 ottobre 2026, Android e iOS)
- La scheda Nutrizione per ora non si vede: verrà proposta più avanti come nuova opzione. **Il codice resta tutto**
  (schermate, ricerca alimenti, scheda del nutrizionista, dati salvati, consenso).
- Interruttore unico nel Core: `AppFeatures.NUTRITION_ENABLED` (`android/core/.../core/AppFeatures.kt`) e
  `AppFeatures.nutritionEnabled` (`Core/Sources/MyGymHelperCore/AppFeatures.swift`), oggi `false`. Rimettendolo a
  `true` tornano scheda, passi del tutorial e righe del confronto piani.
- Dove agisce: barra delle schede (Android `Tab.visible` in `ui/Navigation.kt`; iOS `if` in `ContentView.swift`);
  tutorial (`TutorialGuide.steps` salta i passi delle schede non visibili, versione 4); confronto dei piani
  (`Paywall.kt` / `PaywallView.swift`: nascoste le righe `compare.bmi`, `compare.nutrition`, `compare.meals`, perché
  BMI, fabbisogno e pasti stanno solo nella Nutrizione).
- Restano visibili: la riga `compare.import` ("Importa la scheda della palestra e del nutrizionista") e i testi
  legali/negozio che parlano di alimentazione: da rivedere se la Nutrizione resta spenta al rilascio.
- **Non compilato né provato** su nessuna delle due piattaforme.
### 17.17 Importazione schede: AI come motore principale e conferma dei dati mancanti (30 ottobre 2026, Android e iOS)
- La scheda importata (file o foto) si legge con l'AI del telefono (Gemini Nano su Android, Apple Intelligence su
  iPhone), che riconosce nome dell'esercizio, serie, ripetizioni, pesi e recupero. Le regole fisse restano come rete di
  sicurezza: se l'AI non c'è, è spenta o trova meno di metà degli esercizi, si usa la lettura delle regole (come prima).
- Nuovo `PlanAI.combine` (al posto di `choose` nei servizi `PlanImportAI`): sulla lettura dell'AI, i valori che l'AI non
  ha trovato si prendono dalla voce delle regole con lo stesso esercizio (`complete`, `sameName`: nome simile, ogni voce
  usata una volta sola seguendo l'ordine della scheda). I valori trovati dall'AI non si cambiano mai.
- Dati mancanti: `PlanAI.missing` (serie; ripetizioni, non per gli esercizi a tempo; peso) e `PlanAI.gaps`. Nella
  revisione di una scheda importata (`TrainingDraft.checkMissing`) i campi mancanti hanno etichetta arancione e "?", sotto
  l'esercizio c'è "Non trovati nella scheda: …" e in alto il numero di esercizi da completare. Se al salvataggio manca
  ancora qualcosa compare la conferma "Mancano alcuni dati" con l'elenco (massimo 8 esercizi, poi "…e altri"):
  "Importa comunque" salva, "Completa i dati" torna alla revisione. Non vale per le schede inserite a mano o modificate.
- Istruzioni del modello: aggiunti i formati "3 serie da 12" / "3x12" e i modi di scrivere il peso ("20 kg", "kg 20",
  "manubri da 8 kg"), con la regola di non scrivere pesi che il testo non indica.
- Il peso conta come dato mancante anche per gli esercizi a corpo libero: la conferma serve proprio a dire "va bene così".
- Testi nuovi `plans.review.missingCount`, `plans.review.missingFields`, `plans.missing.*`, `plans.confirm.*`; aggiornati
  `import.aiNote`, `plans.readByAI`, `plans.readByRules` e il passo del tutorial "Elenchi e schede" (versione invariata, 4).
- Test: `PlanAITests` (Kotlin e Swift) con due casi nuovi. **Core Kotlin compilato e test eseguiti (135 verdi)**; app
  Android e tutto il codice Swift **non compilati né provati** (le schermate vanno provate sul telefono).

## 31 ottobre 2026 – Voce e musica: tolto "Altre voci"
- Android (`Audio.kt`): tolto il pulsante "Altre voci" che apriva le impostazioni di sintesi vocale del telefono;
  "Ascolta" ora occupa tutta la riga. Su iOS il pulsante non c'era.
- Testi: tolta la chiave `audio.systemTts`; in `audio.noMale` / `audio.noFemale` tolto il rimando ad "Altre voci"
  (valgono per Android e iOS). `strings.xml` rigenerati con `tools/xcstrings_to_android.py`.
- Tutorial: nessun passo citava il pulsante, quindi invariato.
- **Non compilato né provato** (app Android e Swift).

## 31 ottobre 2026 – Voce e musica: elenco voci ridotto
- Elenco "Voce del telefono" (Android `Audio.kt`, iOS `AudioSettingsView.swift`): "Automatica" più solo le voci
  riconosciute del genere scelto, al massimo **5 femminili e 3 maschili** (le prime dell'elenco già ordinato: prima le
  voci sul telefono, poi per qualità). Le voci di genere non riconosciuto non compaiono più.
- Etichette senza il genere: "Voce 1", "Voce 2"... (Android aggiunge ancora "· online" per le voci che usano internet;
  iOS mantiene il nome tra parentesi e "· migliorata/premium").
- Tolti i pulsanti "È / Non è femminile/maschile" (correzione del genere). Le correzioni già salvate restano valide.
- Se la voce salvata non è più in elenco (cambio genere o oltre il limite) si torna su "Automatica".
- Testi: tolte le chiavi `audio.isMale`, `audio.isFemale`, `audio.notMale`, `audio.notFemale`, `audio.unknownGender`;
  da `audio.voiceNote` e `audio.voiceNoteIOS` tolta la frase sui pulsanti. `strings.xml` rigenerati.
- Tutorial: nessun passo citava l'elenco o i pulsanti, invariato.
- **Non compilato né provato** (app Android e Swift).

## 31 ottobre 2026 – Piani spostati nell'Area personale
- Barra delle schede: tolta la scheda **Piani**. Restano Allenamento, Esercizi, (Nutrizione, disattivata) e Area personale.
  Android: tolto `Tab.PLANS` (`ui/Navigation.kt`); iOS: tolto il `Tab` in `ContentView.swift` e `MainTab.plans` in
  `AppSettings.swift`.
- Area personale (Android `Info.kt`, iOS `InfoView.swift`): nuova voce **"Piani e abbonamenti"**, sempre la **seconda**
  voce: subito sotto l'account se c'è (Supabase configurato), altrimenti sotto "Aspetto". Mostra il piano attuale
  ("Piano attuale: Mid"); apre la stessa schermata di prima (`PaywallScreen` / `PaywallView`), con
  la freccia/Indietro per tornare. È visibile sempre, anche senza account configurato.
- Le note "Disponibile con Mid/Full" continuano ad aprire i Piani sopra la schermata in cui ci si trova (`nav.openPlans()`
  su Android, `NavigationLink` su iOS): nessun cambiamento.
- Testi nuovi `info.plans`, `info.plansNote %@`, `tutorial.plans.*`; tolti `tab.plans` e `tutorial.plansTab.*`;
  aggiornato `tutorial.infoTab.body`. `strings.xml` rigenerati con `tools/xcstrings_to_android.py`.
- Tutorial versione 5 (vedi `docs/TUTORIAL.md`): il passo dei Piani illumina la nuova voce nell'Area personale.
- Test del tutorial aggiornati (Kotlin e Swift): la voce Piani è nell'Area personale, subito dopo "infoTab".

- **Non compilato né provato** (app Android, Core Kotlin e tutto il codice Swift): in questa sessione la rete non
  raggiungeva Maven, quindi neanche i test del Core Kotlin sono stati eseguiti.

## 31 ottobre 2026 – "Suggerisci una funzione" e un solo indirizzo e-mail
- Indirizzo unico dell'app: **mygymhelper@gmail.com**, in `AppContact.EMAIL` / `AppContact.email` (Core, file
  `ErrorReport.kt` / `ErrorReport.swift`). Tutte le e-mail vanno lì: anche i rapporti d'errore (`ErrorReport.EMAIL`/`email`,
  prima ngalmeno@gmail.com) e il contatto nello User-Agent di Open Food Facts (Android `contact.email`, predefinito ora
  mygymhelper@gmail.com in `build.gradle.kts` e `local.properties.example`; iOS `MyGymHelperContactEmail` in
  `Support/Info.plist` e valore di riserva in `FoodSearchView.swift`).
- Area personale, **ultima voce** (sotto "Elimina tutti i dati"): "Suggerisci una funzione". Apre l'app di posta con
  l'e-mail per mygymhelper@gmail.com, oggetto "MyGymHelper <versione> – suggerimento", una riga che invita a scrivere
  (`suggest.intro`, tradotta) e in fondo versione dell'app, sistema, modello e lingua (nessun dato personale).
  Senza app di posta compare "Nessuna app di posta trovata. Scrivi a mygymhelper@gmail.com." (`suggest.noMail`).
  - Core: `Suggestion.subject` / `Suggestion.body`; test nuovi `ContactTests.kt` / `ContactTests.swift`.
  - Android: `SuggestRow` in `Info.kt`; l'apertura della posta è ora `ErrorReporter.openMail(...)`, condivisa con i
    rapporti d'errore (`SENDTO mailto:`, poi `ACTION_SEND`); `ErrorReporter.info()` ora è pubblica.
  - iOS: `suggestRow` in `InfoView.swift`: `MailComposeView` (nuova, in `ErrorReporter.swift`) se Mail è configurata,
    altrimenti link `mailto:`; se nessuna app lo apre si mostra l'indirizzo.
- Testi nuovi `info.suggest`, `info.suggestNote`, `suggest.intro`, `suggest.noMail %@`, `tutorial.suggest.*`;
  `strings.xml` rigenerati.
- Tutorial versione 6: passo "suggest" sulla nuova voce (vedi `docs/TUTORIAL.md`).
- Da decidere: nell'informativa privacy (`App/Legal/privacy.*.md` e `android/.../assets/legal/privacy.*.md`) il
  contatto privacy è ancora il segnaposto "[indirizzo e-mail]": non modificato.
- **Non compilato né provato** (app Android, Core Kotlin e tutto il codice Swift): in questa sessione la rete non
  raggiungeva Maven.


## 31 ottobre 2026 – Serie diverse sullo stesso esercizio (Android e iOS)
Ogni serie di un esercizio può avere ripetizioni e peso diversi (es. piramide 12/10/8 con 40/45/50 kg). La pausa resta
unica. Funzione dei piani **Mid e Full** (`Feature.VARIED_SETS` / `.variedSets`, riga nuova nel confronto dei piani).

- **Core** (Kotlin `Training.kt`, `WorkoutLists.kt`, `Coaching.kt`, `Store.kt`, `Plans.kt`, `PlanAI.kt`; Swift
  `WorkoutParameters.swift`, `WorkoutLists.swift`, `SessionEngine.swift`, `AdaptiveCoach.swift`, `PlanParser.swift`, `PlanAI.swift`):
  - `SetTarget` (ripetizioni + peso di una serie). `WorkoutParameters.perSet` (vuoto = serie uguali, come prima);
    `WorkoutParameters.of(serie, pausa)` torna a serie uguali se sono tutte identiche; `targets`, `isVaried`,
    `maxWeightKg`, `uniform()`. `clamped()` limita anche ogni serie (max 10 serie).
  - `WorkoutItem.perSet` salvato negli elenchi (campo JSON nuovo `perSet`; i dati salvati prima si leggono come serie uguali).
  - `SessionEngine` con ripetizioni per serie (`SessionEngine(repsPerSet, pausa)`; il vecchio costruttore resta);
    `targetReps` = serie in corso (in pausa: la prossima); ogni `SetRecord` ha le ripetizioni della sua serie.
  - Coach: `CoachingResult.applied` e `AdaptiveAdvice.parameters(current)` / `parameters(from:)` applicano la stessa
    variazione a ogni serie mantenendo lo schema (+carico su ogni serie, +1 ripetizione dove è a corpo libero,
    serie in più = copia dell'ultima, serie in meno = tolta l'ultima). Il motore adattivo usa come peso il più alto della sessione.
  - Storico: ogni serie salva il suo peso (Android `SetLog.weightKg`, iOS `SetLogRecord.weightKg` opzionale; le serie
    salvate prima usano il peso della sessione). `plannedTargets` ripropone lo schema dell'ultima sessione.
  - Schede caricate: `PlanAI.mergeRepeated` (chiamato alla fine di `applyMatches`, quindi in tutti i percorsi
    dell'importazione) unisce **tutte le righe con lo stesso esercizio nello stesso giorno** (stesso nome, maiuscole e
    spazi a parte) in una voce sola con `perSet` (`PlanSet`, valori facoltativi). Una riga senza serie vale una serie;
    da un intervallo "8-12" si prende il minimo; righe tutte uguali tornano a una voce normale; esercizi a tempo non si
    uniscono. Dati mancanti: ripetizioni o peso mancanti in almeno una serie. `PlanTarget.perSet` porta lo schema
    nell'esercizio aperto dalla scheda.
  - Test nuovi `VariedSetsTests.kt` / `VariedSetsTests.swift` (stessi casi); `TutorialTests` aggiornati.
- **Modifica dell'esercizio** (Android `ItemEditorScreen` in `Workout.kt`, iOS `WorkoutSetupView.swift`): Mid/Full
  sempre una riga per serie (numero, ripetizioni, peso, cestino) + "Aggiungi serie" (copia l'ultima) + pausa.
  Free: schermata di prima (serie uguali) con la riga "Serie con ripetizioni e pesi diversi: con Mid e Full" che apre i piani.
  Precompilazione da scheda (anche a serie diverse) e dall'ultima sessione (stesso schema).
- **Sessione**: durante la serie si vede il peso di quella serie (più grande con le serie diverse) e l'obiettivo della
  serie; in pausa "N ripetizioni · X kg" della prossima; a voce, a inizio pausa, "Prossima serie: N ripetizioni con X chili"
  (solo se la serie successiva è diversa dalla precedente). Riepilogo con il peso di ogni serie, storico con "40/45/50 kg".
- **Revisione scheda importata** (Android `Plans.kt`, iOS `TrainingPlansView.swift`): per le voci unite una riga per
  serie (ripetizioni, peso, elimina) + "Aggiungi serie" + recupero; il dettaglio mostra "10 × 40 kg · 8 × 50 kg · 90 s".
- Testi nuovi `sets.*`, `session.nextTarget`, `voice.nextSet`, `voice.nextSetBodyweight`, `compare.variedSets`,
  `plans.review.variedSets`, `plans.review.reps`, `tutorial.variedSets.*`; aggiornato `tutorial.list.body`;
  `strings.xml` rigenerati.
- Tutorial versione 7: passo "variedSets" dopo "addExercise" (vedi `docs/TUTORIAL.md`).
- Note: un esercizio salvato con serie diverse continua a funzionare anche se l'utente torna al Free (la sessione usa
  le sue serie); se nel Free lo modifica e salva, diventa a serie uguali (come la prima serie).
- **Verifica**: Core Kotlin compilato ed eseguiti tutti i test (146 superati, nessuno fallito; erano 137, + 9 nuovi) con il compilatore Kotlin
  incluso in Gradle (senza Maven, con un piccolo sostituto di JUnit). **Non compilati**: app Android (Compose) e tutto
  il codice Swift (Core e app).

## 2 novembre 2026 – Serie diverse: numero di serie per riga (Android e iOS)
- Nella modifica dell'esercizio (Mid/Full) ogni riga è ora un **gruppo di serie uguali**: numero di serie, ripetizioni e
  peso (es. "Serie 1–3": 3 × 10 con 40 kg, "Serie 4–5": 2 × 8 con 50 kg). Il titolo della riga dice quali serie sono.
  "Aggiungi serie" aggiunge una riga con 1 serie (ripetizioni e peso dell'ultima riga); il cestino toglie la riga.
  Massimo 10 serie in tutto: il contatore delle serie di una riga si ferma quando si arriva a 10.
- Core: `SetGroup` (Kotlin `Training.kt`, Swift `WorkoutParameters.swift`) con `group` (serie uguali consecutive →
  una riga) ed `expand` (righe → serie). Il modello salvato non cambia: l'esercizio tiene sempre `perSet` serie per serie;
  le righe si ricostruiscono all'apertura. Test nuovi in `VariedSetsTests` (Kotlin e Swift).
- Android `ItemEditorScreen` / `SetGroupEditor` in `Workout.kt`; iOS `variedSetsCard` in `WorkoutSetupView.swift`.
  Il piano Free resta con serie uguali.
- Testi nuovi `sets.range`, `sets.removeRow`; aggiornati `sets.hint` e `tutorial.variedSets.body`; `strings.xml` rigenerati.
- La revisione delle schede importate resta con una riga per serie (non modificata).
- **Verifica**: Core Kotlin compilato, 147 test superati. **Non compilati**: app Android e codice Swift.

## 2 novembre 2026 – Voce e musica: una sola voce extra
- Elenco "Voce del telefono" (Android `Audio.kt`, costante `EXTRA_VOICES = 1`; iOS `AudioSettingsView.swift`, `prefix(1)`):
  per il femminile e per il maschile restano solo "Automatica" e "Voce 1" (la prima voce del genere scelto,
  nell'ordine già usato: prima quelle sul telefono, poi per qualità). Sostituisce il limite 5 femminili / 3 maschili.
- Una voce salvata che non è più in elenco torna su "Automatica" (logica già presente).
- Tutorial e testi invariati (non citano il numero di voci).
- **Non compilato né provato** (app Android e Swift).

## 2 novembre 2026 – Attrezzi in casa e filtro "Solo i miei attrezzi" (Android e iOS, solo piano Full)
- Nuova funzione `HOME_EQUIPMENT` / `.homeEquipment` (piano minimo Full) in `Basics.kt` / `Tier.swift`.
- Core: `HomeEquipment` (Kotlin `Catalog.kt`, Swift `Catalog.swift`): elenco degli attrezzi segnabili (manubri,
  bilanciere, bilanciere EZ, kettlebell, elastici, palla svizzera, palla medica, rullo, cavi, macchine, altro attrezzo),
  filtro (restano corpo libero, esercizi senza attrezzo e quelli con un attrezzo posseduto; gli attrezzi sconosciuti
  delle fonti esterne si nascondono), salvataggio come testo separato da virgole. Test nuovi `HomeEquipmentTests`.
- Impostazioni salvate sul telefono (non sono dati sulla salute): `equipment.owned` ed `equipment.filter`
  (Android `Prefs.kt`, azzerate da "Elimina tutti i dati"; iOS `AppSettings.swift`).
- Interfaccia, nelle schede **Esercizi** e **Aggiungi esercizio** (Allenamento): sopra i filtri il riquadro
  "Attrezzi in casa" con gli attrezzi segnati e il pulsante "Aggiungi o togli attrezzi" (elenco con un tocco per
  aggiungere/togliere); tra i filtri (sotto i tipi di esercizio) il chip "Solo i miei attrezzi" per accendere o
  spegnere il filtro. Free e Mid: nel riquadro c'è l'invito ai piani e il chip non compare; il filtro è attivo solo
  con il piano Full anche se era stato acceso prima.
  Android: `HomeEquipmentCard`, `HomeEquipmentSheet`, `EquipmentFilterChip`, `equipmentFiltered` in `Exercises.kt`,
  usati anche in `AddExerciseScreen` (`Workout.kt`). iOS: stessi nomi in `ExercisesView.swift`, usati anche in
  `AddExerciseView` (`WorkoutSetupView.swift`).
- Piani e abbonamenti: nuova riga del confronto `compare.homeEquipment` (solo Full).
- Tutorial versione 8: passo "homeEquipment" dopo "exercisesLinks" (vedi `docs/TUTORIAL.md`).
- Testi nuovi `equipment.home.*`, `compare.homeEquipment`, `tutorial.homeEquipment.*`; `strings.xml` rigenerati.


## 2 novembre 2026 – Revisione della scheda ogni due settimane con l'AI del telefono (Android e iOS, solo piano Full)
Richiesta dell'utente: ogni due settimane, dallo storico, controllare se le ripetizioni sono eseguite correttamente; dopo
una domanda all'utente (allenamento troppo leggero / troppo pesante) aumentare o ridurre i carichi; la proposta va in
"Consiglio per oggi" (scelta dell'utente) e con "Applica" si aggiornano le schede; si deve poter tornare alla scheda precedente.
Scelte confermate dall'utente: solo Full; domanda a fine allenamento; Applica aggiorna scheda **ed elenchi**; si tiene
**una** versione precedente. Motore AI: quello già integrato (Gemini Nano / ML Kit GenAI su Android, Apple
Intelligence / FoundationModels su iPhone); senza AI resta la proposta a regole.
- Core: `PlanReview.kt` / `PlanReview.swift` (test `PlanReviewTests`, stessi casi). `PlanReviewer.isDue`: 14 giorni
  dall'ultimo controllo (la prima volta da quando la scheda è stata caricata) e almeno 2 sessioni di esercizi della
  scheda negli ultimi 14 giorni. `quality`: ripetizioni fatte, serie interrotte, calo di velocità delle ultime due
  settimane ("corrette" = ≥ 90% fatte e ≤ 20% di serie interrotte). `propose` per ogni esercizio della scheda (scheda
  attiva = la più recente, come i consigli):
  troppo leggero + ripetizioni corrette → carico +2,5% a passi di 1,25 kg (due passi se tutto facile, e pausa −15 s),
  corpo libero +2 ripetizioni; troppo leggero ma ripetizioni mancate → si tiene il carico ("prima completale");
  troppo pesante → −10% (corpo libero −2 ripetizioni), una serie in meno se fatte < 70%, pausa +15 s;
  giusto → −8% se fatte < 70%, piccolo aumento se tutto facile, altrimenti si tiene. Serie diverse: stessa variazione
  su ogni serie. Peso mancante nella scheda = quello dell'ultima sessione.
  AI: `aiPrompt` / `decodeAI` (righe "ES | n | -1/0/+1" e "NOTA | ...") / `applyAI`: il modello può solo spostare di un
  passo, mai sotto il carico di prima con "troppo leggero" né sopra con "troppo pesante", e scrive una nota breve.
  `applyToPlan`, `applyToItems`, `touchedLists`, `prefersPlan` (dopo Applica il precompilare usa la scheda e non
  l'ultima sessione). Stato `PlanReviewState` (ultimo controllo, proposta in attesa, copia `PlanBackup`).
- Android: stato in `AppData.planReview` (stesso file dei dati sanitari, `PlanReviewCodec`); `AppStore.applyPlanReview`
  / `restorePlanBackup` / `updatePlanReview` (eliminando la scheda si tolgono proposta e copia);
  `services/PlanReviewService.kt` (domanda, proposta, Gemini Nano in `PlanReviewAI`); UI in `ui/screens/PlanReviewUi.kt`:
  domanda nel riepilogo di fine sessione (`SessionSummary`), proposta in "Consiglio per oggi" della modifica
  dell'esercizio (`ItemEditorScreen`), card "Suggeriti" e "Torna alla scheda precedente" nel dettaglio della scheda.
- iOS: `App/PlanReviewStore.swift` (stato in Application Support/plan-review.json, escluso dai backup, solo con il
  consenso, cancellato in `LocalData.deleteHealthData`; Apple Intelligence in `PlanReviewAI`, stessa richiesta di
  Android), `App/PlanReviewViews.swift`; collegato in `SessionSummaryView`, `ItemEditorView` (WorkoutSetupView.swift),
  `TrainingPlanDetailView`.
- "Non ora" nasconde la domanda solo per quel riepilogo (si richiede alla sessione dopo); "Ignora" scarta la proposta
  (prossima domanda fra due settimane).
- Testi nuovi `review.*` e `tutorial.planReview.*`; `strings.xml` rigenerati. Tutorial versione 9: passo "planReview"
  dopo "history" (vedi `docs/TUTORIAL.md`).
- Verificato: Core Kotlin compilato con kotlinc 2.1 e 162 test eseguiti, tutti superati (11 nuovi). **Non compilati**:
  app Android (Compose, ML Kit) e tutto il codice Swift (Core e App): da compilare con Android Studio e Xcode, e da
  provare la risposta di Gemini Nano / Apple Intelligence su un telefono compatibile.
- Prove (2 novembre 2026, solo build di debug): **cronologia finta** nell'Area personale, sotto "Piano simulato".
  "Crea: ripetizioni tutte fatte" / "Crea: serie interrotte e fatica" creano 4 sessioni (12, 8, 4 e 1 giorno fa) per
  ogni esercizio della scheda più recente collegato al catalogo, con i pesi della scheda (se mancano 20 kg, 0 a corpo
  libero); spostano indietro di quanto serve le date di **tutte** le schede (così quella attiva resta la più recente e
  risulta caricata da più di 14 giorni) e azzerano la revisione (ultimo controllo, proposta, copia). Poi basta finire
  un esercizio della scheda con il piano Full per vedere la domanda. "Togli la cronologia finta" toglie solo le
  sessioni finte (le date delle schede restano spostate). Core `FakeHistory.kt` / `FakeHistory.swift` (test in
  `PlanReviewTests`); Android `AppStore.addFakePlanHistory` / `removeFakePlanHistory` (id delle sessioni con prefisso
  `debug-`) e `FakeHistoryCard` in Info.kt; iOS `App/FakeHistoryDebug.swift` (`#if DEBUG`, id ricordati in UserDefaults).
  Non è una funzione per l'utente: il tutorial non cambia. Core Kotlin: 163 test superati; app Android e Swift non compilati.
- Kg nel consiglio (2 novembre 2026, Android e iOS): "Consiglio per oggi" (consiglio adattivo e proposta della
  revisione), "La prossima volta" del riepilogo e la card "Suggeriti" mostrano una riga del carico in kg rispetto ai
  valori attuali: "Carico: 60 → 62,5 kg (+2,5 kg)", serie diverse "40/45 → 42,5/47,5 kg (+2,5 kg)", "Carico: 60 kg
  (invariato)", "Carico: corpo libero". Android `loadChangeLine` (Workout.kt, parametro `before` di `AdviceCard`),
  iOS `AdviceText.loadChange` (CoachingText.swift, `before` di `AdviceCard`). Testi `advice.load*`. Non compilato.
- Strumenti di test anche fuori dal debug (2 novembre 2026, richiesta dell'utente): l'app di prova installata non
  mostrava il riquadro (era solo nelle build di debug). Nuovo interruttore `AppFlags.TEST_TOOLS` (Basics.kt) /
  `AppFlags.testTools` (Tier.swift) = **true: DA METTERE A false PRIMA DELLA PUBBLICAZIONE** (l'utente se lo segna).
  Con l'interruttore acceso (o in debug) si vedono il piano simulato (BillingManager / SubscriptionManager con
  `TestTools.enabled`) e la card "Cronologia finta (prove)", ora sia nell'Area personale sia nel **dettaglio della
  scheda**, con il pulsante "Simula il piano Full" se il piano non è Full. Android `FakeHistoryCard` in
  PlanReviewUi.kt; iOS `TestTools` e `FakeHistoryCard` in FakeHistoryDebug.swift (non più `#if DEBUG`).
- "Ripetizioni completate" (2 novembre 2026, Android e iOS): sotto "Mi sono fermato" durante la serie; chiude la serie
  con tutte le ripetizioni previste (`controller.stop(targetReps)`: serie completa, non interrotta), senza scrivere il
  numero. Testo `session.setDone`; tutorial: aggiornato il testo del passo "session". Non compilato.

## 2 novembre 2026 – Attrezzi in casa nascosti; filtro "Corpo libero" (Android e iOS)
- Gli attrezzi in casa (sezione precedente) sono **nascosti per ora** con l'interruttore `AppFlags.HOME_EQUIPMENT`
  (Kotlin `Basics.kt`) / `AppFlags.homeEquipment` (Swift `Tier.swift`) = false: spariscono riquadro, chip "Solo i miei
  attrezzi", riga del confronto dei piani e passo del tutorial; il filtro non agisce. Il codice e le impostazioni
  salvate restano: per riaccendere tutto basta mettere true.
- Nuovo filtro **"Corpo libero"** (per tutti i piani) tra i filtri degli esercizi, sotto i tipi, nelle schede Esercizi
  e Aggiungi esercizio: acceso, esclude tutti gli esercizi che usano un attrezzo (resta solo `equipment` = bodyweight;
  tutti gli 876 esercizi inclusi hanno l'attrezzo indicato). Non viene salvato: si spegne riaprendo l'app.
  Core: `CatalogFilter.isBodyweight` / `bodyweightOnly` (Kotlin e Swift), test in `HomeEquipmentTests`.
  Android `BodyweightChip` (`Exercises.kt`, usato anche in `Workout.kt`); iOS `BodyweightChip` (`ExercisesView.swift`,
  usato anche in `WorkoutSetupView.swift`).
- Testo nuovo `ex.bodyweight`; aggiornati `tutorial.exercisesTab.body` e `tutorial.addExercise.body`; tutorial versione 10;
  `strings.xml` rigenerati.

## 2 novembre 2026 – "Fai esercizio alternativo" (Android e iOS, tutti i piani)

Se non si può fare un esercizio (macchina occupata, attrezzo che manca), nella schermata **Pronto** c'è il pulsante
**"Fai esercizio alternativo"**. Apre la stessa ricerca di "Aggiungi esercizio" (mappa del corpo, tipo, "Corpo libero",
ricerca, lista a pagine) con i **muscoli principali dell'esercizio originale già scelti** (mappa sul retro se stanno tutti
dietro); l'esercizio originale non compare. Toccando un esercizio si torna a **Pronto** con l'alternativa:

- vale **solo per questa sessione**: l'elenco non cambia; a fine esercizio la riga dell'elenco diventa verde come se
  fosse stato fatto l'originale, e nello Storico finisce l'esercizio fatto davvero (l'alternativa);
- stesse serie, ripetizioni e pausa dell'originale (anche con le serie diverse); se l'alternativa è a corpo libero il
  peso si toglie;
- in Pronto si vede "Al posto di: …" e il link "Torna a …"; si può cambiare di nuovo alternativa (si parte sempre
  dall'originale); con "Esercizio successivo" il prossimo esercizio riparte normale.

Codice: Core `WorkoutListLogic.alternativeMuscles / alternativeOnBack / alternatives / alternativeParameters`
(Kotlin e Swift, test in `WorkoutListTests`). Android: `Screen.AlternativeExercise` e `Screen.Session.replacedFrom`
(Navigation.kt), `AlternativeExerciseScreen` e `ExerciseBrowser` (ricerca in comune con `AddExerciseScreen`) in
Workout.kt. iOS: `AddExerciseView(alternativeFor:onPick:)`, `SessionTarget.replacing` e il pulsante in `ReadyView`
(WorkoutSessionView.swift). Stringhe `alternative.*` e passo del tutorial "alternative" (versione 11).
Nota: `App/Localizable.xcstrings` è stato riscritto nel formato di Xcode (chiavi in ordine alfabetico, `" : "`): stesso
contenuto, solo l'ordine delle chiavi è cambiato.

## 2 novembre 2026 – Schede pronte: difficoltà in evidenza (Android e iOS, tutti i piani)

Nella schermata **Schede pronte**, sotto l'intestazione, c'è il titolo **"Scegli la tua scheda di esercizi"**
(`presets.choose`). Ogni scheda (anche la consigliata del mese, e in cima al dettaglio della scheda) mostra la difficoltà
in una **pastiglia colorata** con tre tacche tipo "segnale" e il testo "Difficoltà: …" (`presets.difficulty %@`):
Principiante verde (1 tacca), Intermedio arancione (2), Esperto rosso (3, oggi nessuna scheda è di questo livello).
La riga dei dati (`planFacts`) ora dice solo "N allenamenti a settimana": tolti il livello (è nella pastiglia) e il
numero di giorni (stringa `presets.days` eliminata).

**Tutte le schede sono da 3 o 4 allenamenti a settimana**: Push/Pull/Legs passa da 6 a 3 (in `preset_plans.py`, schede
rigenerate); la scheda del mese non scende più a 2: con meno di 2,5 allenamenti a settimana nel mese scorso restano
2 allenamenti (A e B) da alternare 3 volte a settimana. Aggiornati i testi `presets.free.summary` ("3 volte a settimana")
e `presets.ppl.summary` ("3 allenamenti a settimana"). Nuovo test `everyPlanHasThreeOrFourWorkoutsAWeek` (Kotlin e Swift).

Codice: Android `DifficultyBadge` / `difficultyStyle` in `ui/screens/Presets.kt` (colori `Palette.done/warning/danger`);
iOS `DifficultyBadge` in `App/PresetsView.swift` (`Theme.done`, `.orange`, `.red`). Nessuna modifica al Core.
Aggiornato `tutorial.presets.body`, tutorial versione 12; `strings.xml` rigenerati.

### Esercizio alternativo definitivo: "Sostituisci nell'elenco" (2 novembre 2026, Android e iOS)

Quando in **Pronto** c'è un esercizio alternativo di una riga dell'elenco, compare anche **"Sostituisci nell'elenco"**.
Dopo la conferma la riga resta la stessa (stessa posizione, stesso stato svolto/da fare) ma con il nuovo esercizio e i
parametri di adesso (quelli dell'originale, senza peso se l'alternativa è a corpo libero; poi si cambiano con la matita).
La schermata Pronto prosegue con l'esercizio nuovo, senza più "Al posto di". Non compare per gli esercizi avviati fuori
da un elenco. Core: `WorkoutListLogic.replaceExercise` (Kotlin e Swift, test in `WorkoutListTests`).

## 3 novembre 2026 – Importazione delle schede da file disattivata (Android e iOS)
- Nuovo interruttore `AppFeatures.PLAN_FILE_IMPORT_ENABLED` / `AppFeatures.planFileImportEnabled` = **false**.
- Card "Importa" (`ImportButtons` in Android `Plans.kt` e iOS `TrainingPlansView.swift`, usata per le schede di
  allenamento e, quando la Nutrizione tornerà, per la scheda del nutrizionista): nascosto il pulsante **File**
  (PDF, Excel, Word, CSV, testo). Restano **Foto** e **Inserisci a mano**, e l'interruttore dell'AI del telefono.
- Testi della card: con i file spenti si mostrano `import.formatsPhoto` e `import.privacyPhoto` (solo foto) al posto
  di `import.formats` e `import.privacy`, che restano per quando si riattiva.
- Il codice di lettura dei file (`TextExtractor`, `OfficeText`, `PlanParser`) e i test restano invariati.
- Tutorial: aggiornato il testo del passo "Elenchi e schede" (solo foto); versione invariata.
- Per riattivare: mettere `true` nei due `AppFeatures` e rimettere nel testo `tutorial.exercisesLinks.body` "da foto,
  PDF, Word o Excel" (vedi `docs/TUTORIAL.md`), poi rigenerare gli `strings.xml`.
- **Non compilato né provato** (app Android e Swift).

## 3 novembre 2026 – Caricamento delle schede di allenamento disattivato anche da foto (Android e iOS)
- Nuovo interruttore `AppFeatures.PLAN_PHOTO_IMPORT_ENABLED` / `AppFeatures.planPhotoImportEnabled` = **false** e
  valore derivato `PLAN_IMPORT_ENABLED` / `planImportEnabled` (vero se file o foto sono attivi).
- Con file e foto spenti la card "Importa" diventa **"Nuova scheda"** (`import.titleManual`) con il solo pulsante
  **Inserisci a mano**: nascosti il pulsante Foto, l'interruttore dell'AI del telefono e i testi su formati e privacy.
  Le schede già salvate restano visibili e utilizzabili.
- Sottotitolo della schermata Schede: `plans.list.subtitleManual` ("inserita a mano") al posto di `plans.list.subtitle`.
- Tutorial, passo "Elenchi e schede": `TutorialStep.bodyKey` (Core Kotlin e Swift) usa `tutorial.exercisesLinks.bodyManual`
  quando il caricamento è spento; il testo originale `tutorial.exercisesLinks.body` resta per la riattivazione.
- Il codice di lettura (foto, OCR, `PlanImportAI`, `PlanParser`) resta invariato.
- Per riattivare la foto: mettere `true` in `PLAN_PHOTO_IMPORT_ENABLED` / `planPhotoImportEnabled` (tornano da soli
  card, sottotitolo e tutorial).
- `strings.xml` rigenerati. **Non compilato né provato** (app Android e Swift, test del Core).


## 3 novembre 2026 – Avviso a voce prima dell'ultima serie (Android e iOS, tutti i piani)
- Nella pausa che precede l'ultima serie di ogni esercizio (servono almeno 2 serie: con una sola non c'è pausa), dopo
  la frase della pausa (e dopo l'annuncio della serie diversa, se c'è) la voce dice:
  - **esercizio di un elenco con altri esercizi da fare**: "la prossima sarà l'ultima serie", poi il prossimo esercizio
    (`WorkoutListLogic.nextPending`): nome, muscoli principali, attrezzo (o "corpo libero") e dove mettere il telefono
    (posizione proposta da `WorkoutListLogic.suggestedPosition`: coscia per le gambe, braccio sopra il gomito per il resto);
  - **ultimo esercizio dell'elenco** (nessun altro non svolto): "Stai per iniziare l'ultima serie della giornata. Bravo,
    hai finito tutti i tuoi esercizi!";
  - **conteggio libero / esercizio fuori da un elenco** o esercizio successivo non trovato nel catalogo: solo "la prossima
    sarà l'ultima serie".
- Il prossimo esercizio si annuncia anche se la spunta "esercizio successivo" è spenta (è comunque il prossimo da fare).
- Core: `WorkoutListLogic.isRestBeforeLastSet` e `WorkoutListLogic.lastSetNotice` + tipo `LastSetNotice`
  (`WorkoutLists.kt` / `WorkoutLists.swift`), con test in `WorkoutListTests` (stessi casi sui due lati).
- App: `CueService.announceLastSet` (Kotlin e Swift); `SessionController` riceve una funzione `lastSetNotice`, chiamata
  al momento della pausa (legge lo stato attuale dell'elenco). Creata in `Workout.kt` (`ActiveSession`) e in
  `WorkoutSessionView.swift` (con `CatalogStore` dall'environment).
- Stringhe nuove: `voice.lastSetNotice.1/.2`, `voice.nextExercise %@`, `voice.nextMuscles %@`, `voice.nextEquipment %@`,
  `voice.nextBodyweight`, `voice.nextPosition %@`, `voice.position.<posizione>`, `voice.lastOfDay`; `strings.xml` rigenerati.
- Tutorial: testo del passo "session" aggiornato, versione 13.
- Priorità all'avviso di partenza: il conto alla rovescia di fine pausa ("3, 2, 1") e la frase di inizio serie
  interrompono quello che la voce sta ancora dicendo (`CueService.play` con `flush` per `RestCountdown`, `RestEnded`,
  `SetStarted`, Kotlin e Swift). Con pause corte l'annuncio lungo viene quindi troncato, ma la serie parte in orario.
- **Non compilato né provato** (Core Kotlin, app Android e Swift).

## 3 novembre 2026 – Attrezzi in casa di nuovo visibili (Android e iOS)
- Annullato l'occultamento del 2 novembre (era un errore): `AppFlags.HOME_EQUIPMENT` / `AppFlags.homeEquipment` = true.
  Tornano riquadro "Attrezzi in casa", chip "Solo i miei attrezzi" (Full), riga del confronto dei piani e passo del
  tutorial "homeEquipment". Tutorial versione 14.

## 3 novembre 2026 – Licenze gratuite manuali (Supabase, Android e iOS)
- Nuova migrazione `supabase/migrations/20261103000000_manual_licenses.sql`: tabella `licensing.manual_grants`,
  funzioni `licensing.grant_free_license(utente, data_fine, piano='full', nota)` e `licensing.revoke_free_license(utente)`,
  vista `licensing.free_licenses`; `get_my_entitlement()` ricreata con la colonna `source` e il piano migliore tra
  store e licenza manuale. Istruzioni in `docs/BACKEND.md` sezione 9. SQL provato su PostgreSQL 16 (schema `auth` simulato).
- Le app ora leggono il piano anche dal server (prima solo da Google Play / App Store): Android `AccountService.fetchEntitlement`
  (nuova dipendenza `supabase-postgrest`), `BillingManager.refreshServer` e `freeLicenseUntil`, cache in `Prefs`
  (`server.*`); iOS `AccountService.fetchEntitlement`, `SubscriptionManager.refreshServer`/`freeLicenseUntil`
  (cache in UserDefaults `server.*`), `ServerCheck` in entrambe. Piano = il migliore tra store e server.
- Piani: riga "Licenza gratuita fino al …" (`plans.freeLicense %@`); "Gestisci" nascosto se il piano viene solo
  dalla licenza gratuita. Tutorial: testo del passo "plans" aggiornato, nessun passo nuovo.
- `Localizable.xcstrings` riscritto con le chiavi in ordine alfabetico (contenuto invariato a parte le due stringhe).
- **Non compilato né provato** (app Android e Swift).


## 3 novembre 2026 – Testi legali da un'unica fonte e sito web (GitHub Pages)
- Fonte unica dei testi legali: cartella `legal/` (privacy, disclaimer, consenso, it/en) con blocchi
  `<!--android-->`, `<!--ios-->`, `<!--web-->` e segnaposto `{{TITOLARE}}`, `{{EMAIL}}`, `{{DATA}}`, `{{SITO}}`.
  `python tools/build_legal.py` rigenera `App/Legal/*.md`, `android/app/src/main/assets/legal/*.md` e `site/`.
  **Non modificare più a mano** i file generati.
- Scelte: titolare Nicola Gabriele Almeno, contatto mygymhelper@gmail.com, Supabase Inc. responsabile del trattamento
  (regione eu-central-1, Francoforte); accesso al lancio solo Google su Android (Google e Apple su iOS); tolti Facebook,
  e-mail e Open Food Facts (nutrizione disattivata); "sezione Info" diventa "Area personale"; tolti i segni "BOZZA"
  dalle sezioni 10-11, che restano da far verificare a un legale. Indirizzo del titolare: `INDIRIZZO` nello script, vuoto.
- Sito: `site/` da pubblicare nel repository pubblico `mygymhelper-site.github.io` (account GitHub mygymhelper-site).
  Indirizzi: `/privacy.html` e `/delete-account.html` scelgono la lingua del browser; `/it/...` e `/en/...` fissi.
- `privacy.url` in `android/local.properties` e `MyGymHelperPrivacyURL` in `Support/Info.plist` puntano a
  `https://mygymhelper-site.github.io/privacy.html`.
- Generazione verificata (script eseguito, pagine visualizzate in un browser); app **non ricompilate**.

## 3 novembre 2026 – Catalogo MuscleWiki spento (Android e iOS)
- Nuovo interruttore `AppFlags.MUSCLEWIKI_CATALOG` (Basics.kt) / `AppFlags.muscleWikiCatalog` (Tier.swift) = false:
  `CatalogRepository.refreshRemote()` e `CatalogStore.refreshRemote()` non chiamano più la funzione `catalog`;
  resta l'elenco incluso nell'app (nostri + Free Exercise DB). Codice e funzione `catalog` restano per il futuro.
- La funzione `catalog` non va pubblicata (niente segreto `MUSCLEWIKI_API_KEY`); se era già pubblicata si può eliminare
  dalla dashboard (Edge Functions). Informativa: tolta la frase sull'elenco esercizi dal server (sezione 10 "Account e acquisti").
- Nessun cambiamento visibile, tutorial invariato. **Non compilato** (Android e Swift).

## 3 novembre 2026 – Preparazione alla pubblicazione su Google Play
- `AppFlags.TEST_TOOLS` (Basics.kt) e `AppFlags.testTools` (Tier.swift) = **false**: piano simulato e cronologia finta
  restano solo nelle build di debug. **Non compilato.**
- Testi della scheda Google Play (en/it), campi, abbonamenti e lista screenshot: `docs/STORE_TEXTS_PLAY.md`.
  Immagine in evidenza 1024×500: `android/store/feature-graphic-en.png` e `-it.png`.
- Aperto: nel confronto dei piani la riga `compare.import` ("Importa la scheda della palestra e del nutrizionista")
  resta visibile anche se l'importazione e la nutrizione sono disattivate (da decidere con l'utente).
- Deciso (3 novembre 2026): la riga `compare.import` del confronto dei piani si nasconde finché l'importazione delle
  schede è spenta (`AppFeatures.PLAN_IMPORT_ENABLED` / `AppFeatures.planImportEnabled`), su Android e iOS.
  Tutorial invariato (il passo "plans" non cita l'importazione). **Non compilato.**

## 3 novembre 2026 – Segnalazione dei testi dell'IA (Android e iOS)
- Norme di Google Play sui contenuti generati dall'IA: sotto la nota dell'IA della revisione della scheda (card
  "Consiglio per oggi" e card "Suggeriti" nel dettaglio della scheda) c'è "Segnala il testo dell'IA". Apre l'app di
  posta con l'e-mail a mygymhelper@gmail.com: invito a descrivere il problema, testo dell'IA, dati tecnici.
  Senza app di posta mostra l'indirizzo (`suggest.noMail`).
- Core: `AIContentReport` (ErrorReport.kt / ErrorReport.swift) con test in ContactTests (Kotlin e Swift).
- UI: `AiNote` in PlanReviewUi.kt, `AINoteView` in PlanReviewViews.swift. Stringhe `review.report`,
  `review.report.intro`; tutorial: aggiunta una frase al passo `planReview`. strings.xml rigenerati.
- **Non compilato né testato** (qui c'è solo Java 11: niente Gradle/Android; niente Xcode).

## 4 novembre 2026 – Tolto il piano Mid (iOS)
Stessa modifica già fatta su Android. Restano Free e un solo abbonamento a pagamento, mostrato come "Pro" /
"abbonamento Pro" (ex Full). Nel codice resta `.full` (rawValue 2), i prodotti restano app.mygymhelper.full.monthly /
.yearly (9,99 €/mese, 99,99 €/anno, prova di 7 giorni), nel database resta 'full'. Tutte le funzioni dell'ex Mid sono
nel Pro; Free invariato. Licenze o acquisti "mid" già esistenti valgono come Pro.
- `Core/Sources/MyGymHelperCore/Tier.swift`: tolto `case mid`; nuovo `SubscriptionTier(storedLevel:)` (da 1 in su = Pro,
  negativo = nil) e decodifica Codable tollerante (un vecchio 1 in JSON diventa Pro); `FeatureGate`: tutto tranne
  conteggio, BMI e catalogo ridotto è `.full`.
- `App/SubscriptionManager.swift`: tolti i prodotti mid, `all` = solo full; letture salvate con `storedLevel`.
- `App/AccountService.swift`: tier "mid" dal server = Pro. `App/PaywallView.swift`: confronto a 2 colonne (Free, Pro).
- `App/InfoView.swift`: piano simulato (debug) -1 / Free / Pro. `App/AppSettings.swift`: un vecchio Mid simulato (1)
  diventa Pro.
- Commenti "Mid/Full" → "Pro" in App/ e Core/Sources (solo commenti).
- `Support/MyGymHelper.storekit`: tolti i prodotti mid, nomi "Pro mensile/annuale" ("Pro monthly/yearly").
- `App/Localizable.xcstrings`: `tier.full` = "Pro", tolta `tier.mid`, testi dei blocchi e del tutorial con
  "abbonamento Pro" (24 chiavi).
- Test Core: CoreTests (tutte le funzioni nel Pro, `testStoredLevelsOfTheOldPlansBecomePro`), FeatureTests,
  HomeEquipmentTests, PresetsTests.
- Documenti: `docs/STORE_TEXTS.md` (descrizione, prodotti, gruppo), `docs/TUTORIAL.md` (registro).
- **Non compilato e test non eseguiti** (modifica fatta senza Xcode).


## 4 novembre 2026 – Crea la tua scheda (iOS, piano Pro)
Stessa funzione già fatta e approvata su Android. In Schede pronte, sotto "Scegli la tua scheda di esercizi" e sopra la
scheda del mese, la card "Crea la tua scheda" apre un modulo (sesso, età 18-100, altezza 120-230 cm, peso 30-250 kg,
obiettivo con "Consigliato dal tuo BMI", esperienza, 3 o 4 allenamenti, Palestra / Casa con attrezzi / Corpo libero, nome).
Nel Free la card si vede con la nota `presets.locked`. Serve il consenso ai dati sulla salute. Fino a 20 schede ("Le tue
schede", dalla più recente); il dettaglio è quello delle schede pronte con note, Rinomina, Cambia i dati (rifà la scheda
con lo stesso id, nome e data) ed Elimina (gli elenchi già creati restano). Tutto sul telefono, nessuna API esterna.

Regole (Core `CustomPlanGenerator`, uguale a CustomPlans.kt):
- divisione: 4 allenamenti → parte alta / parte bassa A e B; 3 allenamenti principiante → total body A/B/C;
  3 allenamenti intermedio o avanzato → push / pull / legs;
- esercizi per allenamento: 5 principiante, 6 intermedio, 7 avanzato (dal muscolo più importante del giorno);
- per ogni muscolo un esercizio di forza con quel muscolo principale, fattibile nel luogo, adatto all'esperienza
  (principiante solo esercizi "beginner" o senza livello; intermedio niente "expert"), esclusi olympic e strongman;
  ordine: alla prima volta del muscolo i multiarticolari, per gli addominali prima gli esercizi a ripetizioni del plank,
  poi gli esercizi base (`seed-`), poi l'hash `MonthlyPlanner.stableHash(id + seed)`; ordinamento stabile; mai lo stesso
  esercizio due volte nella scheda (se non ce ne sono altri si ripete, ma mai nello stesso giorno);
- serie × ripetizioni e pausa: massa multiarticolari 3×10 90" / 4×8 120" / 4×6 150", complementari 3×12 60" / 3×10 75" /
  4×10 75"; mantenimento multiarticolari 3×10 90" (avanzato 4×8 90"), complementari 3×12 60"; dimagrimento multiarticolari
  3×12 60" (avanzato 4×12 60"), complementari 3×15 45"; addominali 3×15 45" (dimagrimento 3×20 30"); polpacci 4×15 60";
- dimagrimento: finale pliometrico 3×15 30" a ogni allenamento, tranne che a basso impatto;
- basso impatto (niente salti) con BMI ≥ 30 o età ≥ 65; dai 50 anni almeno 10 ripetizioni e +30" sui multiarticolari;
  dai 65 anni al massimo 3 serie;
- note: BMI, calorie indicative (`NutritionCalculator.targets`, attività leggera con 3 allenamenti, moderata con 4).

File:
- Core: `CustomPlans.swift` (nuovo: `Experience`, `TrainingPlace`, `HealthProfile` con i valori del profilo,
  `CustomPlanInput`, `CustomPlanRecord`, `CustomPlanNotes`, `CustomPlanGenerator`, `CustomPlanCodec` con lo stesso JSON di
  Android: "customPlans" → id, name, createdAt, input {…}, plan {level, daysPerWeek, days […]}); `Tier.swift`
  (`Feature.customPlans`, Pro); `Tutorial.swift` (versione 16). Test: `CustomPlansTests.swift` (stessi casi di Android).
- App: `CustomPlanViews.swift` (nuovo: sezione, note, pulsanti, modulo); `Persistence.swift` (`CustomPlanEntity` in
  SwiftData con il JSON di un record, `CustomPlanStore`); `ConsentStore.swift` ("Cancella dati sulla salute" cancella anche
  le schede create); `PresetsView.swift` (sezione in cima, dettaglio delle schede "custom:", elenchi "Nome scheda · Giorno");
  `PaywallView.swift` (riga `compare.customPlans`); `Localizable.xcstrings` (44 chiavi nuove e `tutorial.presets.body`).
  Il file nuovo dell'app entra da solo nel progetto (cartella App sincronizzata; project.yml usa `path: App`).
- **Non compilato e test non eseguiti** (modifiche fatte senza Xcode e senza Swift): l'equivalenza con il Kotlin è
  ragionata riga per riga, non verificata eseguendo i test.

## 4 novembre 2026 – Scheda Profilo e Impostazioni (iOS)
Stessa modifica già fatta su Android. Barra delle schede (Nutrizione spenta): Allenamento · Esercizi · **Profilo** ·
**Impostazioni** (ex Area personale, `InfoView`, icona `gearshape.fill`; foto profilo sempre nell'intestazione).
- Profilo (`App/ProfileView.swift`, nuovo): senza consenso solo il riquadro `profile.needConsent`; "I tuoi dati" con
  l'avatar (`AvatarView`), riepilogo, BMI, sesso, età, altezza e peso (salvati subito; il peso salva anche la pesata di
  oggi); "Muscoli allenati" con il periodo (Free: solo Giorno, nota `profile.period.locked`), figure fronte e retro
  (`MuscleHeatFigure` in `BodyMapView.swift`) ed elenco con le percentuali; "Andamento" (Pro): quattro totali e cinque
  grafici disegnati con Canvas (allenamenti, serie, volume, ripetizioni a colonne; peso corporeo a linea e punti), tocco
  su una colonna per il valore. Free: riquadro con `profile.charts.locked`.
- Core: `ProfileStats.swift` (nuovo, porta di ProfileStats.kt: `StatsPeriod`, `BucketKind`, `StatsBucket`, `MuscleShare`,
  `StatsTotals`, `WeightEntry`, `ProfileStats`, `WeightLog`, `AvatarFigure`; in più `StatsSession`/`StatsSet`, la sessione
  ridotta che su Android è WorkoutSessionRecord del Core). Tempi in millisecondi Int64, fuso come parametro, calendario
  gregoriano con la settimana da lunedì; confini dalle date (anche nei giorni del cambio d'ora). `Tier.swift`:
  `Feature.profileStats` (Pro). `Tutorial.swift`: `TutorialTab.profile`, target `tab.profile`, `profile.muscles`,
  `profile.charts`, tre passi prima di "infoTab", versione 17. Test: `ProfileStatsTests.swift` (stessi casi di Android
  tranne il codec di AppData: su iOS le pesate stanno in SwiftData) e `TutorialTests.swift` (27 passi, i tre del Profilo).
- Dati: `WeightEntryRecord` (SwiftData, migrazione leggera) e `ProfileData.setWeight` in `Persistence.swift` (aggiorna il
  profilo e applica `WeightLog.upsert`); "Cancella dati sulla salute", revoca ed "Elimina tutto" cancellano anche le
  pesate. "Crea la tua scheda" e il peso della Nutrizione salvano la pesata come su Android (l'importazione da Apple
  Salute nella Nutrizione no, come prima).
- Piani: riga `compare.profileStats`. Testi: 43 chiavi nuove e le frasi con "Area personale" → "Impostazioni" (anche
  `account.deleteMessage`, `lists.needConsent`, `debug.fakeHistory.noConsent`, `tutorial.welcome/suggest/infoTab`).
  Documenti legali: "Area personale" → "Impostazioni" in `App/Legal`, nella fonte `legal/` e in `site/` (stesse sostituzioni
  fatte a mano, `tools/build_legal.py` non rieseguito). `docs/TUTORIAL.md` alla versione 17.
- **Non compilato e test non eseguiti** (nessun Xcode/Swift qui): `swift test` da lanciare sul Mac. Controllata solo la
  sintassi dei file Swift e, con una copia in Python, la parte dell'avatar (tracciati dentro 240×520, "M120.0 90.0").

## 6 novembre 2026 – Calorie bruciate per esercizio e totale dell'allenamento (iOS)
Stessa funzione già fatta su Android, per tutti i piani (Free compreso).
- Calcolo (Core `Calories.swift`, nuovo, `CalorieEstimator` uguale a Calories.kt): kcal = MET × peso corporeo × ore;
  solo serie con almeno una ripetizione; tempo = durata di ogni serie fatta (tra 1,5 e 8 s a ripetizione, 3 s se 0) +
  (serie fatte − 1) × pausa; MET 6,0 multiarticolari, 3,5 gli altri e il conteggio libero. Peso: ultima pesata del
  Profilo, altrimenti il peso del profilo salute, altrimenti 70 kg (con `calories.defaultWeight`). Su iOS non c'è AppData:
  `bodyWeight(weights:profileWeightKg:)` e `ProfileData.bodyWeightKg()` nell'app. Valore mostrato: `.rounded()`, negativi a 0.
- Dati: `WorkoutItem.kcal` (default 0, decodifica tollerante per gli elenchi di prima). `WorkoutListStore.setDone(_:in:kcal:)`
  a fine sessione (rifacendo l'esercizio il valore si sostituisce); `reset` azzera fatto e calorie.
- Schermate: riga "≈ N kcal" sotto gli esercizi fatti dell'elenco (`WorkoutSetupView`); riga `calories.session` nel
  riepilogo (`SessionSummaryView`); nuovo `CaloriesTotalCard` (in fondo all'elenco dopo Reset, se almeno un esercizio è
  fatto; nel riepilogo quando tutti gli esercizi dell'elenco sono fatti, prima dei pulsanti).
- Stringhe `calories.*` (6), tutorial versione 18 (`tutorial.list.body`, `tutorial.session.body`).
- Test: `CaloriesTests.swift` (stessi casi di Android).
- **Non compilato e test non eseguiti** (nessun Xcode/Swift qui); valori attesi dei test ricontrollati a mano.

## 6 novembre 2026 – "Cerca" in Elenchi e zona Glutei (iOS)
Stessa modifica già fatta su Android.
- Core: `BodyRegion.glutes` (zona a sé dopo Gambe; `MuscleGroup.glutes.region` = `.glutes`; `isLowerBody` vero per gambe e
  glutei); `ListSearch.match` in `WorkoutLists.swift`. Test in `FeatureTests.swift` e `WorkoutListTests.swift`.
- App: simbolo `figure.step.training` per i glutei (`BodyMapView.swift`); schermata Elenchi (`ExerciseListsView` in
  `ExercisesView.swift`) con il campo "Cerca" (`ExerciseSearchField` con segnaposto `lists.search`): elenchi pronti e miei
  elenchi filtrati con i soli esercizi trovati, sezione "I miei elenchi" e "Nuovo elenco" nascosti durante la ricerca se
  non servono, `lists.none` se non c'è nulla. La zona Glutei compare da sola nei filtri per zona e negli elenchi pronti.
- Stringhe `region.glutes`, `lists.search`, `lists.none`; tutorial versione 19 (testi del passo "exercisesLinks").
- **Non compilato e test non eseguiti** (nessun Xcode/Swift qui).

## 6 novembre 2026 – Due testi esplicativi tolti (iOS)
Come su Android: tolta la nota sotto la spunta "Esercizio successivo" (`workout.autoNextNote`, `WorkoutSetupView.swift`)
e la regola sotto le percentuali dei muscoli nel Profilo (`profile.muscles.rule`, `ProfileView.swift`). La spunta, le
percentuali e la scritta del muscolo selezionato restano; le chiavi restano in `Localizable.xcstrings` (non usate).
Tutorial invariato. **Non compilato** (controllata solo la sintassi).
