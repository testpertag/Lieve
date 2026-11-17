import UIKit
import WebKit
import Observation

/// Stato multimediale osservato dall'interfaccia (es. per mostrare AirPlay in un tocco).
@MainActor
@Observable
final class MediaState {
    static let shared = MediaState()
    private(set) var videoPlaying = false
    /// Millisecondi tra l'apertura della pagina e l'avvio del contenuto (spot esclusi).
    private(set) var startMetric: String?
    @ObservationIgnored var onChange: (() -> Void)?
    private init() {}

    func setStartMetric(_ value: String) {
        startMetric = value
        onChange?()
    }

    func setVideoPlaying(_ playing: Bool) {
        guard playing != videoPlaying else { return }
        videoPlaying = playing
        onChange?()
    }
}

enum PiPResult: String {
    case entered, exited, skip, noVideo = "no-video", unsupported, failed
}

/// Collegamento nativo ↔ media della pagina. Tutto è guidato da eventi:
/// notifiche di sistema (background/foreground) e messaggi dalla pagina. Nessun polling.
@MainActor
final class MediaBridge: NSObject, WKScriptMessageHandler {
    static let shared = MediaBridge()
    private static let handlerName = "lieveMedia"

    private let webViews = NSHashTable<WKWebView>.weakObjects()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.willResignActive() }
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didEnterBackground() }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.call("__lieveMedia.foreground()") }
        }
    }

    func register(_ webView: WKWebView) {
        webViews.add(webView)
    }

    /// Chiamato da FilterManager ogni volta che ricostruisce gli script di un controller.
    func install(in controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: .lieve))
        controller.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: .lieve)
        controller.add(self, contentWorld: .lieve, name: Self.handlerName)
    }

    // MARK: - Azioni

    func togglePictureInPicture(in webView: WKWebView, completion: @escaping (PiPResult) -> Void) {
        // evaluateJavaScript viene eseguito come gesto dell'utente: WebKit accetta la richiesta PiP.
        webView.evaluateJavaScript("window.__lieveMedia ? __lieveMedia.togglePiP() : 'failed'",
                                   in: nil, in: .lieve) { result in
            let value = (try? result.get()) as? String
            completion(PiPResult(rawValue: value ?? "") ?? .failed)
        }
    }

    // MARK: - Ciclo di vita

    private func willResignActive() {
        // PiP automatico (opzionale): va richiesto finché l'app è ancora in primo piano.
        guard Preferences.autoPiP, MediaState.shared.videoPlaying else { return }
        call("__lieveMedia.autoPiP()")
    }

    private func didEnterBackground() {
        guard Preferences.backgroundPlay else { return }
        holdBackgroundTime()
        call("__lieveMedia.background(true)")
    }

    private func call(_ js: String) {
        for webView in webViews.allObjects {
            webView.evaluateJavaScript("window.__lieveMedia && \(js)", in: nil, in: .lieve, completionHandler: nil)
        }
    }

    /// Pochi secondi garantiti per completare pausa di sistema → ripresa.
    /// Dopo, se l'audio è in riproduzione, è UIBackgroundModes=audio a tenere viva l'app.
    private func holdBackgroundTime() {
        endBackgroundTime()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "lieve.media") { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundTime() }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.endBackgroundTime()
        }
    }

    private func endBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Messaggi dalla pagina

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if let playing = body["playing"] as? Bool { MediaState.shared.setVideoPlaying(playing) }
        if let ms = body["startMs"] as? Int {
            let ads = (body["adsSeen"] as? Bool) == true ? "ads" : "noads"
            MediaState.shared.setStartMetric("\(ms) \(ads)")
            #if DEBUG
            print("LIEVE_METRIC start=\(ms)ms \(ads) strategy=\(Preferences.adStrategy) adblock=\(Preferences.adBlock)")
            #endif
        }
    }

    // MARK: - Script (mondo isolato "lieve", tutti i siti, frame principale)

    static let script = #"""
    (() => {
      if (window.__lieveMedia) return;
      const post = (m) => { try { window.webkit.messageHandlers.lieveMedia.postMessage(m); } catch (_) {} };
      let current = null;          // ultimo <video> in riproduzione
      let reported = false;
      let lastPaused = null, lastPauseAt = 0;
      let bgAt = 0;

      const report = () => {
        const playing = !!(current && current.isConnected && !current.paused);
        if (playing !== reported) { reported = playing; post({ playing }); }
      };
      const resume = (v) => {
        try { const p = v.play(); if (p && p.catch) p.catch(() => {}); } catch (_) {}
      };

      // Tempo di avvio del contenuto (spot esclusi): misurato una volta per pagina.
      const t0 = performance.now();
      let measured = false, adsSeen = false;
      const inAd = (v) => {
        const p = v.closest('#movie_player, .html5-video-player');
        return !!(p && p.classList.contains('ad-showing'));
      };
      const measure = (v) => {
        if (measured) return;
        if (inAd(v)) { adsSeen = true; return; }
        measured = true;
        post({ startMs: Math.round(performance.now() - t0), adsSeen });
      };

      document.addEventListener('playing', (e) => {
        if (e.target instanceof HTMLVideoElement) { current = e.target; report(); measure(e.target); }
      }, true);
      document.addEventListener('timeupdate', (e) => {
        if (!measured && e.target instanceof HTMLVideoElement && !e.target.paused) measure(e.target);
      }, true);

      document.addEventListener('pause', (e) => {
        const v = e.target;
        if (!(v instanceof HTMLMediaElement)) return;
        if (!v.ended) {
          lastPaused = v; lastPauseAt = Date.now();
          // Pausa imposta da iOS subito dopo l'uscita dall'app: si riprende.
          if (bgAt && Date.now() - bgAt < 3000) { resume(v); return; }
        }
        if (v === current) report();
      }, true);

      document.addEventListener('ended', (e) => { if (e.target === current) report(); }, true);
      document.addEventListener('emptied', (e) => { if (e.target === current) report(); }, true);

      const findVideo = () => {
        const all = Array.from(document.querySelectorAll('video'));
        return all.find((v) => v.webkitPresentationMode === 'picture-in-picture')
          || all.find((v) => !v.paused)
          || (current && current.isConnected ? current : null)
          || all.find((v) => v.readyState > 0)
          || null;
      };

      const enterPiP = (v) => {
        if (typeof v.webkitSupportsPresentationMode === 'function'
            && v.webkitSupportsPresentationMode('picture-in-picture')) {
          v.webkitSetPresentationMode('picture-in-picture');
          return 'entered';
        }
        if (document.pictureInPictureEnabled && typeof v.requestPictureInPicture === 'function') {
          v.requestPictureInPicture().catch(() => {});
          return 'entered';
        }
        return 'unsupported';
      };

      Object.defineProperty(window, '__lieveMedia', { value: Object.freeze({
        background(enabled) {
          if (!enabled) return;
          bgAt = Date.now();
          // Se la pausa di sistema è arrivata un istante prima di questa chiamata.
          if (lastPaused && !lastPaused.ended && bgAt - lastPauseAt < 500) resume(lastPaused);
        },
        foreground() { bgAt = 0; },
        togglePiP() {
          const v = findVideo();
          if (!v) return 'no-video';
          if (v.webkitPresentationMode === 'picture-in-picture') {
            v.webkitSetPresentationMode('inline');
            return 'exited';
          }
          return enterPiP(v);
        },
        autoPiP() {
          const v = current;
          if (!v || v.paused || (v.webkitPresentationMode && v.webkitPresentationMode !== 'inline')) return 'skip';
          return enterPiP(v);
        },
      }) });
    })();
    """#
}
