// Lieve — YouTube, mondo isolato "lieve" (invisibile agli script di YouTube).
// Condivide il DOM con la pagina ma non le variabili JavaScript.
// L'app avvolge questo file in una funzione che definisce LIEVE = { adblock, background }.
'use strict';

// ---------------------------------------------------------------------------
// 1) Rete di sicurezza per gli spot che sfuggono (es. inseriti lato server):
//    muto + velocità massima + clic su "Salta". Basato su eventi, nessun polling.
// ---------------------------------------------------------------------------
if (LIEVE.adblock) {
  const SKIP = [
    '.ytp-skip-ad-button', '.ytp-ad-skip-button', '.ytp-ad-skip-button-modern',
    '.ytp-ad-skip-button-container button', 'button.ytm-skip-ad-button',
  ].join(',');
  const watched = new WeakSet();
  const saved = new WeakMap(); // video -> { muted, rate }

  const onAdState = (player) => {
    const video = player.querySelector('video');
    if (!video) return;
    const inAd = player.classList.contains('ad-showing');
    if (inAd) {
      if (!saved.has(video)) saved.set(video, { muted: video.muted, rate: video.playbackRate || 1 });
      video.muted = true;
      try { video.playbackRate = 16; } catch (_) {}
      const btn = player.querySelector(SKIP);
      if (btn) btn.click();
    } else if (saved.has(video)) {
      const s = saved.get(video);
      saved.delete(video);
      video.muted = s.muted;
      try { video.playbackRate = s.rate; } catch (_) {}
    }
  };

  const watchPlayer = (video) => {
    const player = video.closest('.html5-video-player, #movie_player');
    if (!player || watched.has(player)) return;
    watched.add(player);
    // Osserva solo l'attributo class del player: pochissimi eventi.
    new MutationObserver(() => onAdState(player))
      .observe(player, { attributes: true, attributeFilter: ['class'] });
    onAdState(player);
  };

  document.addEventListener('loadedmetadata', (e) => {
    if (e.target instanceof HTMLVideoElement) watchPlayer(e.target);
  }, true);
  document.addEventListener('playing', (e) => {
    if (e.target instanceof HTMLVideoElement) watchPlayer(e.target);
  }, true);
}

// ---------------------------------------------------------------------------
// 2) "Video in pausa. Vuoi continuare a guardare?": segnale di attività
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
