#!/usr/bin/env python3
"""Claude-Usage-Poller: fragt periodisch das Abo-Limit ab und stellt es im LAN bereit."""
import json
import os
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONFIG_DIR = os.environ.get("CLAUDE_CONFIG_DIR", os.path.expanduser("~/.claude"))
CRED_FILE = os.environ.get("CRED_FILE", os.path.join(CONFIG_DIR, ".credentials.json"))
POLL_SECONDS = max(60, int(os.environ.get("POLL_SECONDS", "300")))
PORT = int(os.environ.get("PORT", "8088"))
USAGE_URL = os.environ.get("USAGE_URL", "https://api.anthropic.com/api/oauth/usage")
TOKEN_URLS = [u.strip() for u in os.environ.get(
    "TOKEN_URL",
    "https://platform.claude.com/v1/oauth/token,https://console.anthropic.com/v1/oauth/token",
).split(",") if u.strip()]
CLIENT_ID = os.environ.get("CLIENT_ID", "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
USER_AGENT = os.environ.get("USER_AGENT", "claude-code/2.0.0")
HERE = os.path.dirname(os.path.abspath(__file__))

state = {"ok": False, "error": "Noch keine Daten", "data": None, "fetched_at": None}
lock = threading.Lock()


def now_ms():
    return int(time.time() * 1000)


def load_creds():
    with open(CRED_FILE, encoding="utf-8") as f:
        return json.load(f)


def save_creds(creds):
    tmp = CRED_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(creds, f)
    os.chmod(tmp, 0o600)
    os.replace(tmp, CRED_FILE)


def http_json(url, headers, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers,
                                 method="POST" if data is not None else "GET")
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode())


class RefreshError(Exception):
    pass


def refresh_token(creds):
    oauth = creds["claudeAiOauth"]
    body = {"grant_type": "refresh_token", "refresh_token": oauth["refreshToken"],
            "client_id": CLIENT_ID}
    resp, last = None, None
    for url in TOKEN_URLS:
        try:
            resp = http_json(url, {"Content-Type": "application/json",
                                   "User-Agent": USER_AGENT}, body)
            break
        except urllib.error.HTTPError as e:
            last = f"HTTP {e.code} von {url}"
            print(f"Token-Refresh fehlgeschlagen: {last}", flush=True)
            if e.code not in (404, 405):
                break  # Endpoint existiert, Token abgelehnt -> kein weiterer Versuch
    if resp is None:
        raise RefreshError(last or "kein Token-Endpoint konfiguriert")
    oauth["accessToken"] = resp["access_token"]
    if resp.get("refresh_token"):
        oauth["refreshToken"] = resp["refresh_token"]
    if resp.get("expires_in"):
        oauth["expiresAt"] = now_ms() + int(resp["expires_in"]) * 1000
    save_creds(creds)
    print("Token erneuert", flush=True)


def fetch_usage():
    creds = load_creds()
    oauth = creds["claudeAiOauth"]
    if oauth.get("expiresAt", 0) - 120_000 < now_ms():
        refresh_token(creds)

    def call():
        return http_json(USAGE_URL, {
            "Authorization": f"Bearer {oauth['accessToken']}",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
        })

    try:
        return call()
    except urllib.error.HTTPError as e:
        if e.code == 401:
            refresh_token(creds)
            return call()
        raise


def poll_once():
    try:
        data = fetch_usage()
        result = {"ok": True, "error": None, "data": data}
    except FileNotFoundError:
        result = {"ok": False, "error": "Nicht angemeldet – im Container 'claude' starten und /login ausführen."}
    except KeyError:
        result = {"ok": False, "error": "Credentials unvollständig – bitte neu anmelden (/login)."}
    except RefreshError as e:
        result = {"ok": False, "error": f"Token-Erneuerung fehlgeschlagen ({e}) – ggf. neu anmelden (/login)."}
    except urllib.error.HTTPError as e:
        result = {"ok": False, "error": f"Usage-API-Fehler HTTP {e.code} von {e.url}."}
    except Exception as e:  # Netzwerk etc.
        result = {"ok": False, "error": f"Abruf fehlgeschlagen: {e}"}
    result["fetched_at"] = datetime.now(timezone.utc).isoformat()
    with lock:
        if not result["ok"] and state.get("data"):
            # letzte gültige Daten behalten, Fehler zusätzlich anzeigen
            result["data"] = state["data"]
            result["data_at"] = state.get("data_at")
        elif result["ok"]:
            result["data_at"] = result["fetched_at"]
        state.clear()
        state.update(result)
    print(f"{result['fetched_at']} ok={result['ok']} {result.get('error') or ''}", flush=True)


def poll_loop():
    while True:
        poll_once()
        time.sleep(POLL_SECONDS)


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            with open(os.path.join(HERE, "index.html"), "rb") as f:
                self._send(200, f.read(), "text/html; charset=utf-8")
        elif path == "/api/usage":
            with lock:
                body = json.dumps(state | {"poll_seconds": POLL_SECONDS}).encode()
            self._send(200, body, "application/json")
        elif path in ("/icon.svg", "/favicon.svg"):
            with open(os.path.join(HERE, "icon.svg"), "rb") as f:
                self._send(200, f.read(), "image/svg+xml")
        elif path == "/healthz":
            self._send(200, b"ok", "text/plain")
        else:
            self._send(404, b"not found", "text/plain")

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    threading.Thread(target=poll_loop, daemon=True).start()
    print(f"Lausche auf Port {PORT}, Abruf alle {POLL_SECONDS}s", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
