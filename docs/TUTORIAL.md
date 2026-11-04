# Tutorial dell'app (MyGymHelper)

Tutorial guidato con **indicazioni in sovraimpressione**: l'app si oscura, la funzione del passo resta illuminata con
un bordo arancio pulsante e una mano che la indica, e un fumetto spiega cosa fa (Avanti / Indietro / Salta).
I passi senza una funzione da indicare (benvenuto, telefono sul corpo, sessione, fine) mostrano un disegno animato.

- **Primo avvio**: parte da solo dopo disclaimer e consenso, una volta sola (`tutorial.seenVersion` = 0).
  Completato o saltato, si salva `TutorialGuide.VERSION`. Dopo "Elimina tutti i dati" ricompare (come disclaimer e consenso).
- **Area personale**: riga "Tutorial dell'app" (in alto, sotto account, Piani e Aspetto) per rivederlo quando si vuole.
- Il tasto Indietro di Android torna al passo precedente (al primo passo chiude il tutorial).

## Dove sta il codice

| Cosa | Android | iOS |
| --- | --- | --- |
| Elenco dei passi (uguale sulle due piattaforme, con test) | `android/core/.../core/Tutorial.kt` + `TutorialTests.kt` | `Core/Sources/MyGymHelperCore/Tutorial.swift` + `TutorialTests.swift` |
| Sovraimpressione, fumetto, disegni | `android/app/.../ui/Tutorial.kt` (`TutorialOverlay`, `TutorialState`) | `App/TutorialOverlay.swift` (`TutorialOverlay`, `TutorialController`) |
| Segnare un elemento da illuminare | `Modifier.tutorialTarget(TutorialTarget.X)` | `.tutorialTarget(TutorialTarget.x)` (+ `.tutorialScrollFollow()` sulla ScrollView della schermata) |
| Avvio automatico | `AppRoot` in `ui/Navigation.kt` | `ContentView.swift` |
| Testi (it/en) | chiavi `tutorial.*` in `App/Localizable.xcstrings` → `python3 tools/xcstrings_to_android.py` | stesse chiavi |

Differenza voluta: sui passi delle schede Android illumina la voce nella barra in basso; su iOS (barra di sistema,
non misurabile) illumina il titolo della schermata della scheda. Se un elemento non è sullo schermo (es. profilo
Nutrizione senza consenso, o una scheda iOS lasciata in una sotto-schermata) il fumetto compare al centro, senza riquadro.

## Passi attuali (versione 16)

I passi 16 e 17 (Nutrizione) restano nell'elenco completo (`allSteps`) ma **non vengono mostrati** finché la scheda
Nutrizione è disattivata (`AppFeatures.NUTRITION_ENABLED` / `AppFeatures.nutritionEnabled` = false): l'utente vede 22 passi
(il passo 15, attrezzi in casa, si nasconde solo con `AppFlags.HOME_EQUIPMENT` / `AppFlags.homeEquipment` = false).

| # | id | Scheda | Elemento illuminato | Contenuto |
| --- | --- | --- | --- | --- |
| 1 | welcome | – | disegno | Benvenuto, si può saltare e rivedere dall'Area personale |
| 2 | strap | – | disegno | Telefono legato a braccio/avambraccio/coscia/stinco/addome; in tasca meno preciso |
| 3 | workoutTab | Allenamento | scheda | A cosa serve la scheda |
| 4 | list | Allenamento | elenco attuale | Esercizi con parametri, avvio/modifica/elimina, verde, Reset, "Esercizio successivo", più elenchi (Mid/Full) |
| 5 | addExercise | Allenamento | Aggiungi esercizio | Schermata di scelta: mappa, zone, tipo, ricerca; aggiunta con i parametri |
| 6 | variedSets | Allenamento | elenco attuale | Serie diverse (Mid/Full): dalla matita righe con numero di serie, ripetizioni e peso (serie uguali in una riga sola); in allenamento si vedono e si sentono quelli della serie successiva; nelle schede caricate le righe con lo stesso esercizio nello stesso giorno diventano un esercizio solo |
| 7 | presets | Allenamento | Schede pronte | "Scegli la tua scheda di esercizi"; in cima "Crea la tua scheda" (Pro: scheda su misura da altezza, peso, sesso, età, obiettivo, esperienza, allenamenti e luogo; più schede, rinomina e rifai); difficoltà in pastiglia colorata (verde, arancione, rosso per Esperto); base total body (tutti), altre schede e consigliata del mese (Pro) |
| 8 | session | – | disegno | Pronto (posizione, Avvia), spiegazione saltabile, conteggio, pausa, "Mi sono fermato", "Ripetizioni completate", riepilogo |
| 9 | alternative | – | disegno | "Fai esercizio alternativo" nella schermata Pronto: elenco esercizi con i filtri, già sugli stessi muscoli; l'alternativa vale solo per questa sessione (l'esercizio diventa verde) oppure, con "Sostituisci nell'elenco", diventa definitiva |
| 10 | free | Allenamento | Conteggio libero | Contare senza esercizio |
| 11 | history | Allenamento | Storico | Solo sul telefono, solo con consenso |
| 12 | planReview | Allenamento | Storico | Full: ogni due settimane, a fine allenamento, domanda "troppo leggero / giusto / troppo pesante"; controllo delle ripetizioni dello Storico, nuovi carichi in "Consiglio per oggi", Applica aggiorna scheda ed elenchi, si può tornare alla scheda precedente |
| 13 | exercisesTab | Esercizi | scheda | Catalogo (quasi 900 esercizi), "Cerca esercizio" come primo filtro, filtro per tipo e "Corpo libero", foto, spiegazioni, consigli (Mid/Full) |
| 14 | exercisesLinks | Esercizi | Elenchi / Schede | Elenchi pronti e salvati; scheda (Full) inserita a mano (`bodyManual`: caricamento da file e foto disattivato per ora). Con il caricamento attivo: import da foto con l'AI, dati mancanti da completare o confermare |
| 15 | homeEquipment | Esercizi | riquadro Attrezzi in casa | (nascosto, funzione spenta) Full: segnare gli attrezzi di casa (vedere, aggiungere, togliere) e filtro "Solo i miei attrezzi" in Esercizi e Aggiungi esercizio; corpo libero sempre visibile |
| 16 | nutritionTab | Nutrizione | scheda | (nascosto, Nutrizione disattivata) Indicazioni generali, non sostituisce il nutrizionista |
| 17 | nutritionProfile | Nutrizione | profilo | (nascosto, Nutrizione disattivata) Dati, BMI, fabbisogno; Full: pasti e scheda del nutrizionista; serve consenso |
| 18 | infoTab | Area personale | scheda | Foto profilo (tocco sul cerchio), account, piani e abbonamenti, consenso, Salute/Health Connect, voce, calibrazione, documenti, cancellazione |
| 19 | plans | Area personale | voce Piani e abbonamenti | Free/Mid/Full, ripristino, 7 giorni di prova, scadenza della licenza gratuita |
| 20 | appearance | Area personale | scheda Aspetto | Tema: neutro del telefono (predefinito), scuro oppure originale arancio e viola |
| 21 | replay | Area personale | riga Tutorial | Come rivederlo |
| 22 | cues | Area personale | voce Voce e musica | Avvisi (voce, suono, vibrazione) con prova; voce, velocità e musica (prima nella scheda Allenamento) |
| 23 | suggest | Area personale | voce Suggerisci una funzione (ultima) | Idee o cosa manca: si apre l'app di posta con l'e-mail per mygymhelper@gmail.com |
| 24 | done | – | disegno | Fine, promemoria del disclaimer |

## REGOLA: aggiornare il tutorial a ogni modifica dell'app

A ogni modifica o aggiunta di una funzione (Android e iOS), nella stessa consegna:

1. Valutare se cambia cosa vede o fa l'utente. Se sì, aggiornare il testo del passo interessato o aggiungere un passo.
2. Passo nuovo: aggiungerlo **nello stesso punto** in `Tutorial.kt` e `Tutorial.swift`; se indica un elemento, creare
   la costante in `TutorialTarget` (stesso valore sulle due piattaforme) e applicare `tutorialTarget(...)` all'elemento
   in entrambe le app (su iOS, se la schermata scorre, anche `.tutorialScrollFollow()` sulla ScrollView).
3. Testi `tutorial.<id>.title` / `tutorial.<id>.body` in italiano e inglese in `App/Localizable.xcstrings`, poi
   `python3 tools/xcstrings_to_android.py` (gli strings.xml non si toccano a mano).
4. Aggiornare i test (numero di passi) in `TutorialTests.kt` e `TutorialTests.swift` e la tabella qui sopra.
5. Aumentare `TutorialGuide.VERSION` / `TutorialGuide.version`. Oggi serve solo come registro: il tutorial riparte da
   solo **solo** al primo avvio (se si volesse riproporlo dopo un aggiornamento importante, è una scelta di prodotto
   da confermare con l'utente: basterebbe cambiare `shouldAutoStart`).

## Aggiornamenti
- 26 ottobre 2026: passo "Elenco" (`tutorial.list.body`) con i passi del peso (0,5 kg fino a 4, 1 kg fino a 10, poi 5 kg);
  poi aggiunto che il peso si può anche scrivere a mano;
  27 ottobre: passo "Il tuo profilo" (`tutorial.nutritionProfile.body`) con le calorie per i tre obiettivi e quello consigliato;
  27 ottobre: passo "Esercizi" (`tutorial.exercisesTab.body`): la scheda dell'esercizio mostra i muscoli coinvolti sul corpo;
  poi passo "Elenco": le righe mostrano i muscoli coinvolti in miniatura;
  27 ottobre: passo "Avvisi" (`tutorial.cues.body`): accesso a Spotify e scelta/ricerca della playlist in Voce e musica;
  solo Android: al passo di benvenuto si aggiunge `android.tutorial.systemBack` (tolto il pulsante Indietro dell'app).
- 28 ottobre 2026: passo "Esercizi" (`tutorial.exercisesTab.body`): catalogo di quasi 900 esercizi, filtro per tipo
  (forza, pliometria, stretching, cardio) e foto dell'esercizio. Stesso testo su Android e iOS.
- 28 ottobre 2026 (versione 2): tolti i passi "picker" e "search" (la scelta degli esercizi è ora in una schermata a
  parte); nuovi passi "addExercise" (pulsante Aggiungi esercizio, `workout.add`) e "presets" (Schede pronte,
  `workout.presets`). `TutorialGuide.VERSION`/`version` = 2 su Android e iOS.
- 28 ottobre 2026: passo "Elenchi e schede" (`tutorial.exercisesLinks.body`): le schede caricate si leggono con l'AI del
  telefono se c'è (Apple Intelligence o Gemini Nano), senza far uscire il testo. Stesso testo su Android e iOS.
- 28 ottobre 2026: passo "Avvisi" (`tutorial.cues.body`): tolta la parte su Spotify (integrazione spenta per ora,
  `AppFlags`). Stesso testo su Android e iOS.
- 30 ottobre 2026 (versione 3): nuovo passo "appearance" (scheda Aspetto nell'Area personale, `info.appearance`) per la
  scelta del tema grafico. Testi `tutorial.appearance.*`. Il fumetto e il velo del tutorial seguono il tema (fumetto
  chiaro sul tema neutro con il telefono in modalità chiara). `TutorialGuide.VERSION`/`version` = 3 su Android e iOS.
- 30 ottobre 2026: passo "Area personale" (`tutorial.infoTab.body`): si dice che toccando il cerchio in alto si mette la
  foto profilo (solo sul telefono). Stesso testo su Android e iOS; nessun passo nuovo, versione invariata (3).
- 30 ottobre 2026 (versione 4): scheda Nutrizione disattivata (sarà una nuova opzione più avanti). I passi
  "nutritionTab" e "nutritionProfile" restano in `allSteps` ma `steps` li salta (filtro su `visibleTabs`); testi
  `tutorial.nutrition*` lasciati nelle stringhe. Test: 19 passi in tutto, 17 mostrati. `TutorialGuide.VERSION`/`version` = 4
  su Android e iOS. Per riattivare: `AppFeatures` = true, i passi tornano da soli.
- 30 ottobre 2026: passo "Elenchi e schede" (`tutorial.exercisesLinks.body`): l'AI del telefono riconosce esercizi,
  serie, ripetizioni e pesi; i dati che non trova sono in arancione e si completano o si conferma l'importazione.
  Stesso testo su Android e iOS; nessun passo nuovo, versione invariata (4).
- 31 ottobre 2026 (versione 5): i Piani non sono più una scheda della barra ma una voce dell'Area personale
  ("Piani e abbonamenti", `info.plans`, con il piano attuale; sempre la seconda voce: dopo l'account se c'è, altrimenti
  dopo "Aspetto"). Il passo "plansTab" diventa "plans": si apre l'Area
  personale e si illumina la voce; ora viene subito dopo "infoTab". Tolti `TutorialTab.PLANS`/`.plans` e
  `TutorialTarget.TAB_PLANS`/`tabPlans`; testi `tutorial.plansTab.*` sostituiti da `tutorial.plans.*`, aggiornato
  `tutorial.infoTab.body`. Sempre 19 passi in tutto, 17 mostrati. `TutorialGuide.VERSION`/`version` = 5 su Android e iOS.
- 31 ottobre 2026 (versione 6): nuovo passo "suggest" (`info.suggest`, voce "Suggerisci una funzione", l'ultima
  dell'Area personale), tra "replay" e "done". Testi `tutorial.suggest.*`. 20 passi in tutto, 18 mostrati.
  `TutorialGuide.VERSION`/`version` = 6 su Android e iOS.
- 31 ottobre 2026 (versione 7): serie diverse sullo stesso esercizio (ripetizioni e peso di ogni serie, piani Mid e Full).
  Nuovo passo "variedSets" subito dopo "addExercise", sull'elenco attuale (`workout.list`: le serie si impostano dalla
  matita di un esercizio). Testi `tutorial.variedSets.*`; il passo "Elenco" (`tutorial.list.body`) dice che con le serie
  diverse si vedono ripetizioni e peso di ogni serie. Test: 21 passi in tutto, 19 mostrati.
  `TutorialGuide.VERSION`/`version` = 7 su Android e iOS.
- 2 novembre 2026: passo "Serie diverse" (`tutorial.variedSets.body`): ogni riga ha anche il numero di serie, così le
  serie uguali si scrivono una volta sola. Stesso testo su Android e iOS; nessun passo nuovo, versione invariata (7).
- 2 novembre 2026 (versione 8): attrezzi in casa (solo piano Full). Nuovo passo "homeEquipment" subito dopo
  "exercisesLinks", sul riquadro "Attrezzi in casa" della scheda Esercizi (`exercises.equipment`). Testi
  `tutorial.homeEquipment.*`. Stessi passi su Android e iOS.
- 2 novembre 2026: versione 9, passo "planReview" (revisione della scheda ogni due settimane, piano Full) dopo "history".
- 2 novembre 2026: passo "session" (`tutorial.session.body`) con il pulsante "Ripetizioni completate".
- 2 novembre 2026 (versione 10): attrezzi in casa nascosti per ora (`AppFlags.HOME_EQUIPMENT` = false): il passo
  "homeEquipment" non si mostra. Nuovo filtro "Corpo libero" citato nei passi "exercisesTab" e "addExercise"
  (`tutorial.exercisesTab.body`, `tutorial.addExercise.body`). Stessi passi su Android e iOS.
- 2 novembre 2026 (versione 11): "Fai esercizio alternativo". Nuovo passo "alternative" subito dopo "session", con il
  disegno della sessione (testi `tutorial.alternative.*`). Test: 24 passi in tutto, 21 mostrati. Stessi passi su Android e iOS.
- 2 novembre 2026 (versione 12): Schede pronte con la difficoltà evidenziata. Aggiornato solo il testo del passo "presets"
  (`tutorial.presets.body`): cita "scegli la tua scheda di esercizi" e la pastiglia colorata della difficoltà. Stessi passi su Android e iOS.
- 2 novembre 2026: passo "alternative" (`tutorial.alternative.body`) con "Sostituisci nell'elenco" (alternativa definitiva).
  Stesso testo su Android e iOS; nessun passo nuovo, versione invariata (11).
- 3 novembre 2026: passo "Elenchi e schede" (`tutorial.exercisesLinks.body`): la scheda si carica "da una foto" (prima
  "da foto, PDF, Word o Excel"), perché l'importazione da file è disattivata (`AppFeatures`). Stesso testo su Android e
  iOS; nessun passo nuovo, versione invariata. Quando si riattivano i file, rimettere "da foto, PDF, Word o Excel"
  (in inglese "from a photo, PDF, Word or Excel").
- 3 novembre 2026 (versione 13): avviso a voce nella pausa prima dell'ultima serie. Aggiornato il testo del passo
  "session" (`tutorial.session.body`): la voce avvisa dell'ultima serie e presenta il prossimo esercizio (nome, muscoli,
  attrezzo, dove mettere il telefono). Nessun passo nuovo; stessi testi su Android e iOS.
- 3 novembre 2026 (versione 14): attrezzi in casa di nuovo visibili (`AppFlags.HOME_EQUIPMENT` = true): torna il passo
  "homeEquipment" dopo "exercisesLinks". Stessi passi su Android e iOS.
- 3 novembre 2026: caricamento schede spento anche da foto: il passo "Elenchi e schede" usa `tutorial.exercisesLinks.bodyManual`
  (scheda inserita a mano) finché `AppFeatures.planImportEnabled` è falso; `tutorial.exercisesLinks.body` resta per la riattivazione.
  Stessi passi su Android e iOS, versione del tutorial invariata.
- 3 novembre 2026: licenze gratuite manuali. Aggiornato il testo del passo "plans" (`tutorial.plans.body`): se c'è una
  licenza gratuita, nei Piani si vede fino a quando vale. Stesso testo su Android e iOS; nessun passo nuovo, versione invariata.
- 4 novembre 2026: "Cerca esercizio" diventa il primo filtro, dentro il riquadro dei filtri (Esercizi, Aggiungi esercizio
  ed Esercizio alternativo), con la X per svuotarlo. Aggiornato il testo del passo "exercisesTab"
  (`tutorial.exercisesTab.body`); nessun passo nuovo. Stessi testi su Android e iOS.
- 4 novembre 2026 (versione 15): gli avvisi (voce, suono, vibrazione e prova) passano dalla scheda Allenamento all'Area
  personale > Voce e musica (prima card). Il passo "cues" ora è nell'Area personale, subito dopo "replay"
  (`TutorialTarget.infoAudio` = "info.audio", tolto `workoutCues`); nuovi testi `tutorial.cues.title`/`.body`.
  24 passi in tutto, come prima. Stessi passi su Android e iOS.
- 4 novembre 2026: tolto il piano Mid, il Full si chiama Pro; aggiornati i testi dei passi che citavano Mid o Full;
  versione del tutorial invariata.
- 4 novembre 2026 (versione 16): "Crea la tua scheda" (scheda su misura da altezza, peso, sesso e obiettivo, piano Pro)
  in cima alle Schede pronte. Aggiornato il testo del passo "presets" (`tutorial.presets.body`); nessun passo nuovo.
  Stessi testi su Android e iOS.
