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
