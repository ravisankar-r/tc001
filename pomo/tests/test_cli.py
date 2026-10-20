import io
import json
import tempfile
import unittest
from pathlib import Path

from pomo.cli import main
from tests.fakes import FakeNG

NOW = 1_700_000_000_000


def simulate_script(data):
    """Mimic pomo.be reacting to a command left in the store."""
    cmd = data.pop("cmd", "")
    minutes = data.pop("cmdMinutes", 0)
    if cmd == "start" and data.get("phase", "IDLE") == "IDLE":
        total = (minutes or 25) * 60000
        data.update({"phase": "FOCUS", "paused": False, "endEpoch": NOW + total, "totalMs": total, "cycle": 0})
    elif cmd == "pause" and data.get("phase", "IDLE") != "IDLE":
        data.update({"paused": True, "remainMs": data["endEpoch"] - NOW})
    elif cmd == "stop":
        data.update({"phase": "IDLE"})


class CliTests(unittest.TestCase):
    def setUp(self):
        self.fake = FakeNG().start()
        self.fake.on_patch_data = simulate_script
        self.tmp = tempfile.TemporaryDirectory()
        self.cfg = Path(self.tmp.name) / "config.json"
        self.cfg.write_text(json.dumps({"clock": self.fake.url}))
        self.out, self.err = io.StringIO(), io.StringIO()

    def tearDown(self):
        self.fake.stop()
        self.tmp.cleanup()

    def run_cli(self, *argv):
        return main(list(argv), config_path=self.cfg, out=self.out, err=self.err, now_ms=lambda: NOW)

    def test_start_sends_cmd_and_prints_status(self):
        self.assertEqual(self.run_cli("start"), 0)
        self.assertEqual(self.out.getvalue().strip(), "FOCUS 25:00 left, cycle 0/4")
        patches = [r for r in self.fake.requests if r[0] == "PATCH"]
        self.assertEqual(json.loads(patches[0][2]), {"cmd": "start", "cmdMinutes": 0})

    def test_start_minutes(self):
        self.assertEqual(self.run_cli("start", "40"), 0)
        self.assertIn("FOCUS 40:00 left", self.out.getvalue())

    def test_bad_minutes(self):
        for bad in ("0", "-3", "abc"):
            self.err = io.StringIO()
            self.assertEqual(self.run_cli("start", bad), 2)
            self.assertIn("minutes", self.err.getvalue())
        self.assertEqual(self.fake.requests, [])

    def test_status_idle(self):
        self.assertEqual(self.run_cli("status"), 0)
        self.assertEqual(self.out.getvalue().strip(), "IDLE")

    def test_pause_shows_paused(self):
        self.run_cli("start")
        self.out = io.StringIO()
        self.assertEqual(self.run_cli("pause"), 0)
        self.assertIn("FOCUS (paused) 25:00 left", self.out.getvalue())

    def test_config_print_and_set(self):
        self.assertEqual(self.run_cli("config"), 0)
        lines = self.out.getvalue().strip().splitlines()
        self.assertEqual(len(lines), 5)
        self.assertIn("focus = 25", lines)
        self.assertEqual(self.run_cli("config", "focus", "30"), 0)
        self.assertEqual(self.fake.config["focus"], 30)
        self.assertEqual(self.run_cli("config", "sound", "off"), 0)
        self.assertIs(self.fake.config["sound"], False)
        self.assertEqual(self.run_cli("config", "nope", "1"), 2)
        self.assertEqual(self.run_cli("config", "focus", "abc"), 2)

    def test_log(self):
        self.fake.data = {"log": [{"s": NOW, "e": NOW + 1_500_000, "m": 25, "ok": True}]}
        self.assertEqual(self.run_cli("log"), 0)
        self.assertIn("25 min  done", self.out.getvalue())

    def test_unreachable_and_not_installed(self):
        self.fake.installed = False
        self.assertEqual(self.run_cli("status"), 1)
        self.assertIn("pomo is not installed on the clock; run: pomo install", self.err.getvalue())
        self.cfg.write_text(json.dumps({"clock": "http://127.0.0.1:1"}))
        self.err = io.StringIO()
        self.assertEqual(self.run_cli("status"), 1)
        self.assertIn("cannot reach clock at http://127.0.0.1:1", self.err.getvalue())

    def test_screen(self):
        self.assertEqual(self.run_cli("screen"), 0)
        self.assertEqual(self.out.getvalue(), "█·\n·█\n")

    def test_no_verb_and_default_config_warning(self):
        self.assertEqual(self.run_cli(), 2)
        self.assertIn("usage", self.err.getvalue().lower())
        self.cfg.unlink()
        self.err = io.StringIO()
        self.run_cli("status")
        self.assertIn("using default clock url http://clock.local", self.err.getvalue())


if __name__ == "__main__":
    unittest.main()
