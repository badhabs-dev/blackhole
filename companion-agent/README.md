# Blackhole Companion Agent

Damit die Blackhole-iPhone-App deinen **eigenen** Rechner fernsteuern kann
(Bildschirm ansehen, Webcam ansehen, Dateien schieben), muss auf diesem Rechner
ein kleiner Dienst laufen. iOS darf nicht von außen in einen fremden Rechner
greifen – der Rechner selbst bietet den Zugriff an, und zwar nur nach
PIN-Kopplung im lokalen Netz.

## Start

```bash
# Optionale Extras für Screen/Webcam/Auto-Discovery:
pip install -r requirements.txt

python blackhole_agent.py
```

Beim Start zeigt der Agent einen 6-stelligen **Kopplungs-PIN**. Diesen in der
Blackhole-App unter „Fernsteuerung" beim Koppeln eingeben. Danach erhält die App
ein Token und kann zugreifen.

Ohne die Extra-Pakete laufen Kopplung und Dateibrowser trotzdem; Bildschirm/
Webcam melden sich dann als „nicht verfügbar".

## API (für Neugierige / eigene Clients)

| Methode | Pfad | Zweck |
|---|---|---|
| POST | `/pair` `{pin}` | Kopplung → gibt `{token}` zurück |
| GET | `/info` | Name, OS, Fähigkeiten |
| GET | `/files?path=` | Verzeichnis auflisten |
| GET | `/download?path=` | Datei herunterladen |
| POST | `/upload?path=` | Datei hochladen (Body = Inhalt) |
| GET | `/screen` | MJPEG-Stream des Bildschirms |
| GET | `/webcam` | MJPEG-Stream der Webcam |

Alle Routen außer `/pair` verlangen `Authorization: Bearer <token>` (bzw.
`?token=` für die `<img>`-MJPEG-Streams).

## Sicherheit & Haftung

- Nur im lokalen Netz erreichbar; kein Cloud-Zugang.
- Zugriff erst nach PIN-Kopplung, jede weitere Anfrage braucht das Token.
- Setze das **nur auf deinen eigenen Rechnern** ein. Der Agent gibt vollen
  Datei- und Bildschirmzugriff frei – behandle das Token wie ein Passwort.
- Für den Produktivbetrieb empfiehlt sich zusätzlich TLS und eine Einschränkung
  auf bekannte Client-Geräte.
