// Test dello script MediaBridge (incorporato in Lieve/Media/MediaBridge.swift).
// Uso: node filters/tests/media-bridge.test.mjs
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert';

const swift = fs.readFileSync(new URL('../../Lieve/Media/MediaBridge.swift', import.meta.url), 'utf8');
const raw = swift.split('#"""')[1].split('"""#')[0];
const source = raw.split('\n').map((l) => l.replace(/^ {4}/, '')).join('\n');

function setup() {
  const listeners = {};
  const posts = [];
  let now = 1_000_000;
  class HTMLMediaElement {
    constructor() { this.paused = true; this.ended = false; this.isConnected = true; this.readyState = 4; this.plays = 0; }
    play() { this.plays++; this.paused = false; return Promise.resolve(); }
  }
  class HTMLVideoElement extends HTMLMediaElement {
    constructor() { super(); this.webkitPresentationMode = 'inline'; }
    webkitSupportsPresentationMode() { return true; }
    webkitSetPresentationMode(m) { this.webkitPresentationMode = m; }
  }
  const videos = [];
  const document = {
    addEventListener: (t, fn) => { (listeners[t] ||= []).push(fn); },
    querySelectorAll: () => videos,
  };
  const ctx = {
    document, HTMLMediaElement, HTMLVideoElement,
    Date: { now: () => now },
    webkit: { messageHandlers: { lieveMedia: { postMessage: (m) => posts.push(m.playing) } } },
    Object, Array, Promise,
  };
  ctx.window = ctx;
  vm.createContext(ctx);
  vm.runInContext(source, ctx);
  const fire = (type, target) => (listeners[type] || []).forEach((fn) => fn({ target }));
  const video = () => { const v = new HTMLVideoElement(); videos.push(v); return v; };
  return { ctx, fire, video, posts, tick: (ms) => { now += ms; }, api: () => vm.runInContext('window.__lieveMedia', ctx) };
}

// Riproduzione e pausa dell'utente → stato riportato all'app
{
  const t = setup();
  const v = t.video();
  v.paused = false; t.fire('playing', v);
  v.paused = true; t.fire('pause', v);
  assert.deepStrictEqual(t.posts, [true, false]);
  assert.strictEqual(v.plays, 0);
}

// iOS mette in pausa subito DOPO l'uscita dall'app → ripresa, nessun "false" all'app
{
  const t = setup();
  const v = t.video();
  v.paused = false; t.fire('playing', v);
  t.api().background(true);
  t.tick(200);
  v.paused = true; t.fire('pause', v);
  assert.strictEqual(v.plays, 1);
  assert.deepStrictEqual(t.posts, [true]);
}

// iOS mette in pausa un istante PRIMA della notifica → ripresa
{
  const t = setup();
  const v = t.video();
  v.paused = false; t.fire('playing', v);
  v.paused = true; t.fire('pause', v);
  t.tick(100);
  t.api().background(true);
  assert.strictEqual(v.plays, 1);
}

// Pausa dell'utente 2 s prima di uscire → nessuna ripresa
{
  const t = setup();
  const v = t.video();
  v.paused = false; t.fire('playing', v);
  v.paused = true; t.fire('pause', v);
  t.tick(2000);
  t.api().background(true);
  assert.strictEqual(v.plays, 0);
}

// Pausa dalla schermata di blocco dopo alcuni secondi → rispettata
{
  const t = setup();
  const v = t.video();
  v.paused = false; t.fire('playing', v);
  t.api().background(true);
  t.tick(10_000);
  v.paused = true; t.fire('pause', v);
  assert.strictEqual(v.plays, 0);
}

// Ritorno in primo piano azzera lo stato di background
{
  const t = setup();
  const v = t.video();
  t.api().background(true);
  t.api().foreground();
  t.tick(100);
  v.paused = true; t.fire('pause', v);
  assert.strictEqual(v.plays, 0);
}

// PiP: entra, esce, nessun video, autoPiP solo se in riproduzione
{
  const t = setup();
  assert.strictEqual(t.api().togglePiP(), 'no-video');
  const v = t.video();
  assert.strictEqual(t.api().togglePiP(), 'entered');
  assert.strictEqual(v.webkitPresentationMode, 'picture-in-picture');
  assert.strictEqual(t.api().togglePiP(), 'exited');
  assert.strictEqual(t.api().autoPiP(), 'skip');
  v.paused = false; t.fire('playing', v);
  assert.strictEqual(t.api().autoPiP(), 'entered');
}

// L'API non è modificabile dalla pagina
{
  const t = setup();
  assert.ok(Object.isFrozen(t.api()));
}

console.log('OK: MediaBridge verificato');
