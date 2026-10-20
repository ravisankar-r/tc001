"""pomo install: upload the script and place it right after Time in the rotation."""
import sys
from pathlib import Path

from pomo.client import ClockClient

SOURCE_PATH = Path(__file__).resolve().parent.parent / "pomo.be"
APP = "pomo"


def install(client: ClockClient, source_path: Path = SOURCE_PATH, out=sys.stdout, err=sys.stderr) -> int:
    reply = client.put_script(APP, source_path.read_text())
    error = reply.get("error") if isinstance(reply, dict) else None
    if error:
        where = " (line %s)" % error["line"] if isinstance(error, dict) and error.get("line") else ""
        message = error.get("message", str(error)) if isinstance(error, dict) else str(error)
        err.write("install failed: %s%s\n" % (message, where))
        return 1
    apps = client.get_apps()
    # The clock lists apps in rotation order; sort by slot only when it reports one.
    in_loop = [a for a in apps if a.get("inLoop") and a["name"] != APP]
    if all(isinstance(a.get("slot"), int) for a in in_loop):
        in_loop.sort(key=lambda a: a["slot"])
    order = [a["name"] for a in in_loop]
    index = order.index("Time") + 1 if "Time" in order else len(order)
    order.insert(index, APP)
    disabled = [a["name"] for a in apps if not a.get("enabled", True)]
    client.put_order(order, disabled)
    out.write("installed %s (after Time in rotation)\n" % APP)
    return 0
