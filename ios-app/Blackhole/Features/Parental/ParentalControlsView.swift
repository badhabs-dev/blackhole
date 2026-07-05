import SwiftUI

/// Elternkontrolle & Automatisierung: Zeitfenster, Limits, Blocklisten pro Gerät.
struct ParentalControlsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var editing: DevicePolicy?

    private var router: RouterController { session.router }
    private var store: PolicyStore { session.policies }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                List {
                    Section {
                        Text("Regeln werden über deinen Router durchgesetzt (Zeitpläne + DNS-Filter). Für eigene Apple-Familiengeräte kann zusätzlich Apples Bildschirmzeit genutzt werden.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                            .listRowBackground(Color.clear)
                    }

                    if router.clients.isEmpty {
                        Text("Erst im Router-Tab verbinden, um Geräte zu regeln.")
                            .font(.caption).foregroundStyle(Theme.textFaint)
                            .listRowBackground(Color.clear)
                    }

                    ForEach(router.clients) { client in
                        Button {
                            editing = store.policy(forDeviceID: client.id)
                        } label: {
                            policyRow(for: client)
                        }
                        .listRowBackground(Theme.eventHorizon)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Kontrolle")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Anwenden") { Task { await store.apply(using: router) } }
                }
            }
            .sheet(item: $editing) { policy in
                PolicyEditorView(policy: policy) { updated in
                    store.upsert(updated)
                    Task { await store.apply(using: router) }
                }
            }
        }
    }

    private func policyRow(for client: RouterClient) -> some View {
        let policy = store.policy(forDeviceID: client.id)
        return HStack {
            Image(systemName: "hand.raised.fill").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(client.name).foregroundStyle(Theme.textPrimary)
                Text(summary(policy)).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if policy.enabled && (!policy.schedule.isEmpty || !policy.blockedDomains.isEmpty) {
                Circle().fill(Theme.success).frame(width: 8, height: 8)
            }
        }
    }

    private func summary(_ p: DevicePolicy) -> String {
        var parts: [String] = []
        if !p.schedule.isEmpty { parts.append("\(p.schedule.count) Zeitfenster") }
        if p.dailyLimitMinutes > 0 { parts.append("\(p.dailyLimitMinutes) min/Tag") }
        if !p.blockedDomains.isEmpty { parts.append("\(p.blockedDomains.count) Sperren") }
        return parts.isEmpty ? "keine Regeln" : parts.joined(separator: " · ")
    }
}

/// Editor für die Regeln eines Geräts.
struct PolicyEditorView: View {
    @State var policy: DevicePolicy
    var onSave: (DevicePolicy) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var newDomain = ""
    @State private var limitHours = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Regeln aktiv", isOn: $policy.enabled)
                }
                Section("Tägliche Bildschirmzeit") {
                    VStack(alignment: .leading) {
                        Text("\(Int(limitHours * 60)) Minuten (0 = unbegrenzt)")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                        Slider(value: $limitHours, in: 0...12, step: 0.5)
                    }
                }
                Section("Erlaubte Zeitfenster") {
                    ForEach(policy.schedule) { w in
                        Text("\(weekdayName(w.weekday)): \(time(w.startMinute))–\(time(w.endMinute))")
                    }
                    .onDelete { policy.schedule.remove(atOffsets: $0) }
                    Button("Standard-Fenster hinzufügen (Mo–Fr 15–19 Uhr)") {
                        for wd in 2...6 {
                            policy.schedule.append(AllowedWindow(weekday: wd, startMinute: 15*60, endMinute: 19*60))
                        }
                    }
                }
                Section("Blockierte Webseiten / Domains") {
                    ForEach(policy.blockedDomains, id: \.self) { Text($0) }
                        .onDelete { policy.blockedDomains.remove(atOffsets: $0) }
                    HStack {
                        TextField("z.B. tiktok.com", text: $newDomain)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("+") {
                            guard !newDomain.isEmpty else { return }
                            policy.blockedDomains.append(newDomain); newDomain = ""
                        }
                    }
                }
            }
            .navigationTitle(policy.deviceName)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { limitHours = Double(policy.dailyLimitMinutes) / 60 }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        policy.dailyLimitMinutes = Int(limitHours * 60)
                        onSave(policy); dismiss()
                    }
                }
                ToolbarItem(placement: .cancelAction) { Button("Abbrechen") { dismiss() } }
            }
        }
    }

    private func weekdayName(_ w: Int) -> String {
        ["", "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"][safe: w] ?? "?"
    }
    private func time(_ m: Int) -> String { String(format: "%02d:%02d", m/60, m%60) }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
