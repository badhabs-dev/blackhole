import Foundation

/// Minimaler ONVIF-Client (SOAP über HTTP).
///
/// ONVIF ist der Industriestandard für IP-Kameras. Die App spricht mit der
/// Kamera per SOAP/XML. Hier sind die relevanten Aufrufe umrissen; die
/// XML-Serialisierung ist bewusst kompakt gehalten. Für den Produktivbetrieb
/// empfiehlt sich eine getestete ONVIF-Bibliothek, aber die Struktur zeigt
/// exakt, welche Requests nötig sind.
///
/// Authentifizierung: WS-Security `UsernameToken` mit
/// `PasswordDigest = Base64( SHA1( Nonce + Created + Password ) )`.
struct ONVIFClient {
    let host: String
    let port: Int
    let username: String
    let password: String

    struct Profile {
        var token: String
        var streamURL: URL?
        var hasAudio: Bool
    }

    private var deviceServiceURL: URL {
        URL(string: "http://\(host):\(port)/onvif/device_service")!
    }

    // MARK: - Öffentliche API

    /// `GetProfiles` + `GetStreamUri` je Profil.
    func getProfiles() async throws -> [Profile] {
        let body = soapEnvelope(
            body: #"<trt:GetProfiles xmlns:trt="http://www.onvif.org/ver10/media/wsdl"/>"#
        )
        let xml = try await send(to: mediaURL(), soap: body, action: "GetProfiles")
        let tokens = extractAll(tag: "token", in: xml)

        var result: [Profile] = []
        for token in tokens {
            let streamURL = try await getStreamURI(profileToken: token)
            let hasAudio = xml.contains("AudioEncoderConfiguration")
            result.append(Profile(token: token, streamURL: streamURL, hasAudio: hasAudio))
        }
        return result
    }

    func getStreamURI(profileToken: String) async throws -> URL? {
        let inner = """
        <trt:GetStreamUri xmlns:trt="http://www.onvif.org/ver10/media/wsdl">
          <trt:StreamSetup>
            <tt:Stream xmlns:tt="http://www.onvif.org/ver10/schema">RTP-Unicast</tt:Stream>
            <tt:Transport xmlns:tt="http://www.onvif.org/ver10/schema"><tt:Protocol>RTSP</tt:Protocol></tt:Transport>
          </trt:StreamSetup>
          <trt:ProfileToken>\(profileToken)</trt:ProfileToken>
        </trt:GetStreamUri>
        """
        let xml = try await send(to: mediaURL(), soap: soapEnvelope(body: inner), action: "GetStreamUri")
        guard var uri = extractAll(tag: "Uri", in: xml).first else { return nil }
        // RTSP-URL mit Zugangsdaten anreichern, damit der Player sich anmelden kann.
        if let scheme = uri.range(of: "rtsp://") {
            uri.replaceSubrange(scheme, with: "rtsp://\(username):\(password)@")
        }
        return URL(string: uri)
    }

    func hasPTZ() async throws -> Bool {
        let xml = try await capabilities()
        return xml.contains("PTZ")
    }

    func hasAudioBackchannel() async throws -> Bool {
        let xml = try await capabilities()
        return xml.range(of: "AudioOutputs", options: .caseInsensitive) != nil
    }

    /// Sendet einen PTZ-Bewegungsbefehl (kontinuierlich, bis `stop`).
    func sendPTZ(_ command: PTZCommand, profileToken: String) async throws {
        let inner: String
        switch command {
        case let .move(pan, tilt, zoom):
            inner = """
            <tptz:ContinuousMove xmlns:tptz="http://www.onvif.org/ver20/ptz/wsdl">
              <tptz:ProfileToken>\(profileToken)</tptz:ProfileToken>
              <tptz:Velocity>
                <tt:PanTilt xmlns:tt="http://www.onvif.org/ver10/schema" x="\(pan)" y="\(tilt)"/>
                <tt:Zoom xmlns:tt="http://www.onvif.org/ver10/schema" x="\(zoom)"/>
              </tptz:Velocity>
            </tptz:ContinuousMove>
            """
        case .stop:
            inner = """
            <tptz:Stop xmlns:tptz="http://www.onvif.org/ver20/ptz/wsdl">
              <tptz:ProfileToken>\(profileToken)</tptz:ProfileToken>
              <tptz:PanTilt>true</tptz:PanTilt><tptz:Zoom>true</tptz:Zoom>
            </tptz:Stop>
            """
        case let .gotoPreset(n):
            inner = """
            <tptz:GotoPreset xmlns:tptz="http://www.onvif.org/ver20/ptz/wsdl">
              <tptz:ProfileToken>\(profileToken)</tptz:ProfileToken>
              <tptz:PresetToken>\(n)</tptz:PresetToken>
            </tptz:GotoPreset>
            """
        }
        _ = try await send(to: ptzURL(), soap: soapEnvelope(body: inner), action: "PTZ")
    }

    // MARK: - Intern

    private func capabilities() async throws -> String {
        let inner = #"<tds:GetCapabilities xmlns:tds="http://www.onvif.org/ver10/device/wsdl"><tds:Category>All</tds:Category></tds:GetCapabilities>"#
        return try await send(to: deviceServiceURL, soap: soapEnvelope(body: inner), action: "GetCapabilities")
    }

    private func mediaURL() -> URL { URL(string: "http://\(host):\(port)/onvif/media_service")! }
    private func ptzURL() -> URL { URL(string: "http://\(host):\(port)/onvif/ptz_service")! }

    private func send(to url: URL, soap: String, action: String) async throws -> String {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/soap+xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = soap.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Baut einen SOAP-Envelope inkl. WS-Security-Header.
    private func soapEnvelope(body: String) -> String {
        let nonce = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let created = ISO8601DateFormatter().string(from: Date())
        let digest = passwordDigest(nonce: nonce, created: created)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
          <s:Header>
            <Security xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
              <UsernameToken>
                <Username>\(username)</Username>
                <Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">\(digest)</Password>
                <Nonce>\(nonce.base64EncodedString())</Nonce>
                <Created xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">\(created)</Created>
              </UsernameToken>
            </Security>
          </s:Header>
          <s:Body>\(body)</s:Body>
        </s:Envelope>
        """
    }

    private func passwordDigest(nonce: Data, created: String) -> String {
        var data = nonce
        data.append(created.data(using: .utf8)!)
        data.append(password.data(using: .utf8)!)
        return Data(SHA1.hash(data)).base64EncodedString()
    }

    /// Sehr einfache Extraktion von Elementinhalten (ausreichend für die Demo).
    private func extractAll(tag: String, in xml: String) -> [String] {
        var results: [String] = []
        var searchRange = xml.startIndex..<xml.endIndex
        while let open = xml.range(of: "<\(tag)", range: searchRange),
              let gt = xml.range(of: ">", range: open.upperBound..<xml.endIndex),
              let close = xml.range(of: "</\(tag)>", range: gt.upperBound..<xml.endIndex) {
            results.append(String(xml[gt.upperBound..<close.lowerBound]))
            searchRange = close.upperBound..<xml.endIndex
        }
        return results
    }
}
