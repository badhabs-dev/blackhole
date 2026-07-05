import Foundation
import SwiftUI
import UIKit
import AVFoundation
import VLCKitSPM

/// Echte Wiedergabe eines Kamera-Streams (RTSP/RTP, H.264/H.265) inkl. Audio.
///
/// iOS' eigener AVPlayer kann kein RTSP – deshalb läuft die Wiedergabe über
/// MobileVLCKit (Modul `VLCKitSPM`). Diese Klasse steuert einen VLCMediaPlayer:
/// abspielen, stummschalten, Schnappschuss und (best effort) Mikrofon-
/// Gegensprechen.
@MainActor
final class CameraStreamController: NSObject, ObservableObject {
    let player = VLCMediaPlayer()

    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var isMuted = false
    @Published var statusText = "Verbinde…"

    private let audioEngine = AVAudioEngine()
    private(set) var isTalking = false

    override init() {
        super.init()
        player.delegate = self
    }

    /// Hängt den Player an die anzuzeigende UIView (Video-Oberfläche).
    func attach(to view: UIView) {
        player.drawable = view
    }

    func play(url: URL) {
        let media = VLCMedia(url: url)
        // Niedrige Latenz + RTSP über TCP (robuster bei den meisten Kameras).
        media.addOption(":network-caching=300")
        media.addOption(":rtsp-tcp")
        media.addOption(":clock-jitter=0")
        player.media = media
        applyMute()
        player.play()
        isBuffering = true
        statusText = "Verbinde…"
    }

    func stop() {
        if player.isPlaying { player.stop() }
        isPlaying = false
        stopTalkBack()
    }

    func toggleMuted() {
        isMuted.toggle()
        applyMute()
    }

    /// Stummschalten über die Lautstärke (stabilste VLCAudio-API).
    private func applyMute() {
        player.audio?.volume = isMuted ? 0 : 100
    }

    /// Speichert einen Schnappschuss des aktuellen Bildes in die Fotomediathek.
    func snapshot() {
        let path = NSTemporaryDirectory().appending("blackhole_snap_\(Int(Date().timeIntervalSince1970)).png")
        player.saveVideoSnapshot(at: path, withWidth: 0, andHeight: 0)
        // saveVideoSnapshot schreibt asynchron – kurz warten, dann sichern.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let image = UIImage(contentsOfFile: path) {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        }
    }

    // MARK: - Gegensprechen (Zwei-Wege-Audio, best effort)

    /// Nimmt das Mikrofon auf. Der Rückkanal zur Kamera erfordert zusätzlich den
    /// ONVIF-Audio-Backchannel; ohne den wird nur lokal aufgenommen.
    func startTalkBack() {
        guard !isTalking else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let input = audioEngine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024,
                             format: input.outputFormat(forBus: 0)) { _, _ in
                // Hier: PCM → G.711/AAC kodieren und über den ONVIF-Backchannel senden.
            }
            try audioEngine.start()
            isTalking = true
        } catch {
            isTalking = false
        }
    }

    func stopTalkBack() {
        guard isTalking else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isTalking = false
    }
}

/// VLC-Statusmeldungen in unseren @Published-State übersetzen.
extension CameraStreamController: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in
            switch player.state {
            case .playing:
                isPlaying = true; isBuffering = false; statusText = "Live"
            case .buffering:
                isBuffering = true; statusText = "Puffere…"
            case .error:
                isPlaying = false; isBuffering = false; statusText = "Verbindungsfehler"
            case .stopped, .ended:
                isPlaying = false; statusText = "Beendet"
            default:
                break
            }
        }
    }
}

/// SwiftUI-Brücke zur VLC-Video-Oberfläche.
struct CameraVideoSurface: UIViewRepresentable {
    let controller: CameraStreamController
    let url: URL

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        controller.attach(to: view)
        controller.play(url: url)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
