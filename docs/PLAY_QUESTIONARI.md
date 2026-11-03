# Risposte ai questionari di Play Console (bozza da verificare, 3 novembre 2026)

Dove: Play Console > MyGymHelper > Monitora e migliora (o "Norme") > **Contenuti dell'app**.
Le risposte descrivono la versione Android attuale: accesso solo con Google, nutrizione, importazione delle schede,
Spotify e catalogo MuscleWiki spenti; nessuna pubblicità, statistica o crash report di terze parti.
Da far rivedere all'avvocato insieme all'informativa: le due cose devono dire lo stesso.

## 1. Norme sulla privacy
URL: `https://mygymhelper-site.github.io/privacy.html`

## 2. Accesso alle app (App access)
"Tutte o alcune funzionalità sono soggette a restrizioni". Istruzioni per i revisori di Google:
- Le funzioni Free si usano senza account.
- Per provare Mid e Full: crea un account Google di prova (es. `mygymhelper.review@gmail.com`, senza verifica in due
  passaggi), accedi una volta dall'app, poi assegnagli una licenza Full gratuita in Supabase:
  `select * from licensing.grant_free_license('mygymhelper.review@gmail.com', '2027-12-31', 'full', 'revisione Google');`
- Testo da inserire: "Core features work without an account. To review Mid/Full features, sign in with Google using
  the account below in My area > Account: it has a free Full licence." + e-mail e password dell'account di prova.

## 3. Annunci
"No, la mia app non contiene annunci".

## 4. Classificazione dei contenuti (questionario IARC)
- E-mail: mygymhelper@gmail.com. Categoria: **Tutti gli altri tipi di app** (non gioco, non social, non notizie).
- Violenza, paura, sesso, linguaggio volgare, droghe, gioco d'azzardo: **No** a tutto.
- Gli utenti possono interagire o scambiarsi contenuti tra loro? **No**.
- L'app condivide la posizione dell'utente con altri utenti? **No**.
- Acquisti digitali: **Sì** (abbonamenti).
- Navigazione web senza limiti? **No**.
Risultato atteso: classificazione minima (PEGI 3 / Everyone).

## 5. Pubblico di destinazione e contenuti
- Fasce d'età: **solo 18 anni e oltre**.
- L'app potrebbe attirare involontariamente i bambini? **No** (allenamento con i pesi, nessun personaggio o gioco).

## 6. Sicurezza dei dati (Data safety)
**Raccolta e condivisione**
- L'app raccoglie o condivide dati utente dei tipi richiesti? **Sì**.
- Tutti i dati raccolti sono criptati in transito? **Sì** (HTTPS verso Supabase e Google).
- Gli utenti possono chiedere l'eliminazione dei dati? **Sì**: in app (Area personale > Account) e via web
  `https://mygymhelper-site.github.io/delete-account.html`.
- Creazione dell'account: **Sì, con OAuth (Accedi con Google)**. Link per l'eliminazione: quello sopra.
- Revisione di sicurezza indipendente: **No**.

**Tipi di dati dichiarati** (tutti: raccolti, **non condivisi**, **facoltativi** perché l'account è facoltativo,
trattati non in modo temporaneo)

| Categoria > tipo | Raccolto | Condiviso | Facoltativo | Finalità |
| --- | --- | --- | --- | --- |
| Informazioni personali > Indirizzo email | Sì | No | Sì | Funzionalità app, Gestione account |
| Informazioni personali > Nome (nome visualizzato di Google) | Sì | No | Sì | Gestione account |
| Informazioni personali > ID utente | Sì | No | Sì | Funzionalità app, Gestione account |
| Informazioni finanziarie > Cronologia acquisti (stato dell'abbonamento collegato all'account) | Sì | No | Sì | Funzionalità app, Gestione account |

**Tipi NON dichiarati e perché**
- Salute e fitness (peso, altezza, allenamenti, ripetizioni, dati Health Connect): trattati **solo sul telefono**,
  non lasciano mai il dispositivo. Per Google i dati trattati solo sul dispositivo non sono "raccolti".
- Dati di pagamento: li gestisce Google Play, l'app non li riceve.
- Attività nell'app, diagnostica, identificatori del dispositivo, posizione, foto e video, contatti: non raccolti.
  (Foto del profilo, se presente: resta sul telefono.)
- Supabase è un fornitore di servizi che tratta i dati per conto nostro: per Google questo **non è condivisione**.

## 7. Autorizzazioni Health Connect
Contenuti dell'app > **Health Connect**. Permessi e motivazioni:
- `READ_WEIGHT`, `READ_HEIGHT`: "Imports the user's weight and height into their local profile, only when the user taps
  Import, to calculate BMI and suggest training loads. Data stays on the device."
- `WRITE_EXERCISE`: "Saves completed strength workouts (exercise, duration) to Health Connect so the user can see them
  with their other fitness data."
- Categoria d'uso: **Fitness / allenamento**. Dati non usati per pubblicità, non venduti, non trasferiti a terzi.
- Serve l'informativa pubblicata con la sezione su Health Connect (c'è, sezione 11).

## 8. App di salute (Health apps declaration)
- Funzioni: **Attività fisica e fitness** (activity and fitness tracking, coaching sull'allenamento).
- Non è un dispositivo medico, non fa diagnosi né trattamenti, nessuna funzione per ricerca sanitaria o servizi sanitari.
- Disclaimer nella descrizione e al primo avvio (c'è).

## 9. Altre dichiarazioni
- App governativa: **No**. Funzioni finanziarie: **No**. App di notizie: **No**.
- Funzionalità COVID-19: **No**.
- Intelligenza artificiale generativa: **Sì**. La revisione della scheda ogni due settimane (piano Full) usa, dove il
  telefono lo supporta, il modello sul dispositivo di Google (ML Kit GenAI / Gemini Nano) per proporre le modifiche;
  i dati non lasciano il telefono e l'utente decide se applicarle. Per le norme di Google Play sui contenuti generati
  dall'IA, sotto ogni testo dell'IA c'è "Segnala il testo dell'IA", che apre un'e-mail a mygymhelper@gmail.com già
  compilata (fatto il 3 novembre 2026). Da verificare con l'avvocato (AI Act, obblighi di trasparenza).
- Autorizzazioni sensibili: nessuna (niente posizione, SMS, chiamate, servizi in primo piano, accessibilità).

## 10. Paesi e prezzi
- Paesi: inizia con quelli in cui i testi sono adatti (Italia + Paesi di lingua inglese o tutta l'UE), da decidere
  dopo il parere di avvocato e commercialista.
- Prezzi degli abbonamenti: impostati in euro; Google converte automaticamente nelle altre valute (controllare i
  valori proposti prima di salvare).
