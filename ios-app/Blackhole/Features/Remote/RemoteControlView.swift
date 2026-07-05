import SwiftUI

/// Fernsteuerung eigener Rechner: Bildschirm, Webcam und Dateien.
struct RemoteControlView: View {
    @EnvironmentObject private var session: AppSession
    @State private var pairing: CompanionAgent?
    @State private var showAdd = false
    @State private var host = ""
    @State private var port = "8765"

    private var registry: CompanionRegistry { session.companion }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                List {
                    Section {
                        Text("Steuere deine eigenen Rechner über den Blackhole Companion Agent (im Ordner companion-agent/). Er muss auf dem Ziel-PC laufen und einmalig gekoppelt werden.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(registry.agents) { agent in
                        agentRow(agent)
                            .listRowBackground(Theme.eventHorizon)
                    }
                    if registry.agents.isEmpty {
                        Text("Kein Agent gefunden. Starte den Agent auf dem PC oder füge ihn per IP hinzu.")
                            .font(.caption).foregroundStyle(Theme.textFaint)
                            .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Fernsteuerung")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Suchen") { registry.discover(from: session.scanner.devices) }.font(.caption)
                }
            }
            .onAppear { registry.discover(from: session.scanner.devices) }
            .sheet(item: $pairing) { agent in pairSheet(agent) }
            .sheet(isPresented: $showAdd) { addSheet }
        }
    }

    @ViewBuilder private func agentRow(_ agent: CompanionAgent) -> some View {
        if agent.isPaired {
            NavigationLink { AgentControlView(agent: agent) } label: {
                agentLabel(agent, subtitle: agent.info?.os ?? "gekoppelt")
            }
        } else {
            Button { pairing = agent } label: {
                agentLabel(agent, subtitle: "tippen zum Koppeln")
            }
        }
    }

    private func agentLabel(_ agent: CompanionAgent, subtitle: String) -> some View {
        HStack {
            Image(systemName: "desktopcomputer").foregroundStyle(Theme.accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name).foregroundStyle(Theme.textPrimary)
                Text("\(agent.host):\(agent.port) · \(subtitle)")
                    .font(.caption2).foregroundStyle(Theme.textFaint)
            }
            Spacer()
            if agent.isPaired { Image(systemName: "lock.open.fill").foregroundStyle(Theme.success) }
        }
    }

    private func pairSheet(_ agent: CompanionAgent) -> some View {
        PairView(agent: agent) { pin in
            let ok = await registry.pair(agent, pin: pin)
            if ok { pairing = nil }
            return ok
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Agent per Adresse hinzufügen") {
                    TextField("IP des PCs", text: $host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Port", text: $port).keyboardType(.numberPad)
                }
            }
            .navigationTitle("Agent hinzufügen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        registry.addManual(host: host, port: Int(port) ?? 8765)
                        host = ""; showAdd = false
                    }.disabled(host.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showAdd = false } }
            }
        }
    }
}

/// PIN-Kopplung.
private struct PairView: View {
    let agent: CompanionAgent
    let onPair: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var working = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "lock.shield").font(.system(size: 44)).foregroundStyle(Theme.accent)
                Text("Gib den PIN ein, der auf \(agent.name) angezeigt wird.")
                    .multilineTextAlignment(.center).foregroundStyle(Theme.textSecondary)
                TextField("PIN", text: $pin)
                    .keyboardType(.numberPad).multilineTextAlignment(.center)
                    .font(.title).textFieldStyle(.roundedBorder).frame(width: 160)
                if failed { Text("Kopplung fehlgeschlagen.").font(.caption).foregroundStyle(Theme.danger) }
                Button {
                    Task { working = true; failed = !(await onPair(pin)); working = false }
                } label: {
                    Text(working ? "Koppeln…" : "Koppeln").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(pin.isEmpty || working)
                Spacer()
            }
            .padding()
            .navigationTitle("Koppeln")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }
}
