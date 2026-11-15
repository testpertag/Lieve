import AVFoundation

enum AudioSession {
    /// Categoria .playback: l'audio continua con il silenzioso attivo e, se il sito
    /// lo consente, in background e a schermo bloccato. È anche il prerequisito per il PiP.
    /// La sessione NON viene attivata qui: la attiva WebKit quando parte un media,
    /// così l'avvio dell'app non interrompe la musica di altre app.
    static func configure() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        } catch {
            #if DEBUG
            print("AudioSession: \(error)")
            #endif
        }
    }
}
