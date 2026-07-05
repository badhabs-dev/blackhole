import SwiftUI

/// Live-Ansicht einer Kamera: Video, Ton, Gegensprechen und PTZ-Steuerung.
struct CameraPlayerView: View {
    let camera: Camera

    @State private var player: StreamPlayer = VLCStreamPlayer()
    @State private var muted = false
    @State private var talking = false

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
        .onAppear {
            if let url = camera.mainStreamURL { player.play(url: url) }
        }
        .onDisappear {
            player.stop()
            if talking { player.stopTalkBack() }
        }
    }

    private var videoSurface: some View {
        ZStack {
            // Hier rendert MobileVLCKit sein Video-Layer (UIViewRepresentable).
            Rectangle().fill(Theme.eventHorizon)
            if camera.mainStreamURL == nil {
                Text("Keine Stream-URL – erst per ONVIF verbinden.")
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                    Text("Live-Stream").foregroundStyle(Theme.textSecondary)
                    Text(camera.mainStreamURL!.absoluteString)
                        .font(.caption2).foregroundStyle(Theme.textFaint)
                        .lineLimit(1).truncationMode(.middle).padding(.horizontal)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0/9.0, contentMode: .fit)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                controlButton(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", "Ton") {
                    muted.toggle(); player.setMuted(muted)
                }
                if camera.hasTwoWayAudio {
                    controlButton(talking ? "mic.fill" : "mic", "Sprechen", active: talking) {
                        toggleTalk()
                    }
                }
                controlButton("camera.fill", "Foto") { /* Snapshot speichern */ }
            }

            if camera.hasPTZ {
                ptzPad
            }
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

    private func toggleTalk() {
        talking.toggle()
        do {
            if talking { try player.startTalkBack() } else { player.stopTalkBack() }
        } catch {
            talking = false
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
