# dist/ — fertige Builds

Hier legt der CI-Build (GitHub Actions, Workflow `ios-build.yml`) nach jedem
erfolgreichen Lauf automatisch die frisch gebaute App ab:

- **`Blackhole-unsigned.ipa`** — unsignierte iOS-App.

## Installieren

Die `.ipa` ist absichtlich **unsigniert**. Du signierst sie beim Installieren
mit deiner eigenen Apple-ID:

1. **Sideloadly** (Windows/Mac): https://sideloadly.io
2. iPhone anstecken, `Blackhole-unsigned.ipa` in Sideloadly ziehen.
3. Apple-ID eingeben → **Start** (Sideloadly signiert automatisch).
4. Am iPhone: *Einstellungen → Allgemein → VPN & Geräteverwaltung* → Profil vertrauen.

Läuft mit kostenloser Apple-ID 7 Tage, danach neu signieren.

> Kamera-Live-Video (RTSP) läuft echt inkl. Ton über MobileVLCKit. Netzwerk-Scan,
> Router-Anbindung und PC-Fernsteuerung funktionieren ebenfalls.
