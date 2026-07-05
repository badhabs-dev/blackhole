# blackhole

Netzwerk-Debugging & DIY-Smarthome fürs eigene WLAN.

- **`ios-app/`** — SwiftUI-iPhone-App: Geräte im WLAN finden, Kameras
  ansehen/hören (ONVIF/RTSP), Router steuern (kicken/drosseln via FRITZ!Box &
  OpenWrt), Elternkontrolle und Fernsteuerung eigener Rechner. Siehe
  [`ios-app/README.md`](ios-app/README.md) — dort steht ehrlich, was auf iOS
  direkt geht und was eine Router-API bzw. einen Companion-Agent braucht.
- **`companion-agent/`** — kleiner Dienst für den eigenen PC/Mac/Linux, damit die
  App Bildschirm, Webcam und Dateien fernsteuern kann (nach PIN-Kopplung).
- **`index.html`** — Projekt-Website.

> ⚠️ Nur fürs eigene Netzwerk und eigene Geräte. Eingriffe wie Kicken, Drosseln
> oder Fernsteuern setzen voraus, dass dir das Netz/Gerät gehört.
