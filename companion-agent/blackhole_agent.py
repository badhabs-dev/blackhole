#!/usr/bin/env python3
"""
Blackhole Companion Agent
=========================

Kleiner lokaler Dienst, der auf deinem eigenen Rechner (Windows/macOS/Linux)
läuft und der Blackhole-iPhone-App erlaubt, DIESEN Rechner zu steuern:
Bildschirm ansehen, Webcam ansehen und Dateien hin- und herschieben.

Warum nötig? iOS darf nicht von außen auf einen fremden Rechner zugreifen –
der Rechner selbst muss den Zugriff anbieten und erlauben. Genau das macht
dieser Agent, und zwar nur nach PIN-Kopplung.

Sicherheit:
  * Erreichbar nur im lokalen Netz.
  * Erster Zugriff erfordert den beim Start angezeigten PIN → App erhält Token.
  * Alle weiteren Anfragen brauchen dieses Token.

Abhängigkeiten (optional – Features werden sonst als „nicht verfügbar" gemeldet):
    pip install mss pillow opencv-python zeroconf
Ohne Extras funktionieren Kopplung + Dateibrowser trotzdem.

Start:
    python blackhole_agent.py
"""

import base64
import json
import os
import secrets
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = 8765

# ---- Optionale Fähigkeiten erkennen -----------------------------------------
try:
    import mss                     # Bildschirmaufnahme
    from PIL import Image
    import io
    HAS_SCREEN = True
except Exception:
    HAS_SCREEN = False

try:
    import cv2                     # Webcam
    HAS_WEBCAM = True
except Exception:
    HAS_WEBCAM = False


class State:
    """Hält PIN und ausgegebenes Token."""
    pin = f"{secrets.randbelow(1000000):06d}"
    token = None


def jpeg_from_rgb(rgb_bytes, size):
    img = Image.frombytes("RGB", size, rgb_bytes)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=60)
    return buf.getvalue()


class Handler(BaseHTTPRequestHandler):
    # ---- Hilfen -------------------------------------------------------------
    def _json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        # Token aus Header ODER Query (?token= für MJPEG-<img>-Streams).
        auth = self.headers.get("Authorization", "")
        q = parse_qs(urlparse(self.path).query)
        token = q.get("token", [None])[0]
        if auth.startswith("Bearer "):
            token = auth[7:]
        return State.token is not None and token == State.token

    def log_message(self, *args):
        pass  # ruhig halten

    # ---- Routen -------------------------------------------------------------
    def do_POST(self):
        route = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b""

        if route == "/pair":
            try:
                pin = json.loads(raw).get("pin")
            except Exception:
                pin = None
            if pin == State.pin:
                State.token = secrets.token_hex(16)
                print(f"[Agent] Gekoppelt. Token vergeben.")
                return self._json({"token": State.token})
            return self._json({"error": "PIN falsch"}, 403)

        if not self._authorized():
            return self._json({"error": "nicht autorisiert"}, 401)

        if route == "/upload":
            q = parse_qs(urlparse(self.path).query)
            path = q.get("path", ["/"])[0]
            try:
                with open(path, "wb") as f:
                    f.write(raw)
                return self._json({"ok": True})
            except Exception as e:
                return self._json({"error": str(e)}, 500)

        self._json({"error": "unbekannt"}, 404)

    def do_GET(self):
        route = urlparse(self.path).path
        q = parse_qs(urlparse(self.path).query)

        if route == "/info":
            if not self._authorized():
                return self._json({"error": "nicht autorisiert"}, 401)
            return self._json({
                "name": socket.gethostname(),
                "os": f"{os.name}",
                "hasWebcam": HAS_WEBCAM,
                "hasScreen": HAS_SCREEN,
                "hasFiles": True,
            })

        if not self._authorized():
            return self._json({"error": "nicht autorisiert"}, 401)

        if route == "/files":
            path = q.get("path", ["/"])[0]
            try:
                entries = []
                for name in sorted(os.listdir(path)):
                    full = os.path.join(path, name)
                    is_dir = os.path.isdir(full)
                    entries.append({
                        "name": name,
                        "path": full,
                        "isDirectory": is_dir,
                        "size": 0 if is_dir else os.path.getsize(full),
                    })
                return self._json(entries)
            except Exception as e:
                return self._json({"error": str(e)}, 500)

        if route == "/download":
            path = q.get("path", [""])[0]
            try:
                with open(path, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            except Exception as e:
                self._json({"error": str(e)}, 500)
            return

        if route == "/screen" and HAS_SCREEN:
            return self._stream_screen()
        if route == "/webcam" and HAS_WEBCAM:
            return self._stream_webcam()

        self._json({"error": "nicht verfügbar"}, 404)

    # ---- MJPEG-Streams ------------------------------------------------------
    def _start_mjpeg(self):
        self.send_response(200)
        self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
        self.end_headers()

    def _send_frame(self, jpeg):
        self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\n")
        self.wfile.write(f"Content-Length: {len(jpeg)}\r\n\r\n".encode())
        self.wfile.write(jpeg)
        self.wfile.write(b"\r\n")

    def _stream_screen(self):
        self._start_mjpeg()
        with mss.mss() as sct:
            monitor = sct.monitors[1]
            try:
                while True:
                    shot = sct.grab(monitor)
                    jpeg = jpeg_from_rgb(shot.rgb, shot.size)
                    self._send_frame(jpeg)
                    time.sleep(1 / 10)   # ~10 FPS
            except (BrokenPipeError, ConnectionResetError):
                pass

    def _stream_webcam(self):
        self._start_mjpeg()
        cap = cv2.VideoCapture(0)
        try:
            while True:
                ok, frame = cap.read()
                if not ok:
                    break
                ok, jpeg = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 60])
                if ok:
                    self._send_frame(jpeg.tobytes())
                time.sleep(1 / 15)
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            cap.release()


def advertise_bonjour():
    """Kündigt den Agent per Bonjour an, damit die App ihn automatisch findet."""
    try:
        from zeroconf import Zeroconf, ServiceInfo
        ip = socket.gethostbyname(socket.gethostname())
        info = ServiceInfo(
            "_blackhole-agent._tcp.local.",
            f"{socket.gethostname()}._blackhole-agent._tcp.local.",
            addresses=[socket.inet_aton(ip)],
            port=PORT,
            properties={"name": socket.gethostname()},
        )
        Zeroconf().register_service(info)
        print(f"[Agent] Bonjour angekündigt als _blackhole-agent._tcp auf {ip}")
    except Exception:
        print("[Agent] Bonjour nicht verfügbar (pip install zeroconf) – App per IP hinzufügen.")


def main():
    print("=" * 48)
    print("  Blackhole Companion Agent")
    print(f"  Port:        {PORT}")
    print(f"  Bildschirm:  {'ja' if HAS_SCREEN else 'nein (pip install mss pillow)'}")
    print(f"  Webcam:      {'ja' if HAS_WEBCAM else 'nein (pip install opencv-python)'}")
    print(f"\n  >>> KOPPLUNGS-PIN:  {State.pin}  <<<\n")
    print("  Diesen PIN in der Blackhole-App eingeben.")
    print("=" * 48)
    threading.Thread(target=advertise_bonjour, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
