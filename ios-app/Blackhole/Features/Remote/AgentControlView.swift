import SwiftUI
import UniformTypeIdentifiers

/// Steuerzentrale für einen gekoppelten Rechner.
struct AgentControlView: View {
    let agent: CompanionAgent
    @State private var mode: Mode = .screen

    enum Mode: String, CaseIterable { case screen = "Bildschirm", webcam = "Webcam", files = "Dateien" }

    private var client: CompanionClient { CompanionClient(agent: agent) }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                Picker("Modus", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).padding()

                switch mode {
                case .screen:
                    if agent.info?.hasScreen ?? true {
                        MJPEGView(url: client.streamURL(kind: .screen))
                    } else { unavailable("Bildschirm") }
                case .webcam:
                    if agent.info?.hasWebcam ?? true {
                        MJPEGView(url: client.streamURL(kind: .webcam))
                    } else { unavailable("Webcam") }
                case .files:
                    RemoteFileBrowser(agent: agent)
                }
                Spacer(minLength: 0)
            }
        }
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func unavailable(_ what: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "xmark.octagon").font(.largeTitle).foregroundStyle(Theme.textFaint)
            Text("\(what) auf diesem Rechner nicht verfügbar.").foregroundStyle(Theme.textSecondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Einfacher Dateibrowser mit Download/Upload.
private struct RemoteFileBrowser: View {
    let agent: CompanionAgent
    @State private var path = "/"
    @State private var files: [RemoteFile] = []
    @State private var error: String?
    @State private var showImporter = false

    private var client: CompanionClient { CompanionClient(agent: agent) }

    var body: some View {
        List {
            Section {
                HStack {
                    Text(path).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Hochladen") { showImporter = true }.font(.caption)
                }.listRowBackground(Color.clear)
            }
            if path != "/" {
                Button("⬆︎ .. (übergeordnet)") { navigate(up: true) }
                    .listRowBackground(Theme.eventHorizon)
            }
            ForEach(files) { file in
                Button {
                    file.isDirectory ? navigate(into: file) : download(file)
                } label: {
                    HStack {
                        Image(systemName: file.isDirectory ? "folder.fill" : "doc")
                            .foregroundStyle(file.isDirectory ? Theme.accent : Theme.textSecondary)
                        Text(file.name).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if !file.isDirectory {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                                .font(.caption2).foregroundStyle(Theme.textFaint)
                        }
                    }
                }.listRowBackground(Theme.eventHorizon)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(Theme.danger).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .task(id: path) { await load() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
            if case let .success(url) = result { upload(url) }
        }
    }

    private func load() async {
        do { files = try await client.listFiles(path: path); error = nil }
        catch { self.error = "Fehler: \(error.localizedDescription)" }
    }
    private func navigate(into file: RemoteFile) { path = file.path }
    private func navigate(up: Bool) {
        path = (path as NSString).deletingLastPathComponent
        if path.isEmpty { path = "/" }
    }
    private func download(_ file: RemoteFile) {
        Task {
            guard let data = try? await client.download(path: file.path) else { return }
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try? data.write(to: dest)
        }
    }
    private func upload(_ url: URL) {
        Task {
            guard url.startAccessingSecurityScopedResource(), let data = try? Data(contentsOf: url) else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            let dest = (path as NSString).appendingPathComponent(url.lastPathComponent)
            try? await client.upload(data: data, toPath: dest)
            await load()
        }
    }
}
