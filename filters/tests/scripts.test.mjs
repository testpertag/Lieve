// Test degli script del pacchetto in un ambiente DOM simulato (Node ≥ 18).
// Uso: node filters/tests/scripts.test.mjs dist/pack.lvp
import fs from 'node:fs';
import zlib from 'node:zlib';
import vm from 'node:vm';
import assertBase from 'node:assert';
const assert = { ...assertBase, equal: assertBase.strictEqual, ok: assertBase.ok, match: assertBase.match, deepEqual: (a, b) => assertBase.deepStrictEqual(JSON.parse(JSON.stringify(a)), b) };

const packPath = process.argv[2];
const data = fs.readFileSync(packPath);
assert.equal(data.subarray(0, 4).toString(), 'LVP1');
const pack = JSON.parse(zlib.inflateRawSync(data.subarray(68)).toString());
const script = (id) => pack.scripts.find((s) => s.id === id).source;

function makeContext(hostname, cfg) {
  const listeners = [];
  class Document {}
  Object.defineProperty(Document.prototype, 'hidden', { get() { return true; }, configurable: true, enumerable: true });
  Object.defineProperty(Document.prototype, 'webkitHidden', { get() { return true; }, configurable: true, enumerable: true });
  Object.defineProperty(Document.prototype, 'visibilityState', { get() { return 'hidden'; }, configurable: true, enumerable: true });
  Object.defineProperty(Document.prototype, 'webkitVisibilityState', { get() { return 'hidden'; }, configurable: true, enumerable: true });
  Document.prototype.hasFocus = function hasFocus() { return false; };
  Document.prototype.addEventListener = function addEventListener(type, fn) { docListeners.push(type); };
  const docListeners = [];
  const timers = [];
  const pending = [];
  class XMLHttpRequest { constructor() { this.responseType = ''; this._r = null; } }
  Object.defineProperty(XMLHttpRequest.prototype, 'response', { get() { return this._r; }, configurable: true, enumerable: true });

  const ctx = {
    Document, XMLHttpRequest, Response, location: { hostname },
    document: new Document(),
    addEventListener: (type, fn, capture) => listeners.push({ type, fn, capture }),
    setTimeout: function setTimeout(fn, delay) { timers.push(delay); pending.push(fn); return timers.length; },
    clearTimeout: function clearTimeout() {},
    __pending: pending,
    __listeners: listeners,
    __timers: timers,
    __docListeners: docListeners,
  };
  ctx.window = ctx;
  vm.createContext(ctx);
  return ctx;
}

const run = (ctx, id, cfg) => vm.runInContext(script(id).replace('__LIEVE_CFG__', JSON.stringify(cfg)), ctx);

// --- 1. Script attivo su m.youtube.com ---------------------------------------
{
  const ctx = makeContext('m.youtube.com');
  run(ctx, 'youtube-page', { adblock: true, background: true, strategy: 'channel' });

  // Visibilità sempre "visibile"
  assert.equal(vm.runInContext('document.hidden', ctx), false);
  assert.equal(vm.runInContext('document.visibilityState', ctx), 'visible');
  assert.equal(vm.runInContext('document.webkitHidden', ctx), false);
  assert.equal(vm.runInContext('document.hasFocus()', ctx), true);
  const types = ctx.__listeners.map((l) => l.type);
  assert.ok(types.includes('visibilitychange') && types.includes('webkitvisibilitychange'));
  // blur: fermato solo se il target è la finestra
  const blur = ctx.__listeners.find((l) => l.type === 'blur').fn;
  let stopped = 0;
  blur({ target: vm.runInContext('window', ctx), stopImmediatePropagation: () => stopped++ });
  blur({ target: {}, stopImmediatePropagation: () => stopped++ });
  assert.equal(stopped, 1);

  // JSON.parse: rimozione dati pubblicitari
  const r = vm.runInContext(`JSON.parse('${JSON.stringify({
    adPlacements: [1], playerAds: [2], adSlots: [3], adBreakHeartbeatParams: 'x', videoDetails: { id: 'a' },
    playerResponse: { adPlacements: [1], streamingData: {} },
    auxiliaryUi: { messageRenderers: { enforcementMessageViewModel: {} } },
  })}')`, ctx);
  assert.deepEqual(Object.keys(r).sort(), ['auxiliaryUi', 'playerResponse', 'videoDetails']);
  assert.deepEqual(Object.keys(r.playerResponse), ['streamingData']);
  assert.deepEqual(r.auxiliaryUi.messageRenderers, {});

  // Array di risposte (navigazione interna)
  const arr = vm.runInContext(`JSON.parse('[{"playerResponse":{"playerAds":[1],"x":1}}]')`, ctx);
  assert.deepEqual(arr[0].playerResponse, { x: 1 });

  // Shorts: rimozione delle voci pubblicitarie
  const shorts = vm.runInContext(`JSON.parse('${JSON.stringify({ entries: [
    { command: { reelWatchEndpoint: { videoId: 'v1' } } },
    { command: { reelWatchEndpoint: { adClientParams: { isAd: true } } } },
    { command: { reelWatchEndpoint: { videoId: 'v2' } } },
  ] })}')`, ctx);
  assert.equal(shorts.entries.length, 2);

  // Valori primitivi e JSON non pertinenti intatti
  assert.equal(vm.runInContext('JSON.parse("42")', ctx), 42);
  assert.deepEqual(vm.runInContext('JSON.parse(\'{"a":[1,2]}\')', ctx), { a: [1, 2] });

  // var ytInitialPlayerResponse = {...} (assegnazione da script inline)
  vm.runInContext('var ytInitialPlayerResponse = { adPlacements: [1], playerAds: [1], videoDetails: {} };', ctx);
  assert.deepEqual(Object.keys(vm.runInContext('ytInitialPlayerResponse', ctx)), ['videoDetails']);

  // XHR con responseType json
  const xhr = vm.runInContext('(() => { const x = new XMLHttpRequest(); x.responseType = "json"; x._r = { adSlots: [1], ok: 1 }; return x.response; })()', ctx);
  assert.deepEqual(xhr, { ok: 1 });

  // fetch(...).json()
  const viaFetch = await vm.runInContext(
    'new Response(\'{"adPlacements":[1],"ok":true}\').json()', ctx);
  assert.deepEqual(viaFetch, { ok: true });

  // Le funzioni sostituite sembrano native
  assert.match(vm.runInContext('Function.prototype.toString.call(JSON.parse)', ctx), /\[native code\]/);
}

// --- 1b. Richiesta del player "senza annunci" e timer dell'attesa --------------
const playerRequest = '({ context: { client: { clientName: "MWEB", clientScreen: "WATCH" } }, playbackContext: { contentPlaybackContext: { vis: 0 } }, videoId: "x" })';
for (const [strategy, screen, inline] of [['channel', 'CHANNEL', undefined], ['inline', 'WATCH', true], ['both', 'CHANNEL', true], ['prune', 'WATCH', undefined], ['skip', 'WATCH', undefined]]) {
  const ctx = makeContext('m.youtube.com');
  run(ctx, 'youtube-page', { adblock: true, background: true, strategy });
  const sent = JSON.parse(vm.runInContext(`JSON.stringify(${playerRequest})`, ctx));
  assert.equal(sent.context.client.clientScreen, screen, strategy);
  assert.equal(sent.playbackContext.contentPlaybackContext.isInlinePlaybackNoAd, inline, strategy);
  // Oggetti qualsiasi: invariati
  assert.equal(vm.runInContext('JSON.stringify({ a: 1, context: { client: {} } })', ctx), '{"a":1,"context":{"client":{}}}');
  // Timer: solo quello da 17 s con funzione nativa viene accelerato
  vm.runInContext('setTimeout(Math.max, 17000); setTimeout(() => 1, 17000); setTimeout(Math.max, 5000);', ctx);
  assert.deepEqual(ctx.__timers, [17, 17000, 5000]);
  // Salto spot: ascoltatori sui media registrati
  assert.ok(ctx.__docListeners.includes('playing') && ctx.__docListeners.includes('loadedmetadata'));
}

// --- 1d. Modalità "skip": nessuna rimozione, spot silenziato e portato alla fine -
{
  const ctx = makeContext('m.youtube.com');
  const h = {};
  Object.getPrototypeOf(ctx.document).addEventListener = function (type, fn) { (h[type] ||= []).push(fn); };
  let observerCb = null;
  ctx.MutationObserver = class { constructor(cb) { observerCb = cb; } observe() {} };
  run(ctx, 'youtube-page', { adblock: true, background: true, strategy: 'skip' });
  // Nessuna rimozione dai dati
  assert.deepEqual(vm.runInContext('JSON.parse(\'{"adPlacements":[1],"x":1}\')', ctx), { adPlacements: [1], x: 1 });
  // Spot in corso
  const classes = new Set(['ad-showing']);
  const video = { tagName: 'VIDEO', muted: false, duration: 15, currentTime: 0.3 };
  const player = { classList: { contains: (c) => classes.has(c) }, querySelector: (q) => (q === 'video' ? video : null),
                   getProgressState: () => ({ duration: 15 }), seekTo: (t) => { player.sought = t; } };
  video.closest = () => player;
  h.playing.forEach((fn) => fn({ target: video }));
  assert.equal(video.muted, true);
  assert.equal(video.currentTime, 15);
  assert.equal(player.sought, 15);
  // Fine dello spot: audio ripristinato
  classes.delete('ad-showing');
  observerCb();
  assert.equal(video.muted, false);
  // Video normale: nessun intervento
  video.currentTime = 3;
  h.timeupdate.forEach((fn) => fn({ target: video }));
  assert.equal(video.currentTime, 3);
}

// --- 1c. Recupero automatico di un video bloccato ------------------------------
{
  const ctx = makeContext('m.youtube.com');
  ctx.location.pathname = '/watch';
  ctx.location.search = '?v=abc';
  const loaded = [];
  let reloads = 0;
  ctx.location.reload = () => { reloads++; };
  const video = { tagName: 'VIDEO', paused: true, currentTime: 0, readyState: 1 };
  const player = { classList: { contains: () => false }, querySelector: () => video,
                   loadVideoById: (id, t) => loaded.push([id, t]) };
  ctx.document.getElementById = () => player;
  const storage = {};
  ctx.sessionStorage = { getItem: (k) => storage[k] ?? null, setItem: (k, v) => { storage[k] = v; } };
  const docHandlers = {};
  Object.getPrototypeOf(ctx.document).addEventListener = function (type, fn) { (docHandlers[type] ||= []).push(fn); };
  ctx.URLSearchParams = URLSearchParams;
  run(ctx, 'youtube-page', { adblock: true, background: true, strategy: 'channel' });
  const req = '({ context: { client: {} }, playbackContext: { contentPlaybackContext: {} } })';
  const fireLoadstart = () => docHandlers.loadstart.forEach((fn) => fn({ target: video }));
  const runLastTimer = () => ctx.__pending[ctx.__pending.length - 1]();

  fireLoadstart();
  assert.equal(ctx.__timers[ctx.__timers.length - 1], 7000);
  runLastTimer();                                   // fermo → nuova tecnica + loadVideoById
  assert.deepEqual(loaded, [['abc', 0]]);
  assert.equal(JSON.parse(vm.runInContext(`JSON.stringify(${req})`, ctx)).playbackContext.contentPlaybackContext.isInlinePlaybackNoAd, true);
  runLastTimer();                                   // ancora fermo → ricarica pagina
  assert.equal(reloads, 1);
  assert.equal(JSON.parse(storage['lieve.s']).s, 'prune');

  // Dopo la ricarica: niente secondo ricaricamento entro 2 minuti per lo stesso video
  const ctx2 = makeContext('m.youtube.com');
  Object.assign(ctx2.location, { pathname: '/watch', search: '?v=abc', reload: () => { reloads++; } });
  ctx2.sessionStorage = ctx.sessionStorage;
  ctx2.document.getElementById = () => player;
  const h2 = {};
  Object.getPrototypeOf(ctx2.document).addEventListener = function (type, fn) { (h2[type] ||= []).push(fn); };
  ctx2.URLSearchParams = URLSearchParams;
  run(ctx2, 'youtube-page', { adblock: true, background: true, strategy: 'channel' });
  h2.loadstart.forEach((fn) => fn({ target: video }));
  ctx2.__pending[ctx2.__pending.length - 1]();     // loadVideoById
  ctx2.__pending[ctx2.__pending.length - 1]();     // avrebbe ricaricato: bloccato dal limite
  assert.equal(reloads, 1);

  // Video che parte: nessun intervento
  const ctx3 = makeContext('m.youtube.com');
  Object.assign(ctx3.location, { pathname: '/watch', search: '?v=zzz', reload: () => { reloads++; } });
  const playing = { tagName: 'VIDEO', paused: false, currentTime: 3, readyState: 4 };
  const loaded3 = [];
  ctx3.document.getElementById = () => ({ classList: { contains: () => false }, querySelector: () => playing, loadVideoById: (...a) => loaded3.push(a) });
  const h3 = {};
  Object.getPrototypeOf(ctx3.document).addEventListener = function (type, fn) { (h3[type] ||= []).push(fn); };
  ctx3.URLSearchParams = URLSearchParams;
  run(ctx3, 'youtube-page', { adblock: true, background: true, strategy: 'channel' });
  h3.loadstart.forEach((fn) => fn({ target: playing }));
  ctx3.__pending[ctx3.__pending.length - 1]();
  assert.equal(loaded3.length, 0);
  assert.equal(reloads, 1);
}

// --- 2. Opzioni disattivate: nessuna modifica ---------------------------------
{
  const ctx = makeContext('m.youtube.com');
  run(ctx, 'youtube-page', { adblock: false, background: false });
  assert.equal(vm.runInContext('document.hidden', ctx), true);
  assert.deepEqual(vm.runInContext('JSON.parse(\'{"adSlots":[1]}\')', ctx), { adSlots: [1] });
  vm.runInContext('setTimeout(Math.max, 17000)', ctx);
  assert.deepEqual(ctx.__timers, [17000]);
  const sent = JSON.parse(vm.runInContext(`JSON.stringify(${playerRequest})`, ctx));
  assert.equal(sent.context.client.clientScreen, 'WATCH');
}

// --- 3. Altri siti: nessuna modifica ------------------------------------------
{
  const ctx = makeContext('www.notyoutube.com');
  run(ctx, 'youtube-page', { adblock: true, background: true });
  assert.equal(vm.runInContext('document.hidden', ctx), true);
  assert.deepEqual(vm.runInContext('JSON.parse(\'{"adSlots":[1]}\')', ctx), { adSlots: [1] });
  assert.equal(ctx.__listeners.length, 0);
}

// --- 4. Sintassi di tutti gli script ------------------------------------------
for (const s of pack.scripts) {
  new vm.Script(s.source.replace('__LIEVE_CFG__', '{"adblock":true,"background":true}'), { filename: s.id });
}

console.log(`OK: ${pack.scripts.length} script verificati`);
