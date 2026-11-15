// Lieve — YouTube, mondo "page".
// Eseguito a document-start, solo nel frame principale e solo sui domini YouTube.
// L'app avvolge questo file in una funzione che definisce LIEVE = { adblock, background }.
// Tecniche equivalenti agli scriptlet pubblici di uBlock Origin (json-prune, set)
// e di Mozilla/Brave (video-bg-play). Nessun timer, nessun polling.
'use strict';

const P = Proxy;
const R = Reflect;

// Sostituisce un metodo/getter mantenendo l'aspetto nativo (Proxy su funzione nativa).
const wrap = (fn, apply) => new P(fn, { apply });

// ---------------------------------------------------------------------------
// 1) Riproduzione in background: la pagina vede sempre "visibile".
// ---------------------------------------------------------------------------
if (LIEVE.background) {
  const spoofGetter = (proto, prop, value) => {
    const d = Object.getOwnPropertyDescriptor(proto, prop);
    if (!d || typeof d.get !== 'function') return;
    try {
      Object.defineProperty(proto, prop, { ...d, get: wrap(d.get, () => value) });
    } catch (_) { /* proprietà non configurabile */ }
  };
  spoofGetter(Document.prototype, 'hidden', false);
  spoofGetter(Document.prototype, 'webkitHidden', false);
  spoofGetter(Document.prototype, 'visibilityState', 'visible');
  spoofGetter(Document.prototype, 'webkitVisibilityState', 'visible');

  if (typeof Document.prototype.hasFocus === 'function') {
    Document.prototype.hasFocus = wrap(Document.prototype.hasFocus, () => true);
  }

  // Ascoltatore in cattura su window: viene eseguito prima di quelli della pagina
  // e ferma la propagazione degli eventi di visibilità.
  const stop = (e) => e.stopImmediatePropagation();
  window.addEventListener('visibilitychange', stop, true);
  window.addEventListener('webkitvisibilitychange', stop, true);
  // Solo il blur della finestra, non quello dei campi di testo.
  window.addEventListener('blur', (e) => { if (e.target === window) stop(e); }, true);
}

// ---------------------------------------------------------------------------
// 2) Blocco pubblicità: rimozione dei dati pubblicitari dalle risposte del player.
// ---------------------------------------------------------------------------
if (LIEVE.adblock) {
  const AD_KEYS = ['adPlacements', 'playerAds', 'adSlots', 'adBreakHeartbeatParams'];

  const stripKeys = (o) => {
    if (!o || typeof o !== 'object') return;
    for (const k of AD_KEYS) if (k in o) delete o[k];
  };

  const isAdEntry = (e) => {
    const ep = e && e.command && e.command.reelWatchEndpoint;
    return !!(ep && ep.adClientParams && ep.adClientParams.isAd);
  };

  // Controlli puntuali su poche chiavi: costo trascurabile per ogni JSON.
  const prune = (root) => {
    if (!root || typeof root !== 'object') return root;
    try {
      stripKeys(root);
      if (root.playerResponse) stripKeys(root.playerResponse);
      if (Array.isArray(root)) {
        for (const item of root) if (item && item.playerResponse) stripKeys(item.playerResponse);
      }
      // Annunci tra gli Shorts.
      const seq = root.reelWatchSequenceResponse || root;
      if (Array.isArray(seq.entries)) {
        for (let i = seq.entries.length - 1; i >= 0; i--) {
          if (isAdEntry(seq.entries[i])) seq.entries.splice(i, 1);
        }
      }
      // Popup "Gli adblocker non sono consentiti".
      const mr = root.auxiliaryUi && root.auxiliaryUi.messageRenderers;
      if (mr && mr.enforcementMessageViewModel) delete mr.enforcementMessageViewModel;
    } catch (_) { /* mai interrompere la pagina */ }
    return root;
  };

  // JSON.parse (risposte lette come testo).
  JSON.parse = wrap(JSON.parse, (t, self, args) => prune(R.apply(t, self, args)));

  // fetch(...).json()
  if (typeof Response !== 'undefined' && Response.prototype.json) {
    Response.prototype.json = wrap(Response.prototype.json, (t, self, args) =>
      R.apply(t, self, args).then(prune));
  }

  // XMLHttpRequest con responseType = 'json'.
  if (typeof XMLHttpRequest !== 'undefined') {
    const d = Object.getOwnPropertyDescriptor(XMLHttpRequest.prototype, 'response');
    if (d && typeof d.get === 'function') {
      try {
        Object.defineProperty(XMLHttpRequest.prototype, 'response', {
          ...d,
          get: wrap(d.get, (t, self, args) => {
            const r = R.apply(t, self, args);
            return (self.responseType === 'json' && r && typeof r === 'object') ? prune(r) : r;
          }),
        });
      } catch (_) {}
    }
  }

  // Dati iniziali incorporati nella pagina: var ytInitialPlayerResponse = {...}
  for (const name of ['ytInitialPlayerResponse']) {
    let value;
    try {
      Object.defineProperty(window, name, {
        configurable: true,
        enumerable: true,
        get: () => value,
        set: (v) => { value = prune(v); },
      });
    } catch (_) {}
  }
}
