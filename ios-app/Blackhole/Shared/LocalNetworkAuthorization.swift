import Foundation
import Network

/// Löst den iOS „Local Network"-Berechtigungsdialog aus und meldet das Ergebnis.
///
/// Ab iOS 14 muss eine App die Erlaubnis haben, überhaupt mit anderen Geräten
/// im lokalen Netz zu sprechen. Der Dialog erscheint erst, wenn man tatsächlich
/// versucht, das Netz zu durchsuchen. Wir starten dazu kurz einen Bonjour-Browser
/// und einen -Dienst; sobald wir Ergebnisse (oder ein Timeout) sehen, gilt der
/// Zugriff als geklärt.
///
/// Voraussetzung: In der Info.plist müssen `NSLocalNetworkUsageDescription` und
/// `NSBonjourServices` gesetzt sein (siehe Resources/Info.plist).
final class LocalNetworkAuthorization: NSObject {
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var continuation: CheckedContinuation<Bool, Never>?

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            start()
        }
    }

    private func start() {
        // Ein Dummy-Listener, damit iOS uns als „Netzteilnehmer" behandelt.
        let listener = try? NWListener(using: NWParameters(tls: nil, tcp: .init()))
        listener?.service = NWListener.Service(name: UUID().uuidString, type: "_blackhole._tcp")
        listener?.newConnectionHandler = { _ in }
        listener?.start(queue: .main)
        self.listener = listener

        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_blackhole._tcp", domain: nil), using: params)
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.finish(true)
            case .failed, .cancelled:
                self?.finish(false)
            case .waiting:
                // Meist „Not authorized" → Nutzer hat abgelehnt.
                self?.finish(false)
            default:
                break
            }
        }
        browser.start(queue: .main)
        self.browser = browser

        // Sicherheits-Timeout.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.finish(true)
        }
    }

    private func finish(_ authorized: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        browser?.cancel()
        listener?.cancel()
        continuation.resume(returning: authorized)
    }
}
