# Adempimenti da verificare prima della pubblicazione (non fanno parte dell'app)

Note per lo sviluppatore ricavate dal testo fornito. Non sono una consulenza legale: fai verificare la versione definitiva
da un legale esperto di privacy e tecnologia e il flusso reale dei dati da uno sviluppatore.

## Segnaposto da compilare nei testi (App/Legal/*.md)
- `[data]` (ultimo aggiornamento), titolare del trattamento, contatto privacy (e-mail).
- `[nome dell'app]` viene sostituito in automatico con il nome dell'app (CFBundleDisplayName).
- Sezione 10 dell'informativa: bozza aggiunta da noi su account, acquisti ed elenco esercizi, da far verificare.
- Versioni in inglese e nelle altre lingue: oggi esiste solo l'italiano (l'app lo mostra a tutti, con un avviso).

## A. GDPR e dati sanitari
Verifica quali dati vengono effettivamente trattati, chi determina finalità e mezzi del trattamento, quale base giuridica
si applica e se serve il consenso esplicito (art. 9 GDPR). Definisci misure di sicurezza e tempi di conservazione.
Il consenso non deve essere preselezionato, deve essere libero, specifico, informato, esplicito e revocabile con facilità;
le funzioni che non dipendono dai dati sanitari vanno mantenute quando possibile (l'app lo fa).

## B. Verifica tecnica della modalità offline
- Il modello AI è davvero locale e i prompt non escono dal telefono.
- Nessuna telemetria, SDK pubblicitario, log o crash report che trasferisca dati sanitari.
- I dati sanitari non finiscono nei backup cloud del sistema (iCloud): valuta di escludere i file dai backup.
- L'app non contiene altre funzioni che inviano dati a server esterni.
- La cancellazione dei dati locali funziona davvero (oggi cancella solo le impostazioni salvate; i dati su SwiftData
  andranno aggiunti quando esisteranno).

## C. Regolamento europeo sull'intelligenza artificiale (AI Act)
Il testo fornito indica che dal 2 agosto 2026 si applicano diverse disposizioni, comprese quelle sulla trasparenza.
Verifica le date e gli obblighi attuali (potrebbero essere cambiati) e informa l'utente quando interagisce con un sistema
di IA, se previsto. Valuta anche l'alfabetizzazione sull'IA e l'eventuale classificazione del sistema.

## D. Possibile dispositivo medico
Un'app di benessere e fitness è diversa da un software con finalità mediche. Se promette di diagnosticare, prevenire,
monitorare o trattare patologie, o di supportare decisioni cliniche, può ricadere nel regolamento europeo sui dispositivi
medici. Conta la destinazione d'uso effettiva, non il disclaimer. Evita nell'app e nello store formulazioni mediche.

## E. Documentazione e store
- Account: l'app permette di creare un account, quindi deve permettere di eliminarlo (fatto: Info > Account).
  Per "Accedi con Apple" i token Apple vengono revocati alla cancellazione (servono i segreti in docs/BACKEND.md).
- Testi legali in inglese (`App/Legal/*.en.md`): traduzione della bozza italiana, da far verificare per i Paesi in cui vendi.
- Apple Salute: i dati non possono essere usati per pubblicità né venduti (linee guida Apple 5.1.3); l'app non lo fa.
- Ricerca alimenti (Open Food Facts): l'app invia a un server esterno solo le parole cercate (nessun dato sanitario).
  Va citato nell'informativa insieme all'attribuzione ODbL; verificare i termini d'uso dell'API e lo User-Agent.
- Importazione schede: PDF, Excel, Word, CSV e foto vengono letti sul telefono (PDFKit e Vision su iOS, PdfRenderer e ML Kit su Android, Excel e Word dal Core), nulla viene inviato a server.
- Informativa privacy pubblicata su una pagina web (richiesta dagli store) e raggiungibile dall'app.
- Dati del titolare, modalità di cancellazione, dichiarazioni privacy richieste da Apple e Google, condizioni d'uso.
- Il disclaimer va anche nella descrizione dell'app.
- Se l'app ha account, pagamenti o servizi esterni, descrivi separatamente i dati relativi a queste funzioni.

## Controlli da fare prima di dire "i dati medici restano solo sul telefono"
1. Il modello AI non richiede connessione remota.
2. I dati non sono nei backup cloud del sistema.
3. Non passano da crash reporting, analytics o diagnostica.
4. Nessuna altra funzione invia dati a server esterni.
5. La cancellazione dei dati locali funziona davvero.
