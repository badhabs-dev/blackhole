import Foundation
import AVFoundation

/// Abstraktion für die Wiedergabe eines Kamera-Streams.
///
/// Wichtig: **AVPlayer von iOS kann kein RTSP.** Die allermeisten IP-Kameras
/// liefern aber RTSP. Deshalb bindet man in der Praxis `MobileVLCKit`
/// (LGPL, via Swift Package / CocoaPods) ein – VLC beherrscht RTSP inkl. H.264/
/// H.265 und Audio.
///
/// Diese Protokoll-Schicht hält den restlichen Code unabhängig vom konkreten
/// Player. `VLCStreamPlayer` (unten) ist der reale Adapter; er ist bewusst nur
/// als Umriss vorhanden, damit das Projekt ohne die VLC-Abhängigkeit kompiliert.
protocol StreamPlayer: AnyObject {
    func play(url: URL)
    func stop()
    func setMuted(_ muted: Bool)
    /// Startet die Mikrofon-Rückübertragung (Zwei-Wege-Audio), falls unterstützt.
    func startTalkBack() throws
    func stopTalkBack()
    var isPlaying: Bool { get }
}

/// Realer Adapter auf Basis von MobileVLCKit.
///
/// Zum Aktivieren:
///   1. Swift Package `https://github.com/thabinowski/VLCKitSPM` (oder CocoaPods
///      `MobileVLCKit`) hinzufügen.
///   2. `import MobileVLCKit`, `VLCMediaPlayer` verwenden.
///   3. Diesen Stub durch die auskommentierten Zeilen ersetzen.
///
/// Für Zwei-Wege-Audio nimmt man das Mikrofon (AVAudioEngine) auf und schickt
/// es über den ONVIF-Backchannel (RTSP `Require: www.onvif.org/ver20/backchannel`)
/// zur Kamera.
final class VLCStreamPlayer: NSObject, StreamPlayer {
    private(set) var isPlaying = false
    private let audioEngine = AVAudioEngine()

    // private let player = VLCMediaPlayer()   // ← mit MobileVLCKit

    func play(url: URL) {
        // player.media = VLCMedia(url: url)
        // player.play()
        isPlaying = true
        print("[VLCStreamPlayer] play \(url)  — MobileVLCKit einbinden, um echt abzuspielen.")
    }

    func stop() {
        // player.stop()
        isPlaying = false
    }

    func setMuted(_ muted: Bool) {
        // player.audio?.isMuted = muted
    }

    func startTalkBack() throws {
        try configureAudioSession()
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            // Hier: PCM → AAC/G.711 kodieren und über RTSP-Backchannel senden.
        }
        try audioEngine.start()
    }

    func stopTalkBack() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
    }
}
