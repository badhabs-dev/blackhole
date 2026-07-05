import SwiftUI

/// Übersicht aller entdeckten WLAN-Kameras.
struct CamerasView: View {
    @EnvironmentObject private var session: AppSession
    @State private var showAdd = false
    @State private var manualHost = ""
    @State private var manualName = ""

    private var discovery: CameraDiscovery { session.cameraDiscovery }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                List {
                    ForEach(discovery.cameras) { camera in
                        NavigationLink {
                            CameraLoginView(host: camera.host, prefilled: camera)
                        } label: {
                            cameraRow(camera)
                        }
                        .listRowBackground(Theme.eventHorizon)
                    }
                    if discovery.cameras.isEmpty {
                        Text("Noch keine Kameras. Starte einen Netzwerk-Scan oder füge eine per IP hinzu.")
                            .font(.caption).foregroundStyle(Theme.textFaint)
                            .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Kameras")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Scan übernehmen") { discovery.merge(from: session.scanner.devices) }
                        .font(.caption)
                }
            }
            .sheet(isPresented: $showAdd) { addSheet }
            .onAppear { discovery.merge(from: session.scanner.devices) }
        }
    }

    private func cameraRow(_ camera: Camera) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "video.fill").foregroundStyle(Theme.accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(camera.name).foregroundStyle(Theme.textPrimary)
                Text(camera.host).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if camera.mainStreamURL != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
            }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Kamera manuell hinzufügen") {
                    TextField("IP-Adresse oder Host", text: $manualHost)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Name (optional)", text: $manualName)
                }
            }
            .navigationTitle("Kamera hinzufügen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        discovery.addManual(host: manualHost, name: manualName)
                        manualHost = ""; manualName = ""; showAdd = false
                    }.disabled(manualHost.isEmpty)
                }
                ToolbarItem(placement: .cancelAction) {
                    Button("Abbrechen") { showAdd = false }
                }
            }
        }
    }
}
