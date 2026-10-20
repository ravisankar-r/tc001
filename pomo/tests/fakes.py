"""FakeNG: a small http.server stand-in for the AWTRIX NG endpoints the CLI uses."""
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class FakeNG:
    def __init__(self):
        self.data = {}
        self.config = {"focus": 25, "shortBreak": 5, "longBreak": 15, "every": 4, "sound": True}
        self.script = None
        self.script_error = None
        self.order = None
        self.active = None
        self.apps = [
            {"name": "Time", "enabled": True, "inLoop": True, "slot": 0, "origin": "builtin"},
            {"name": "Date", "enabled": True, "inLoop": True, "slot": 1, "origin": "builtin"},
        ]
        self.screen = {"width": 2, "height": 2, "pixels": [1, 0, 0, 1]}
        self.installed = True
        self.requests = []
        self.on_patch_data = None  # optional callable(data) simulating the script's reaction
        self._server = None
        self._thread = None

    @property
    def url(self):
        return "http://127.0.0.1:%d" % self._server.server_address[1]

    def start(self):
        fake = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def _body(self):
                n = int(self.headers.get("Content-Length", 0))
                return self.rfile.read(n) if n else b""

            def _send(self, code, obj):
                body = json.dumps(obj).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def _handle(self):
                body = self._body()
                fake.requests.append((self.command, self.path, body, self.headers.get("Content-Type")))
                p = self.path
                if p == "/api/v1/apps/pomo/data":
                    if not fake.installed:
                        return self._send(404, {"error": "notFound"})
                    if self.command == "GET":
                        return self._send(200, fake.data)
                    if self.command == "PATCH":
                        patch = json.loads(body)
                        for k, v in patch.items():
                            if v is None:
                                fake.data.pop(k, None)
                            else:
                                fake.data[k] = v
                        if fake.on_patch_data:
                            fake.on_patch_data(fake.data)
                        return self._send(200, {"ok": True, "name": "pomo", "error": None})
                if p == "/api/v1/apps/pomo/config":
                    if not fake.installed:
                        return self._send(404, {"error": "notFound"})
                    if self.command == "PATCH":
                        fake.config.update(json.loads(body))
                    fields = [{"key": k, "type": "bool" if isinstance(v, bool) else "number",
                               "label": k, "default": v, "value": v} for k, v in fake.config.items()]
                    return self._send(200, {"name": "pomo", "fields": fields})
                if p == "/api/v1/apps/script/pomo" and self.command == "PUT":
                    fake.script = body.decode()
                    return self._send(200, {"ok": fake.script_error is None, "name": "pomo",
                                            "error": fake.script_error})
                if p == "/api/v1/apps" and self.command == "GET":
                    return self._send(200, fake.apps)
                if p == "/api/v1/apps/order" and self.command == "PUT":
                    fake.order = json.loads(body)
                    return self._send(200, {"ok": True})
                if p == "/api/v1/apps/active" and self.command == "PUT":
                    fake.active = json.loads(body).get("name")
                    return self._send(200, {"ok": True})
                if p == "/api/v1/display/screen" and self.command == "GET":
                    return self._send(200, fake.screen)
                return self._send(404, {"error": "notFound"})

            do_GET = do_PUT = do_PATCH = do_POST = do_DELETE = _handle

        self._server = ThreadingHTTPServer(("127.0.0.1", 0), H)
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()
        return self

    def stop(self):
        self._server.shutdown()
        self._server.server_close()
