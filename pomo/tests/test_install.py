import io
import unittest
from pathlib import Path

from pomo.client import ClockClient
from pomo.install import install
from tests.fakes import FakeNG

SOURCE = Path(__file__).resolve().parent.parent / "pomo.be"


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.fake = FakeNG().start()
        self.fake.apps = [
            {"name": "Time", "enabled": True, "inLoop": True, "slot": 0, "origin": "builtin"},
            {"name": "Date", "enabled": True, "inLoop": True, "slot": 1, "origin": "builtin"},
            {"name": "Temperature", "enabled": True, "inLoop": True, "slot": 2, "origin": "builtin"},
            {"name": "Battery", "enabled": False, "inLoop": False, "slot": 3, "origin": "builtin"},
            {"name": "pomo", "enabled": True, "inLoop": True, "slot": 4, "origin": "script", "error": None},
        ]
        self.client = ClockClient(self.fake.url)
        self.out, self.err = io.StringIO(), io.StringIO()

    def tearDown(self):
        self.fake.stop()

    def test_install_uploads_and_orders(self):
        self.assertEqual(install(self.client, out=self.out, err=self.err), 0)
        self.assertEqual(self.fake.script, SOURCE.read_text())
        self.assertEqual(self.fake.order,
                         {"order": ["Time", "pomo", "Date", "Temperature"], "disabled": ["Battery"]})
        self.assertIn("installed pomo (after Time in rotation)", self.out.getvalue())

    def test_install_compile_error(self):
        self.fake.script_error = {"message": "syntax_error: x", "line": 12}
        self.assertEqual(install(self.client, out=self.out, err=self.err), 1)
        self.assertIn("install failed: syntax_error: x (line 12)", self.err.getvalue())
        self.assertIsNone(self.fake.order)


if __name__ == "__main__":
    unittest.main()
