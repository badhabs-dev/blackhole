# Blackhole — iPhone-App für Netzwerk-Debugging & DIY-Smarthome

Eine SwiftUI-App fürs iPhone, um das **eigene** WLAN zu erkunden und zu
verwalten: Geräte finden, Kameras ansehen/hören, den Router steuern
(kicken/drosseln), Elternkontrolle einrichten und eigene Rechner fernsteuern.

> ⚠️ **Nur für dein eigenes Netzwerk und deine eigenen Geräte.** Fremde
> WLANs, Kameras oder Rechner ohne Erlaubnis zu manipulieren ist illegal.
> Alle eingreifenden Funktionen (kicken, drosseln, fernsteuern) setzen voraus,
> dass dir das Netz bzw. Gerät gehört und du die Zugangsdaten besitzt.

## Was auf einem iPhone wirklich geht – und was nicht

iOS läuft in einer strengen Sandbox. Deshalb ist die App ehrlich aufgeteilt in
Dinge, die die App **selbst** kann, und Dinge, die zwingend eine **Router-API**
oder einen **Companion-Agent** auf dem Zielgerät brauchen:

| Feature | Umsetzung | Status |
|---|---|---|
| Geräte im WLAN + IP anzeigen | Bonjour/mDNS + gezielter TCP-Subnetz-Scan | ✅ direkt in der App |
| Kameras finden, Bild + Ton | ONVIF-Discovery + RTSP (via MobileVLCKit) | ✅ mit Standard-Kameras |
| Kamera: Gegensprechen (Mikro) | ONVIF-Audio-Backchannel | ✅ falls Kamera es kann |
| Kamera: schwenken/zoomen (PTZ) | ONVIF-PTZ-Service | ✅ falls Kamera es kann |
| MAC-Adressen aller Geräte | iOS-Sandbox verbietet ARP-Zugriff | ⚠️ nur über Router-API |
| Geräte kicken / bannen | Router-API (FRITZ!Box TR-064, OpenWrt ubus) | ⚠️ Router muss es können |
| Bandbreite boosten / drosseln | Router-QoS (OpenWrt `tc`) | ⚠️ Router muss es können |
| Elternkontrolle: Zeitfenster/Limits | Router-Zeitprofile | ⚠️ über Router |
| Elternkontrolle: Web/Apps blocken | Router-DNS-Filter, bzw. Apple ScreenTime für eigene Familiengeräte | ⚠️ über Router/Apple |
| Eigenen PC: Screen/Webcam/Dateien | Blackhole Companion Agent (siehe `../companion-agent`) | ⚠️ Agent auf PC nötig |

Kurz: Eine iOS-App kann keine fremden Pakete manipulieren und nicht in andere
Rechner „hineingreifen". Sie kann aber der **Fernbedienung** für deinen Router
und deine eigenen Geräte sein – und genau so ist Blackhole gebaut.

## Aufbau

```
ios-app/
├── project.yml                     # XcodeGen: erzeugt das Xcode-Projekt
└── Blackhole/
    ├── App/                        # Einstieg, Navigation, Theme
    ├── Models/                     # NetworkDevice, Camera
    ├── Shared/                     # Local-Network-Berechtigung, IP-Helfer, SHA1
    ├── Features/
    │   ├── Network/                # Scanner (Bonjour + TCP-Sweep) + Views
    │   ├── Cameras/                # ONVIF-Client, RTSP-Player, PTZ, Views
    │   ├── Router/                 # RouterController + FRITZ!Box/OpenWrt-Backends
    │   ├── Parental/               # Regel-Engine + Editor
    │   └── Remote/                 # Companion-Client, MJPEG-Viewer, Dateibrowser
    └── Resources/Info.plist        # Berechtigungen (Local Network, Mikro, …)
```

## Bauen & aufs iPhone bringen

Die App braucht **einen Mac mit Xcode** (so verlangt es Apple für iOS-Apps).

```bash
brew install xcodegen           # einmalig
cd ios-app
xcodegen generate               # erzeugt Blackhole.xcodeproj
open Blackhole.xcodeproj
```

Dann in Xcode:
1. Bei „Signing & Capabilities" dein Apple-Developer-Team wählen (ein kostenloses
   Apple-ID-Konto reicht für das Laden auf dein eigenes iPhone).
2. Für **echte RTSP-Wiedergabe**: das Swift-Package `MobileVLCKit` hinzufügen und
   in `VideoStreaming.swift` die auskommentierten Zeilen aktivieren. Ohne das
   baut die App, zeigt Streams aber nur als Platzhalter.
3. iPhone anstecken, Ziel wählen, **Run**.

## Der Companion Agent (für PC-Fernsteuerung)

Die Fernsteuerung eigener Rechner braucht das kleine Programm in
`../companion-agent`. Es läuft auf dem PC/Mac/Linux und bietet Bildschirm,
Webcam und Dateizugriff – erst nach PIN-Kopplung. Details dort im README.

## Datenschutz

- Alle Zugangsdaten (Kamera, Router, Agent-Token) bleiben lokal (Keychain
  empfohlen) und werden nur direkt mit dem jeweiligen Gerät im WLAN gesprochen.
- Es gibt keinen Cloud-Server; die App funktioniert komplett offline im LAN.
