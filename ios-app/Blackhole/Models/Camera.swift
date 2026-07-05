import Foundation

/// Eine Netzwerk-Kamera. Kameras werden per ONVIF/mDNS entdeckt und über RTSP
/// (Video + Audio) angesehen. Zwei-Wege-Audio (Mikrofon zurück zur Kamera)
/// wird über ONVIF-Backchannel unterstützt, sofern die Kamera das kann.
struct Camera: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var host: String
    var onvifPort: Int = 80
    var credentials: Credentials?

    /// Aufgelöste Stream-URLs (werden nach dem Login per ONVIF ermittelt).
    var mainStreamURL: URL?
    var subStreamURL: URL?

    var hasAudio: Bool = false
    var hasTwoWayAudio: Bool = false      // Backchannel / „Gegensprechen"
    var hasPTZ: Bool = false              // Schwenken/Neigen/Zoom

    struct Credentials: Hashable {
        var username: String
        var password: String
    }
}

/// PTZ-Bewegungsbefehle.
enum PTZCommand {
    case move(pan: Float, tilt: Float, zoom: Float)   // -1.0 … 1.0
    case stop
    case gotoPreset(Int)
}
