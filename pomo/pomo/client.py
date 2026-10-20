"""Every HTTP call the CLI makes to the AWTRIX NG clock."""
import json
import socket
import urllib.error
import urllib.request

APP = "pomo"


class ClockUnreachable(Exception):
    pass


class NotInstalled(Exception):
    pass


class ClockError(Exception):
    pass


class ClockClient:
    def __init__(self, base_url: str, timeout: float = 5.0):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def _request(self, method: str, path: str, body: bytes | None = None,
                 content_type: str | None = "application/json"):
        req = urllib.request.Request(self.base_url + path, data=body, method=method)
        if body is not None and content_type:
            req.add_header("Content-Type", content_type)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise NotInstalled(path)
            raise ClockError("%s %s -> %d %s" % (method, path, e.code, e.read().decode(errors="replace")))
        except (urllib.error.URLError, socket.timeout, OSError, TimeoutError) as e:
            raise ClockUnreachable(str(e))
        return json.loads(raw) if raw else None

    def _json(self, method: str, path: str, obj) -> object:
        return self._request(method, path, json.dumps(obj).encode())

    def get_data(self) -> dict:
        return self._request("GET", "/api/v1/apps/%s/data" % APP) or {}

    def patch_data(self, d: dict) -> dict:
        return self._json("PATCH", "/api/v1/apps/%s/data" % APP, d)

    def get_config(self) -> dict:
        reply = self._request("GET", "/api/v1/apps/%s/config" % APP) or {}
        return {f["key"]: f.get("value", f.get("default")) for f in reply.get("fields", [])}

    def patch_config(self, d: dict) -> dict:
        return self._json("PATCH", "/api/v1/apps/%s/config" % APP, d)

    def put_script(self, name: str, source: str) -> dict:
        return self._request("PUT", "/api/v1/apps/script/%s" % name, source.encode(), content_type=None)

    def get_apps(self) -> list:
        return self._request("GET", "/api/v1/apps") or []

    def put_order(self, order: list, disabled: list) -> None:
        self._json("PUT", "/api/v1/apps/order", {"order": order, "disabled": disabled})

    def put_active(self, name: str) -> None:
        self._json("PUT", "/api/v1/apps/active", {"name": name, "fast": True})

    def get_screen(self) -> dict:
        return self._request("GET", "/api/v1/display/screen")
