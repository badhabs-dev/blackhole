import SwiftUI

/// Live-Ansicht einer Kamera: echtes Video, Ton, Gegensprechen und PTZ.
struct CameraPlayerView: View {
    let camera: Camera

    @StateObject private var stream = CameraStreamController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                videoSurface
                controls
            }
        }
        .navigationTitle(camera.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { stream.stop() }
    }

    private var videoSurface: some View {
        ZStack {
            if let url = camera.mainStreamURL {
                // Echte VLC-Wiedergabe (RTSP inkl. Audio).
                CameraVideoSurface(controller: stream, url: url)
            } else {
                Rectangle().fill(Theme.eventHorizon)
                Text("Keine Stream-URL – erst per ONVIF verbinden.")
                    .foregroundStyle(Theme.textSecondary)
            }

            if stream.isBuffering {
                VStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text(stream.statusText).font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            }

            // Status-Badge oben links.
            VStack {
                HStack {
                    Label(stream.statusText, systemImage: stream.isPlaying ? "dot.radiowaves.left.and.right" : "wifi.slash")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: Capsule())
                        .foregroundStyle(stream.isPlaying ? Theme.success : Theme.warning)
                    Spacer()
                }
                Spacer()
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0/9.0, contentMode: .fit)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                controlButton(stream.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", "Ton") {
                    stream.toggleMuted()
                }
                if camera.hasTwoWayAudio {
                    controlButton(stream.isTalking ? "mic.fill" : "mic", "Sprechen", active: stream.isTalking) {
                        stream.isTalking ? stream.stopTalkBack() : stream.startTalkBack()
                    }
                }
                controlButton("camera.fill", "Foto") { stream.snapshot() }
            }

            if camera.hasPTZ { ptzPad }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Theme.void)
    }

    private var ptzPad: some View {
        VStack(spacing: 8) {
            Text("Schwenken / Neigen / Zoom").font(.caption).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 40) {
                VStack(spacing: 8) {
                    ptzButton("chevron.up", pan: 0, tilt: 0.5)
                    HStack(spacing: 40) {
                        ptzButton("chevron.left", pan: -0.5, tilt: 0)
                        ptzButton("chevron.right", pan: 0.5, tilt: 0)
                    }
                    ptzButton("chevron.down", pan: 0, tilt: -0.5)
                }
                VStack(spacing: 16) {
                    ptzButton("plus.magnifyingglass", pan: 0, tilt: 0, zoom: 0.5)
                    ptzButton("minus.magnifyingglass", pan: 0, tilt: 0, zoom: -0.5)
                }
            }
        }
    }

    private func ptzButton(_ symbol: String, pan: Float, tilt: Float, zoom: Float = 0) -> some View {
        Image(systemName: symbol)
            .font(.title2).foregroundStyle(Theme.textPrimary)
            .frame(width: 48, height: 48)
            .background(Circle().fill(Theme.accretion))
            .onLongPressGesture(minimumDuration: 0.01, pressing: { pressing in
                Task { await handlePTZ(pressing: pressing, pan: pan, tilt: tilt, zoom: zoom) }
            }, perform: {})
    }

    private func controlButton(_ symbol: String, _ label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title2)
                Text(label).font(.caption2)
            }
            .foregroundStyle(active ? Theme.accent : Theme.textPrimary)
            .frame(width: 64, height: 60)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accretion))
        }
    }

    private func handlePTZ(pressing: Bool, pan: Float, tilt: Float, zoom: Float) async {
        guard let cred = camera.credentials else { return }
        let client = ONVIFClient(host: camera.host, port: camera.onvifPort,
                                 username: cred.username, password: cred.password)
        try? await client.sendPTZ(pressing ? .move(pan: pan, tilt: tilt, zoom: zoom) : .stop,
                                  profileToken: "Profile_1")
    }
}
