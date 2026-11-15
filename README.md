# Lieve

Browser iOS leggero basato su WKWebView, pensato per YouTube: blocco pubblicità, audio a schermo spento, Picture-in-Picture e AirPlay. Swift + SwiftUI, nessuna dipendenza, nessuna telemetria, nessun backend obbligatorio.

Tecniche, architettura e limiti: [`docs/ANALISI.md`](docs/ANALISI.md).

## Struttura

```
project.yml                     definizione progetto (XcodeGen genera il .xcodeproj in CI)
Lieve/App                       avvio, preferenze
Lieve/Browser                   WKWebView, stato della scheda, delegate
Lieve/Filters                   caricamento, verifica e aggiornamento del pacchetto filtri
Lieve/Media                     sessione audio, ponte media (background, PiP, stato)
Lieve/UI                        vista principale, menu flottante, indirizzi, impostazioni, AirPlay
Lieve/Resources                 icona, pacchetto filtri incluso, manifest privacy
filters/                        regole e script di blocco (aggiornabili senza reinstallare l'app)
ci/prepare.sh                   test + pacchetto filtri + progetto Xcode
.github/workflows/ios.yml       build dell'app
.github/workflows/filters.yml   pubblicazione quotidiana dei filtri firmati
```

## Uso

- **Pulsante flottante**: toccalo per aprire i comandi (indietro, avanti, ricarica, indirizzo, PiP, AirPlay, impostazioni). Trascinalo su un lato.
- **AirPlay in un tocco**: mentre un video è in riproduzione compare un pulsante AirPlay sopra quello flottante.
- **PiP**: pulsante PiP nel menu, oppure schermo intero e poi torna alla Home.
- **Impostazioni**: blocco pubblicità, background, PiP automatico (sperimentale), versione e aggiornamento dei filtri.

## Compilare senza Mac

1. Crea un repository su GitHub e carica questi file (anche dal browser: *Add file → Upload files*).
2. In **Settings → Secrets and variables → Actions → Variables** crea `BUNDLE_ID`, ad esempio `com.tuonome.lieve` (deve essere unico).
3. Ogni push su `main` avvia il job **unsigned**: dopo circa 5 minuti, in **Actions → esecuzione → Artifacts** trovi `Lieve-unsigned.ipa`.

Ogni build esegue anche i test dei filtri, scarica EasyList ed EasyPrivacy e verifica tutte le regole con il compilatore WebKit reale: se una regola viene rifiutata, è scartata in automatico.

I repository pubblici usano i runner macOS gratis. Nei repository privati i minuti macOS consumano la quota molto più in fretta di quelli Linux: controlla il tuo piano.

## Filtri aggiornabili (consigliato)

Senza questa configurazione l'app usa i filtri inclusi al momento della build. Con questa configurazione riceve correzioni entro un giorno, senza reinstallarla.

1. **Il repository deve essere pubblico**, perché l'app scarica il pacchetto da una release GitHub senza autenticazione. Il pacchetto contiene solo regole e script, nessun dato personale.
2. **Crea la chiave di firma** in Git Bash (incluso in Git for Windows):
   ```bash
   openssl genpkey -algorithm ed25519 -out filters-signing.pem
   cat filters-signing.pem
   ```
3. **Copia tutto il contenuto** (righe `BEGIN`/`END` comprese) nel secret `FILTERS_SIGNING_KEY` (Settings → Secrets and variables → Actions). Poi conserva il file al sicuro, fuori dal repository.
4. **Avvia la pubblicazione**: Actions → **Filtri** → *Run workflow*. Viene creata la release `filters`.
5. **Ricompila l'app** (push o *Run workflow* su **iOS**) e reinstallala una volta. La build ricava la chiave pubblica dal secret e la include nell'app.

Da quel momento:
- il workflow **Filtri** gira ogni notte e pubblica solo se EasyList o i tuoi file sono cambiati;
- se YouTube cambia qualcosa, modifichi `filters/scripts/` o `filters/rules/` e fai push: l'app si aggiorna al successivo controllo, oppure subito con Impostazioni → Controlla aggiornamenti;
- un pacchetto senza firma valida viene sempre scartato dall'app.

GitHub sospende i workflow pianificati dopo 60 giorni senza attività nel repository: basta un commit o un avvio manuale per riattivarli.

## Modificare i filtri

| Cosa | File |
|---|---|
| Domini o percorsi da bloccare su YouTube | `filters/rules/youtube.json` (formato WebKit) |
| Elementi da nascondere | stessa lista, regola `css-display-none` |
| Logica anti-pubblicità e background | `filters/scripts/youtube-page.js` |
| Rete di sicurezza per gli spot, "continuare a guardare?" | `filters/scripts/youtube-isolated.js` |
| Liste esterne (EasyList, ecc.) | `filters/pack.json` → `remoteLists` |

Prima del push puoi provare in locale con Python 3 e Node:
```bash
python3 -m unittest discover -s filters/tests
python3 filters/tools/build_pack.py build --offline --out dist/pack.lvp
node filters/tests/scripts.test.mjs dist/pack.lvp
```

## Installare sull'iPhone

iOS installa solo app firmate da un certificato Apple. Ci sono tre strade.

### A. Gratis: Apple ID personale + Sideloadly (per i primi test)

Su Windows:
1. Installa **iTunes** e **iCloud** dal sito Apple (le versioni da sito, non quelle del Microsoft Store).
2. Installa **Sideloadly** (sideloadly.io), collega l'iPhone via USB e autorizza il computer.
3. Trascina `Lieve-unsigned.ipa` in Sideloadly, inserisci il tuo Apple ID e avvia. Sideloadly firma l'app con un certificato di sviluppo gratuito.

Sull'iPhone:
4. **Impostazioni → Privacy e sicurezza → Modalità sviluppatore** → attiva e riavvia.
5. **Impostazioni → Generali → VPN e gestione dispositivi** → autorizza il tuo Apple ID.

Limiti dell'account gratuito: l'app **scade dopo 7 giorni** (va reinstallata), massimo 3 app installate così, nuovi App ID limitati a 10 ogni 7 giorni. Audio in background, PiP e AirPlay funzionano: non servono entitlement speciali.

### B. Consigliata: Apple Developer Program (99 €/anno) + TestFlight

Nessuna scadenza settimanale (le build TestFlight durano 90 giorni) e installazione via rete, senza cavo.

Una tantum, tutto da browser e da Windows:

1. **Iscriviti** su developer.apple.com/programs. Annota il **Team ID** (Membership).
2. **Crea l'App ID**: Certificates, IDs & Profiles → Identifiers → + → App IDs → Explicit, stesso valore di `BUNDLE_ID`.
3. **Crea il certificato di distribuzione**. In PowerShell (OpenSSL è incluso in Git for Windows):
   ```powershell
   openssl genrsa -out lieve.key 2048
   openssl req -new -key lieve.key -out lieve.csr -subj "/emailAddress=TUA_EMAIL/CN=Tuo Nome/C=IT"
   ```
   Carica `lieve.csr` in Certificates → + → **Apple Distribution**, scarica `distribution.cer`, poi:
   ```powershell
   openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM
   openssl pkcs12 -export -inkey lieve.key -in distribution.pem -out distribution.p12 `
     -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
   ```
   (Gli algoritmi "legacy" servono perché il portachiavi macOS non sempre accetta i .p12 creati con le impostazioni predefinite di OpenSSL 3.) Conserva `lieve.key` in un posto sicuro.
4. **Crea il profilo**: Profiles → + → **App Store Connect** → scegli App ID e certificato → scarica il `.mobileprovision`.
5. **Crea la chiave API**: App Store Connect → Utenti e accessi → Integrazioni → App Store Connect API → nuova chiave con ruolo **App Manager**. Annota Key ID e Issuer ID, scarica il `.p8` (si scarica una sola volta).
6. **Crea l'app**: App Store Connect → App → + → Nuova app, con lo stesso bundle ID. Non serve pubblicarla.
7. **Converti i file in Base64** in PowerShell:
   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("distribution.p12")) | Set-Clipboard
   ```
   Ripeti per `.mobileprovision` e `.p8`.
8. **Aggiungi i Secrets su GitHub** (Settings → Secrets and variables → Actions → Secrets):

   | Secret | Contenuto |
   |---|---|
   | `APPLE_TEAM_ID` | Team ID |
   | `DIST_CERT_P12_BASE64` | `distribution.p12` in Base64 |
   | `DIST_CERT_PASSWORD` | password scelta all'export del .p12 |
   | `APPSTORE_PROFILE_BASE64` | `.mobileprovision` in Base64 |
   | `ASC_KEY_ID` | Key ID della chiave API |
   | `ASC_ISSUER_ID` | Issuer ID |
   | `ASC_KEY_P8_BASE64` | `.p8` in Base64 |

Ogni volta che vuoi una build:
- Actions → **iOS** → *Run workflow* → spunta **testflight**.
- Dopo l'elaborazione (5–30 minuti) la build compare in App Store Connect → TestFlight. Aggiungiti come **tester interno**: per i tester interni non c'è revisione Apple.
- Sull'iPhone installa l'app **TestFlight** e installa Lieve da lì.

### C. Alternativa con account a pagamento: Sideloadly

Come la strada A, ma con l'Apple ID del Developer Program: la firma dura un anno invece di 7 giorni. Non servono certificati in CI.

## Checklist di test sul dispositivo

Fluidità
- [ ] Avvio rapido, YouTube carica, scrolling fluido, swipe indietro/avanti.
- [ ] Nessun rallentamento rispetto a Safari aprendo 10–15 video di fila.

Pubblicità
- [ ] 10 video diversi (anche lunghi, che di solito hanno spot a metà): quanti spot compaiono, e per quanto?
- [ ] Home e ricerca: nessun riquadro "Sponsorizzato".
- [ ] Shorts: nessun annuncio tra uno Short e l'altro.

Background
- [ ] Video avviato → blocco schermo → l'audio continua.
- [ ] Video avviato → torna alla Home → l'audio continua.
- [ ] Schermata di blocco: titolo, play/pausa, avanti; la pausa da lì viene rispettata.
- [ ] Playlist: il brano successivo parte a schermo spento.
- [ ] Ascolto lungo (oltre 30 minuti) senza "Vuoi continuare a guardare?".

PiP e AirPlay
- [ ] Pulsante PiP → finestra flottante → altre app.
- [ ] Schermo intero → Home → PiP automatico.
- [ ] AirPlay dal pulsante che compare durante la riproduzione: arriva il video sulla TV?
- [ ] AirPlay dal player a schermo intero.

Altro
- [ ] Login Google su YouTube: riesce e resta attivo dopo il riavvio.
- [ ] Tema scuro, nessun lampo bianco.
- [ ] Musica di un'altra app: l'avvio di Lieve non la interrompe.

Se qualcosa non funziona, annota il passaggio esatto: di solito la correzione va in `filters/` e arriva senza reinstallare l'app.
