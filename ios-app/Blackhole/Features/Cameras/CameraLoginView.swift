import SwiftUI

/// Login-Maske für eine Kamera; nach erfolgreichem Login öffnet sich der Player.
struct CameraLoginView: View {
    let host: String
    var prefilled: Camera? = nil

    @EnvironmentObject private var session: AppSession
    @State private var username = "admin"
    @State private var password = ""
    @State private var connecting = false
    @State private var errorText: String?
    @State private var connected: Camera?

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    GlowCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Verbindung zu \(host)").font(.headline).foregroundStyle(Theme.textPrimary)
                            TextField("Benutzername", text: $username)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            SecureField("Passwort", text: $password)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                Task { await connect() }
                            } label: {
                                HStack {
                                    if connecting { ProgressView().tint(.white) }
                                    Text(connecting ? "Verbinde…" : "Verbinden (ONVIF)")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                            .disabled(connecting)

                            if let errorText {
                                Text(errorText).font(.caption).foregroundStyle(Theme.danger)
                            }
                        }
                    }
                    Text("Tipp: Die Zugangsdaten sind die der Kamera selbst (oft admin / eigenes Passwort). Sie werden nur lokal zum Abruf der RTSP-URL genutzt.")
                        .font(.caption2).foregroundStyle(Theme.textFaint)
                        .padding(.horizontal)
                }
                .padding()
            }
        }
        .navigationTitle("Kamera-Login")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $connected) { CameraPlayerView(camera: $0) }
    }

    private func connect() async {
        connecting = true; errorText = nil
        defer { connecting = false }
        let base = prefilled ?? Camera(name: host, host: host)
        do {
            connected = try await session.cameraDiscovery.connect(base, username: username, password: password)
        } catch {
            errorText = "Login/Stream fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
