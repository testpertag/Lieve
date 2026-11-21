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

// Strategia corrente: "skip" | "channel" | "inline" | "both" | "prune".
// Può cambiare da sola se un video resta bloccato (sezione 6).
let strategy = LIEVE.strategy || 'skip';
const store = (() => { try { return window.sessionStorage; } catch (_) { return null; } })();
try {
  // Tecnica scelta dal recupero automatico prima di una ricarica (valida 10 minuti).
  const saved = store && JSON.parse(store.getItem('lieve.s') || 'null');
  if (saved && Date.now() - saved.t < 600000) strategy = saved.s;
} catch (_) {}
const nativeSetTimeout = window.setTimeout;
const nativeClearTimeout = window.clearTimeout;

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
    if (strategy === 'skip' || !root || typeof root !== 'object') return root;
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

// ---------------------------------------------------------------------------
// 3) Richiesta "senza annunci": il server non programma spot, quindi non applica
//    l'attesa punitiva che scatta quando gli spot vengono rimossi dopo l'arrivo.
//    Stessa idea delle regole uBlock Origin del 17/11/2026 (trusted-edit-inbound-object
//    su JSON.stringify): clientScreen CHANNEL oppure isInlinePlaybackNoAd.
//    LIEVE.strategy: "channel" | "inline" | "both" | "prune" (solo rimozione).
// ---------------------------------------------------------------------------

if (LIEVE.adblock) {
  const editPlayerRequest = (o) => {
    const S = strategy;
    if (S === 'prune' || S === 'skip') return;
    if (!o || typeof o !== 'object') return;
    const pc = o.playbackContext;
    const cpc = pc && pc.contentPlaybackContext;
    const client = o.context && o.context.client;
    if (!cpc || !client) return;                       // solo le richieste del player
    if (S === 'channel' || S === 'both') client.clientScreen = 'CHANNEL';
    if (S === 'inline' || S === 'both') cpc.isInlinePlaybackNoAd = true;
  };
  JSON.stringify = wrap(JSON.stringify, (t, self, args) => {
    try { editPlayerRequest(args[0]); } catch (_) {}
    return R.apply(t, self, args);
  });
}

// ---------------------------------------------------------------------------
// 4) Timer dell'attesa artificiale (uBO: nano-stb, [native code], 17000, 0.001).
//    Si controlla prima il ritardo: costo nullo per tutti gli altri timer.
// ---------------------------------------------------------------------------
if (LIEVE.adblock) {
  window.setTimeout = wrap(window.setTimeout, (t, self, args) => {
    if (args[1] === 17000 && typeof args[0] === 'function'
        && Function.prototype.toString.call(args[0]).includes('[native code]')) {
      args[1] = 17;
    }
    return R.apply(t, self, args);
  });
}

// ---------------------------------------------------------------------------
// 5) Salto degli spot: lo spot arriva, viene silenziato e portato subito alla fine
//    (o si clicca "Salta"). Per YouTube risulta riprodotto: nessuna penalità.
//    È la tecnica principale in modalità "skip" e la rete di sicurezza nelle altre.
//    Solo su eventi del player e del video, nessun polling.
// ---------------------------------------------------------------------------
if (LIEVE.adblock) {
  const SKIP = '.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, '
             + '.ytp-ad-skip-button-container button, button.ytm-skip-ad-button';
  const watched = new WeakSet();
  const muted = new WeakMap();          // video -> stato "muto" prima dello spot

  const inAd = (p) => {
    if (p.classList.contains('ad-showing') || p.classList.contains('ad-interrupting')) return true;
    try {
      const st = typeof p.getStatsForNerds === 'function' ? p.getStatsForNerds() : null;
      return !!(st && typeof st.debug_info === 'string' && st.debug_info.startsWith('SSAP, AD'));
    } catch (_) { return false; }
  };

  const handle = (p, video) => {
    if (!inAd(p)) {
      if (video && muted.has(video)) { video.muted = muted.get(video); muted.delete(video); }
      return;
    }
    if (video && !muted.has(video)) { muted.set(video, video.muted); video.muted = true; }
    const btn = p.querySelector(SKIP);
    if (btn) { btn.click(); return; }
    try {
      // Spot separato: il <video> contiene solo lo spot, basta portarlo alla fine.
      if (video && isFinite(video.duration) && video.duration > 0 && video.currentTime < video.duration - 0.25) {
        video.currentTime = video.duration;
      }
      // Spot inserito nel flusso (SSAP): fine dello spot secondo il player.
      const pr = typeof p.getProgressState === 'function' ? p.getProgressState() : null;
      if (pr && pr.duration > 0 && typeof p.seekTo === 'function') p.seekTo(pr.duration);
    } catch (_) {}
  };

  const attach = (video) => {
    const p = video.closest('#movie_player, .html5-video-player');
    if (!p) return;
    if (!watched.has(p)) {
      watched.add(p);
      new MutationObserver(() => handle(p, p.querySelector('video')))
        .observe(p, { attributes: true, attributeFilter: ['class'] });
    }
    handle(p, video);
  };

  for (const type of ['loadedmetadata', 'playing']) {
    document.addEventListener(type, (e) => {
      if (e.target && e.target.tagName === 'VIDEO') attach(e.target);
    }, true);
  }
  // Durante uno spot, nuovo tentativo a ogni avanzamento (se il primo salto non è andato).
  document.addEventListener('timeupdate', (e) => {
    const v = e.target;
    if (!v || v.tagName !== 'VIDEO') return;
    const p = v.closest('#movie_player, .html5-video-player');
    if (p && p.classList.contains('ad-showing')) handle(p, v);
  }, true);
}

// ---------------------------------------------------------------------------
// 6) Recupero automatico: se dopo l'apertura il video resta fermo (penalità di
//    YouTube), lo ricarica con la tecnica successiva; al secondo tentativo ricarica
//    la pagina. È ciò che succede a mano spegnendo e riaccendendo il blocco.
//    Un solo timer per video, nessun polling. Stessa idea dello script uBO
//    del 17/11/2026 (loadVideoById con un'altra variante della richiesta).
// ---------------------------------------------------------------------------
if (LIEVE.adblock) {
  const ORDER = ['skip', 'channel', 'inline', 'prune'];
  const WAIT_MS = 7000;
  let timer = 0, retries = 0, lastId = '';

  const currentId = () => {
    try { return new URLSearchParams(location.search).get('v') || ''; } catch (_) { return ''; }
  };

  const isStuck = (video) => {
    if (!video) return true;
    if (video.paused && video.currentTime > 0.5) return false;   // messo in pausa dall'utente
    return video.readyState < 3 || video.currentTime < 0.5;
  };

  const check = () => {
    timer = 0;
    if (!location.pathname.startsWith('/watch')) return;
    const player = document.getElementById('movie_player');
    const video = player ? player.querySelector('video') : document.querySelector('video');
    if (player && player.classList.contains('ad-showing')) { arm(); return; }
    if (!isStuck(video) || retries >= 2) return;
    retries++;
    strategy = ORDER[(ORDER.indexOf(strategy) + 1) % ORDER.length];
    const id = currentId();
    if (retries === 1 && player && typeof player.loadVideoById === 'function' && id) {
      player.loadVideoById(id, video ? Math.floor(video.currentTime) : 0);
      arm();
    } else {
      // Al massimo una ricarica per video ogni 2 minuti: mai un ciclo di ricariche.
      try {
        const last = JSON.parse(store.getItem('lieve.r') || 'null');
        if (last && last.id === id && Date.now() - last.t < 120000) return;
        store.setItem('lieve.r', JSON.stringify({ id, t: Date.now() }));
        store.setItem('lieve.s', JSON.stringify({ s: strategy, t: Date.now() }));
      } catch (_) {}
      location.reload();
    }
  };

  const arm = () => {
    if (timer) nativeClearTimeout(timer);
    timer = nativeSetTimeout(check, WAIT_MS);
  };

  document.addEventListener('loadstart', (e) => {
    if (!e.target || e.target.tagName !== 'VIDEO') return;
    const id = currentId();
    if (id !== lastId) { lastId = id; retries = 0; }
    arm();
  }, true);
}
