import SwiftUI

/// Einrichtungsdialog: Router-Typ wählen und Zugangsdaten eingeben.
struct RouterSetupView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable, Identifiable {
        case fritzbox = "FRITZ!Box"
        case openwrt = "OpenWrt"
        var id: String { rawValue }
    }

    @State private var kind: Kind = .fritzbox
    @State private var host = ""
    @State private var username = "admin"
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Router-Typ") {
                    Picker("Typ", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                }
                Section("Zugang") {
                    TextField("Router-IP (z.B. 192.168.178.1)", text: $host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Benutzername", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Passwort (WLAN-/Admin-Passwort)", text: $password)
                }
                Section {
                    Text("Die Zugangsdaten bleiben auf dem Gerät (Keychain) und werden nur direkt mit deinem Router gesprochen. Aktionen wie Kicken erfordern, dass dir dieser Router gehört.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .navigationTitle("Router einrichten")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verbinden") { connect() }.disabled(host.isEmpty)
                }
                ToolbarItem(placement: .cancelAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private func connect() {
        let backend: RouterBackend
        switch kind {
        case .fritzbox:
            backend = FritzBoxBackend(host: host, username: username, password: password)
        case .openwrt:
            backend = OpenWrtBackend(host: host, username: username, password: password)
        }
        session.router.configure(backend)
        Task { await session.router.refreshClients() }
        dismiss()
    }
}
