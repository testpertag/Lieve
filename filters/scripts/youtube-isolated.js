// Lieve — YouTube, mondo isolato "lieve" (invisibile agli script di YouTube).
// Condivide il DOM con la pagina ma non le variabili JavaScript.
// L'app avvolge questo file in una funzione che definisce LIEVE = { adblock, background }.
'use strict';

// ---------------------------------------------------------------------------
// "Video in pausa. Vuoi continuare a guardare?": segnale di attività
//    una volta al minuto, solo mentre un video è in riproduzione.
// ---------------------------------------------------------------------------
if (LIEVE.background) {
  let timer = 0;
  const ping = () => {
    for (const type of ['keydown', 'keyup']) {
      document.dispatchEvent(new KeyboardEvent(type, { key: 'Shift', code: 'ShiftLeft', bubbles: true }));
    }
  };
  document.addEventListener('playing', (e) => {
    if (!(e.target instanceof HTMLVideoElement) || timer) return;
    timer = setInterval(ping, 60000);
  }, true);
  const stop = (e) => {
    if (!(e.target instanceof HTMLVideoElement) || !timer) return;
    clearInterval(timer);
    timer = 0;
  };
  document.addEventListener('pause', stop, true);
  document.addEventListener('ended', stop, true);
}

// ---------------------------------------------------------------------------
// Pulsante "Apri l'app" nella barra in alto (riserva se le regole CSS non bastano).
// Osserva solo la barra superiore, non l'intera pagina.
// ---------------------------------------------------------------------------
{
  const LABELS = new Set(['open app', 'apri app', "apri l'app", 'apri l’app', 'app öffnen', 'ouvrir l’app']);
  const hideOpenApp = () => {
    const bar = document.querySelector('ytm-mobile-topbar-renderer, header');
    if (!bar) return;
    for (const el of bar.querySelectorAll('a, button')) {
      const text = (el.getAttribute('aria-label') || el.textContent || '').trim().toLowerCase();
      if (LABELS.has(text)) (el.closest('ytm-button-renderer') || el).style.display = 'none';
    }
  };
  document.addEventListener('DOMContentLoaded', () => {
    hideOpenApp();
    const bar = document.querySelector('ytm-mobile-topbar-renderer');
    if (bar) new MutationObserver(hideOpenApp).observe(bar, { childList: true, subtree: true });
  });
}
