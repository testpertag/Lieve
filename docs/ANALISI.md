# Analisi tecnica — Lieve

Stato: novembre 2026, iOS 26, iPhone 14.

## Priorità e come sono ottenute

| Priorità | Tecnica | Dove |
|---|---|---|
| Fluidità | Nessun polling, nessuna iniezione ripetuta. Script eseguiti una sola volta a document-start. Regole di blocco compilate da WebKit una volta e messe in cache. Stato UI via KVO + `@Observable`. | tutto il progetto |
| Interfaccia minimale | Un solo pulsante flottante. Barra comandi a scomparsa. AirPlay compare accanto al pulsante quando un video è in riproduzione. | `UI/FloatingMenu.swift` |
| Blocco pubblicità YouTube | (1) Rimozione di `adPlacements`/`playerAds`/`adSlots` dalle risposte del player (`JSON.parse`, `Response.json`, XHR, `ytInitialPlayerResponse`), (2) annunci negli Shorts, (3) popup anti-adblock, (4) blocco di rete degli endpoint pubblicitari, (5) nascondimento CSS dei riquadri sponsorizzati, (6) rete di sicurezza per gli spot residui: muto + velocità 16× + clic su "Salta". | `filters/scripts/youtube-page.js`, `youtube-isolated.js`, `filters/rules/youtube.json` |
| Blocco generale | EasyList + EasyPrivacy convertite nel formato nativo WebKit (solo regole eseguibili nativamente). | `filters/tools/abp2webkit.py` |
| Audio a schermo spento | (1) La pagina vede sempre `visibilityState = visible` (tecnica Mozilla/Brave). (2) Ripresa nativa se iOS mette in pausa il video all'uscita dall'app. (3) Segnale di attività contro "Vuoi continuare a guardare?". | `youtube-page.js`, `Media/MediaBridge.swift` |
| PiP con altre app | Pulsante PiP (gesto utente, sempre accettato da WebKit). PiP automatico opzionale all'uscita. Schermo intero → Home attiva il PiP nativo. | `MediaBridge.swift` |
| AirPlay | `AVRoutePickerView` di sistema, raggiungibile con un tocco durante la riproduzione. | `UI/RoutePicker.swift` |

Le tecniche di blocco seguono le regole pubbliche di uBlock Origin per YouTube (aggiornate al 9 novembre 2026: `json-prune` e `set` su `playerResponse.adPlacements`, `playerAds`, `adSlots`, voci `isAd` degli Shorts).

## Architettura dei filtri (aggiornabili senza reinstallare l'app)

```
filters/                    ← unica cartella da modificare quando YouTube cambia
  pack.json                 manifest: liste locali, liste remote, script
  rules/youtube.json        regole WebKit scritte a mano (critiche, piccole)
  scripts/*.js              script YouTube (mondo "page" e mondo isolato "lieve")
  tools/build_pack.py       costruzione, compressione, firma Ed25519
  tools/abp2webkit.py       convertitore EasyList → WebKit
  tools/check_rules.swift   verifica con il vero compilatore WebKit (macOS)
  tests/                    test Python e Node
```

Flusso: GitHub Actions (ogni giorno o a ogni modifica di `filters/`) → scarica EasyList/EasyPrivacy → converte → compila ogni lista con WebKit su macOS e scarta le regole rifiutate → firma → pubblica `pack.lvp` nella release `filters` solo se il contenuto è cambiato.

L'app:
- all'avvio legge un piccolo indice e recupera le liste già compilate (millisecondi);
- una volta al giorno scarica l'impronta del pacchetto (pochi byte) e, solo se diversa, il pacchetto;
- verifica la firma Ed25519 con la chiave pubblica inclusa nell'app: un pacchetto alterato viene scartato;
- ricompila solo le liste cambiate, in background, una alla volta.

La richiesta di aggiornamento usa una sessione senza cookie né cache: non trasmette dati di navigazione.

## Limiti noti (onestamente)

- **Spot inseriti lato server (SSAI)**: nessun blocco li elimina alla fonte. La rete di sicurezza li accelera e li silenzia; può restare qualche istante visibile.
- **Corsa con YouTube**: quando YouTube cambia, basta modificare `filters/` e fare push. L'app riceve la correzione entro un giorno, senza reinstallarla.
- **PiP automatico dalla riproduzione nella pagina**: Apple non lo garantisce per i video web. L'opzione è sperimentale e si attiva anche aprendo il Centro di Controllo. Il percorso sempre affidabile è schermo intero → Home.
- **Ripresa in background**: dipende dall'ordine degli eventi di WebKit. Coperti entrambi i casi (pausa prima o dopo la notifica di sistema). Va comunque confermata sul dispositivo.
- **Termini di servizio**: blocco pubblicità e riproduzione in background vanno contro i termini di YouTube. Non toccano DRM, credenziali o cifratura.
- **Pagina web Google per il login**: Google può rifiutare l'accesso in WebView. Lo user agent tipo Safari di solito basta.

## Prestazioni: cosa costa cosa

| Componente | Costo |
|---|---|
| Script YouTube page | Un `Proxy` su `JSON.parse` e `Response.json`: qualche controllo di chiave per ogni JSON. Attivo solo su YouTube. |
| Script isolato YouTube | Un `MutationObserver` limitato all'attributo `class` del player. Un timer da 60 s solo durante la riproduzione. |
| MediaBridge | Ascoltatori di eventi media; un messaggio all'app solo quando lo stato cambia. |
| Regole WebKit | Valutate in codice nativo (automa compilato). La compilazione avviene una volta per versione, in background. |
| Aggiornamenti | Una richiesta di pochi byte al giorno. |
