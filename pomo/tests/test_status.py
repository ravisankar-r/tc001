import unittest
from datetime import datetime

from pomo.status import log_lines, render_screen, status_line

NOW = 1_700_000_000_000
CFG = {"focus": 25, "shortBreak": 5, "longBreak": 15, "every": 4, "sound": True}


class StatusLineTests(unittest.TestCase):
    def test_idle_and_empty(self):
        self.assertEqual(status_line({}, {}, 0), "IDLE")
        self.assertEqual(status_line({"phase": "IDLE"}, CFG, NOW), "IDLE")

    def test_running(self):
        d = {"phase": "FOCUS", "paused": False, "endEpoch": NOW + 1_394_000, "cycle": 1}
        self.assertEqual(status_line(d, CFG, NOW), "FOCUS 23:14 left, cycle 1/4")

    def test_paused(self):
        d = {"phase": "FOCUS", "paused": True, "remainMs": 600_000, "cycle": 2}
        self.assertEqual(status_line(d, CFG, NOW), "FOCUS (paused) 10:00 left, cycle 2/4")

    def test_break_names(self):
        d = {"phase": "SHORT", "paused": False, "endEpoch": NOW + 299_000, "cycle": 1}
        self.assertEqual(status_line(d, CFG, NOW), "BREAK 04:59 left, cycle 1/4")
        d["phase"] = "LONG"
        self.assertTrue(status_line(d, CFG, NOW).startswith("REST 04:59"))

    def test_overdue_clamps_to_zero(self):
        d = {"phase": "FOCUS", "paused": False, "endEpoch": NOW - 5000, "cycle": 0}
        self.assertEqual(status_line(d, CFG, NOW), "FOCUS 00:00 left, cycle 0/4")


class LogTests(unittest.TestCase):
    def test_log_lines(self):
        e1 = {"s": NOW, "e": NOW + 1_500_000, "m": 25, "ok": True}
        e2 = {"s": NOW + 3_600_000, "e": NOW + 3_900_000, "m": 25, "ok": False}
        e3 = {"s": NOW + 7_200_000, "e": NOW + 9_000_000, "m": 30, "ok": True}
        lines = log_lines({"log": [e1, e2, e3]}, 2)
        self.assertEqual(len(lines), 2)
        stamp3 = datetime.fromtimestamp(e3["s"] / 1000).strftime("%Y-%m-%d %H:%M")
        self.assertEqual(lines[0], "%s  30 min  done" % stamp3)
        self.assertTrue(lines[1].endswith("25 min  aborted"))
        self.assertEqual(log_lines({}, 5), [])


class ScreenTests(unittest.TestCase):
    def test_render_screen(self):
        self.assertEqual(render_screen({"width": 2, "height": 2, "pixels": [1, 0, 0, 255]}), "█·\n·█")


if __name__ == "__main__":
    unittest.main()
