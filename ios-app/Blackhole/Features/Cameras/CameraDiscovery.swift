import Foundation
import Network

/// Findet ONVIF-/RTSP-Kameras im WLAN und ermittelt ihre Stream-URLs.
///
/// Ablauf einer echten Integration:
///  1. Discovery via WS-Discovery (UDP Multicast 239.255.255.250:3702) *oder*
///     via Bonjour `_onvif._tcp` / `_rtsp._tcp` (siehe NetworkScanner).
///  2. Login mit Benutzer/Passwort (ONVIF nutzt WS-Security UsernameToken).
///  3. `GetProfiles` + `GetStreamUri` → liefert die RTSP-URL je Profil.
///  4. Wiedergabe der RTSP-URL im Player (VLCKit), Audio inklusive.
///  5. Optional: `GetAudioOutputs` / Backchannel für Zwei-Wege-Audio, PTZ über
///     den ONVIF-PTZ-Service.
///
/// Diese Klasse kapselt Schritt 2–5 hinter einer sauberen API. Die konkreten
/// SOAP-Requests sind in `ONVIFClient` umrissen.
@MainActor
final class CameraDiscovery: ObservableObject {
    @Published private(set) var cameras: [Camera] = []

    /// Übernimmt Kamera-Kandidaten aus dem allgemeinen Netzwerk-Scan.
    func merge(from devices: [NetworkDevice]) {
        for dev in devices where dev.kind == .camera {
            guard let host = dev.ipAddress ?? dev.hostname else { continue }
            if cameras.contains(where: { $0.host == host }) { continue }
            let onvifPort = dev.services.first { $0.type.contains("onvif") }?.port ?? 80
            cameras.append(Camera(name: dev.name, host: host, onvifPort: onvifPort))
        }
    }

    func addManual(host: String, name: String) {
        guard !cameras.contains(where: { $0.host == host }) else { return }
        cameras.append(Camera(name: name.isEmpty ? host : name, host: host))
    }

    /// Loggt sich ein und löst die Stream-URLs auf.
    func connect(_ camera: Camera, username: String, password: String) async throws -> Camera {
        var cam = camera
        cam.credentials = .init(username: username, password: password)

        let client = ONVIFClient(host: cam.host, port: cam.onvifPort,
                                 username: username, password: password)
        let profiles = try await client.getProfiles()
        cam.mainStreamURL = profiles.first?.streamURL
        cam.subStreamURL = profiles.count > 1 ? profiles[1].streamURL : nil
        cam.hasAudio = profiles.first?.hasAudio ?? false
        cam.hasTwoWayAudio = try await client.hasAudioBackchannel()
        cam.hasPTZ = try await client.hasPTZ()

        if let idx = cameras.firstIndex(where: { $0.id == camera.id }) {
            cameras[idx] = cam
        }
        return cam
    }
}
