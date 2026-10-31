#!/usr/bin/env python3
"""
Grafana Alerting webhook -> Telegram: one message per alert - panel image with the text as its caption.

The built-in Telegram integration of Grafana 11+/12 sends the text (sendMessage) and the image (sendPhoto) as
separate posts, a photo caption is not supported. The relay accepts the webhook, renders the alert panel via the
Grafana API (dashboardUID/panelId are taken from panelURL) and sends sendPhoto with a caption. No panel or the
render failed - plain sendMessage.

The webhook is answered with 200 right away, delivery goes from a queue in one thread: a slow render or a 429
from Telegram does not cause webhook timeouts and retries on the Grafana side (= duplicates).

stdlib only. Settings - environment variables (see CONFIG), optionally from the file in RELAY_ENV_FILE.
"""
import base64
import html
import json
import logging
import os
import queue
import re
import ssl
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def load_env_file(path: str) -> None:
    """KEY=VALUE lines (docker env_file format, no quoting) -> os.environ; keeps secrets out of `docker inspect`."""
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if line.strip() and not line.lstrip().startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value)


if os.environ.get("RELAY_ENV_FILE"):
    load_env_file(os.environ["RELAY_ENV_FILE"])

CONFIG = {
    "listen": os.environ.get("RELAY_LISTEN", "0.0.0.0:8080"),
    "auth_token": os.environ.get("RELAY_AUTH_TOKEN", ""),           # Bearer from Grafana (authorization_credentials)
    "tg_token": os.environ["TG_BOT_TOKEN"],
    "tg_chat_id": os.environ["TG_CHAT_ID"],
    "tg_thread_id": os.environ.get("TG_THREAD_ID", ""),
    "tg_api_url": os.environ.get("TG_API_URL", "https://api.telegram.org").rstrip("/"),
    "grafana_url": os.environ.get("GRAFANA_URL", "https://127.0.0.1:443/graph").rstrip("/"),
    "grafana_token": os.environ.get("GRAFANA_TOKEN", ""),           # service account (Viewer), takes precedence over user/password
    "grafana_user": os.environ.get("GRAFANA_USER", ""),
    "grafana_password": os.environ.get("GRAFANA_PASSWORD", ""),
    "grafana_insecure": os.environ.get("GRAFANA_INSECURE_TLS", "1") == "1",
    "render_width": int(os.environ.get("RENDER_WIDTH", "1000")),
    "render_height": int(os.environ.get("RENDER_HEIGHT", "500")),
    "render_range": os.environ.get("RENDER_RANGE", "1h"),
    "render_tz": os.environ.get("RENDER_TZ", "UTC"),
    "render_timeout": int(os.environ.get("RENDER_TIMEOUT", "60")),
    "resolved_images": os.environ.get("RESOLVED_IMAGES", "1") == "1",
    "link_text": os.environ.get("LINK_TEXT", "Open graph"),
}
CAPTION_LIMIT = 1024   # Telegram limit for a photo caption
MESSAGE_LIMIT = 4096
HOST_PREFIX_RE = re.compile(r"^(?P<host>\[[^\]]+\])\s+(?P<text>.+)$", re.S)
PANEL_RE = re.compile(r"/d/(?P<uid>[^/?#]+).*?[?&]viewPanel=(?:panel-)?(?P<panel>\d+)")

log = logging.getLogger("relay")
jobs: "queue.Queue[dict]" = queue.Queue()


def grafana_render(panel_url: str) -> bytes | None:
    m = PANEL_RE.search(panel_url or "")
    if not m:
        return None
    query = urllib.parse.urlencode({
        "orgId": 1, "panelId": m["panel"], "width": CONFIG["render_width"], "height": CONFIG["render_height"],
        "from": f"now-{CONFIG['render_range']}", "to": "now", "tz": CONFIG["render_tz"],
    })
    req = urllib.request.Request(f"{CONFIG['grafana_url']}/render/d-solo/{m['uid']}/_?{query}")
    if CONFIG["grafana_token"]:
        req.add_header("Authorization", f"Bearer {CONFIG['grafana_token']}")
    elif CONFIG["grafana_user"]:
        creds = base64.b64encode(f"{CONFIG['grafana_user']}:{CONFIG['grafana_password']}".encode()).decode()
        req.add_header("Authorization", f"Basic {creds}")
    ctx = ssl._create_unverified_context() if CONFIG["grafana_insecure"] else None
    try:
        with urllib.request.urlopen(req, timeout=CONFIG["render_timeout"], context=ctx) as resp:
            if resp.headers.get_content_type() == "image/png":
                return resp.read()
            log.warning("render %s: unexpected content type %s", panel_url, resp.headers.get_content_type())
    except (urllib.error.URLError, TimeoutError) as e:
        log.warning("render %s failed: %s", panel_url, e)
    return None


def format_alert(alert: dict) -> str:
    labels, ann = alert.get("labels", {}), alert.get("annotations", {})
    firing = alert.get("status") == "firing"
    name = labels.get("rulename") or labels.get("alertname", "")
    kind = {"DatasourceNoData": " — <b>No Data</b>", "DatasourceError": " — <b>Error</b>"}.get(labels.get("alertname"), "")
    # "[host] TEXT" -> "[host]" and TEXT on a new line
    m = HOST_PREFIX_RE.match(name)
    name = f"{m['host']}\n{m['text']}" if m else name
    lines = [f"{'🔴 <b>[Alerting]</b>' if firing else '🟢 <b>[OK]</b>'} {html.escape(name)}{kind}"]
    if ann.get("summary"):
        lines.append(html.escape(ann["summary"]))
    if ann.get("description"):
        lines.append(html.escape(ann["description"]))
    link = alert.get("panelURL") or alert.get("dashboardURL") or alert.get("generatorURL")
    if link:
        lines.append(f'<a href="{html.escape(link, quote=True)}">{html.escape(CONFIG["link_text"])}</a>')
    return "\n".join(lines)


def fit(text: str, limit: int) -> str:
    """Truncate by lines, so that an HTML tag is not cut."""
    if len(text) <= limit:
        return text
    out = ""
    for line in text.split("\n"):
        if len(out) + len(line) + 2 > limit:
            break
        out += line + "\n"
    return out.rstrip("\n") + "\n…"


def telegram(method: str, fields: dict, photo: bytes | None = None) -> None:
    fields = {"chat_id": CONFIG["tg_chat_id"], "parse_mode": "HTML", **fields}
    if CONFIG["tg_thread_id"]:
        fields["message_thread_id"] = CONFIG["tg_thread_id"]
    boundary = uuid.uuid4().hex
    body = b""
    for k, v in fields.items():
        body += f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
    if photo is not None:
        body += (f'--{boundary}\r\nContent-Disposition: form-data; name="photo"; filename="panel.png"\r\n'
                 f"Content-Type: image/png\r\n\r\n").encode() + photo + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    url = f"{CONFIG['tg_api_url']}/bot{CONFIG['tg_token']}/{method}"
    for attempt in range(5):
        req = urllib.request.Request(url, data=body, headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
        try:
            with urllib.request.urlopen(req, timeout=30):
                return
        except urllib.error.HTTPError as e:
            info = json.loads(e.read() or b"{}")
            retry = info.get("parameters", {}).get("retry_after")
            if e.code == 429 and retry:
                log.warning("telegram 429, retry after %ss", retry)
                time.sleep(retry + 1)
                continue
            raise RuntimeError(f"telegram {method}: {e.code} {info.get('description')}") from None
        except urllib.error.URLError as e:
            log.warning("telegram %s: %s (attempt %d)", method, e, attempt + 1)
            time.sleep(2 ** attempt)
    raise RuntimeError(f"telegram {method}: giving up")


def deliver(alert: dict) -> None:
    text = format_alert(alert)
    image = None
    if alert.get("status") == "firing" or CONFIG["resolved_images"]:
        image = grafana_render(alert.get("panelURL", ""))
    if image:
        telegram("sendPhoto", {"caption": fit(text, CAPTION_LIMIT)}, image)
    else:
        telegram("sendMessage", {"text": fit(text, MESSAGE_LIMIT), "disable_web_page_preview": "true"})
    log.info("sent %s %s (image=%s, link=%s)", alert.get("status"),
             alert.get("labels", {}).get("rulename") or alert.get("labels", {}).get("alertname"), bool(image),
             alert.get("panelURL") or alert.get("dashboardURL") or alert.get("generatorURL"))


def worker() -> None:
    while True:
        alert = jobs.get()
        try:
            deliver(alert)
        except Exception:  # one failed delivery must not stop the queue
            log.exception("delivery failed")
        finally:
            jobs.task_done()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        log.debug(fmt, *args)

    def reply(self, code: int, body: str = "") -> None:
        self.send_response(code)
        self.end_headers()
        self.wfile.write(body.encode())

    def do_GET(self):
        self.reply(200, "ok") if self.path == "/healthz" else self.reply(404)

    def do_POST(self):
        if self.path != "/alert":
            return self.reply(404)
        if CONFIG["auth_token"] and self.headers.get("Authorization") != f"Bearer {CONFIG['auth_token']}":
            return self.reply(401)
        try:
            payload = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        except ValueError:
            return self.reply(400)
        for alert in payload.get("alerts", []):
            jobs.put(alert)
        log.info("accepted %d alert(s), status=%s, queue=%d",
                 len(payload.get("alerts", [])), payload.get("status"), jobs.qsize())
        self.reply(200, "queued")


def main() -> None:
    logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(message)s")
    threading.Thread(target=worker, daemon=True).start()
    host, port = CONFIG["listen"].rsplit(":", 1)
    log.info("listening on %s, grafana %s", CONFIG["listen"], CONFIG["grafana_url"])
    ThreadingHTTPServer((host, int(port)), Handler).serve_forever()


if __name__ == "__main__":
    main()
