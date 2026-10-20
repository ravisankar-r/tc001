import json
import os
import tempfile
import unittest
from pathlib import Path

from pomo.client import ClockClient, ClockUnreachable, NotInstalled
from pomo.config import load_config
from tests.fakes import FakeNG


class ClientTests(unittest.TestCase):
    def setUp(self):
        self.fake = FakeNG().start()
        self.client = ClockClient(self.fake.url)

    def tearDown(self):
        self.fake.stop()

    def test_get_data_and_patch_merge(self):
        self.fake.data = {"phase": "IDLE"}
        self.assertEqual(self.client.get_data(), {"phase": "IDLE"})
        reply = self.client.patch_data({"cmd": "start", "cmdMinutes": 0})
        self.assertEqual(reply["error"], None)
        self.assertEqual(self.fake.data, {"phase": "IDLE", "cmd": "start", "cmdMinutes": 0})
        method, path, body, ctype = self.fake.requests[-1]
        self.assertEqual((method, path), ("PATCH", "/api/v1/apps/pomo/data"))
        self.assertEqual(ctype, "application/json")

    def test_not_installed_raises(self):
        self.fake.installed = False
        with self.assertRaises(NotInstalled):
            self.client.get_data()
        with self.assertRaises(NotInstalled):
            self.client.get_config()

    def test_get_config_flattens(self):
        self.assertEqual(self.client.get_config(),
                         {"focus": 25, "shortBreak": 5, "longBreak": 15, "every": 4, "sound": True})
        self.client.patch_config({"focus": 30})
        self.assertEqual(self.fake.config["focus"], 30)

    def test_put_script_raw_and_error(self):
        reply = self.client.put_script("pomo", "class X end\nreturn X()")
        self.assertEqual(reply["error"], None)
        self.assertEqual(self.fake.script, "class X end\nreturn X()")
        method, path, body, ctype = self.fake.requests[-1]
        self.assertEqual((method, path), ("PUT", "/api/v1/apps/script/pomo"))
        self.assertNotEqual(ctype, "application/json")
        self.fake.script_error = {"message": "syntax_error: x", "line": 12}
        self.assertEqual(self.client.put_script("pomo", "bad")["error"]["line"], 12)

    def test_apps_order_active_screen(self):
        self.assertEqual([a["name"] for a in self.client.get_apps()], ["Time", "Date"])
        self.client.put_order(["Time", "pomo", "Date"], ["Battery"])
        self.assertEqual(self.fake.order, {"order": ["Time", "pomo", "Date"], "disabled": ["Battery"]})
        self.client.put_active("pomo")
        self.assertEqual(self.fake.active, "pomo")
        self.assertEqual(self.client.get_screen()["pixels"], [1, 0, 0, 1])

    def test_unreachable(self):
        c = ClockClient("http://127.0.0.1:1", timeout=2)
        with self.assertRaises(ClockUnreachable):
            c.get_data()


class ConfigTests(unittest.TestCase):
    def test_load_config_defaults(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "config.json"
            self.assertEqual(load_config(p), {"clock": "http://clock.local", "warned": True})
            p.write_text(json.dumps({"clock": "http://192.168.1.7"}))
            self.assertEqual(load_config(p), {"clock": "http://192.168.1.7", "warned": False})
            p.write_text("{not json")
            self.assertEqual(load_config(p)["clock"], "http://clock.local")


if __name__ == "__main__":
    unittest.main()
