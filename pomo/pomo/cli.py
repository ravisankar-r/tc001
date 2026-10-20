"""pomo: control the pomodoro script on the clock from the Mac."""
import sys
import time
from pathlib import Path

from pomo.client import ClockClient, ClockError, ClockUnreachable, NotInstalled
from pomo.config import CONFIG_PATH, load_config
from pomo.status import log_lines, render_screen, status_line

COMMANDS = ("start", "pause", "resume", "toggle", "skip", "stop")
CONFIG_KEYS = ("focus", "shortBreak", "longBreak", "every", "sound")
USAGE = """usage: pomo <verb> [args]
  start [MINUTES]    start a focus block (MINUTES overrides this block only)
  pause | resume | toggle | skip | stop
  status             what the clock is doing
  config             print focus, shortBreak, longBreak, every, sound
  config KEY VALUE   set one of them (applies from the next phase)
  log [N]            last N focus blocks (default 10)
  install            upload pomo.be to the clock and place it after Time
  screen             render the clock's display as text"""

NOT_INSTALLED = "pomo is not installed on the clock; run: pomo install"


def parse_minutes(raw: str) -> int:
    try:
        minutes = int(raw)
    except ValueError:
        raise ValueError("minutes must be a positive integer")
    if minutes <= 0:
        raise ValueError("minutes must be a positive integer")
    return minutes


def parse_config_value(key: str, raw: str):
    if key not in CONFIG_KEYS:
        raise ValueError("unknown config key %r (one of %s)" % (key, ", ".join(CONFIG_KEYS)))
    if key == "sound":
        low = raw.strip().lower()
        if low in ("true", "on", "1", "yes"):
            return True
        if low in ("false", "off", "0", "no"):
            return False
        raise ValueError("sound must be on or off")
    try:
        value = int(raw)
    except ValueError:
        raise ValueError("%s must be a positive integer" % key)
    if value <= 0:
        raise ValueError("%s must be a positive integer" % key)
    return value


def send_command(client: ClockClient, cmd: str, minutes: int = 0) -> dict:
    client.patch_data({"cmd": cmd, "cmdMinutes": minutes})
    return client.get_data()


def print_status(client, out, now_ms):
    out.write(status_line(client.get_data(), client.get_config(), now_ms()) + "\n")


def main(argv: list, *, client_factory=ClockClient, config_path: Path = CONFIG_PATH,
         out=sys.stdout, err=sys.stderr, now_ms=lambda: int(time.time() * 1000)) -> int:
    if not argv:
        err.write(USAGE + "\n")
        return 2
    verb, args = argv[0], argv[1:]
    minutes = 0
    if verb == "start" and args:
        try:
            minutes = parse_minutes(args[0])
        except ValueError as e:
            err.write(str(e) + "\n")
            return 2
    if verb == "config" and len(args) == 2:
        try:
            value = parse_config_value(args[0], args[1])
        except ValueError as e:
            err.write(str(e) + "\n")
            return 2

    cfg = load_config(config_path)
    if cfg["warned"]:
        err.write("using default clock url %s (no %s)\n" % (cfg["clock"], config_path))
    client = client_factory(cfg["clock"])

    try:
        if verb in COMMANDS:
            send_command(client, verb, minutes)
            print_status(client, out, now_ms)
        elif verb == "status":
            print_status(client, out, now_ms)
        elif verb == "config":
            if len(args) == 2:
                client.patch_config({args[0]: value})
            elif args:
                err.write("usage: pomo config [KEY VALUE]\n")
                return 2
            current = client.get_config()
            for key in CONFIG_KEYS:
                if key in current and (len(args) != 2 or key == args[0]):
                    out.write("%s = %s\n" % (key, current[key]))
        elif verb == "log":
            n = int(args[0]) if args else 10
            for line in log_lines(client.get_data(), n):
                out.write(line + "\n")
        elif verb == "screen":
            out.write(render_screen(client.get_screen()) + "\n")
        elif verb == "install":
            from pomo.install import install
            return install(client, out=out, err=err)
        else:
            err.write("unknown verb %r\n%s\n" % (verb, USAGE))
            return 2
    except NotInstalled:
        err.write(NOT_INSTALLED + "\n")
        return 1
    except ClockUnreachable:
        err.write("cannot reach clock at %s\n" % cfg["clock"])
        return 1
    except ClockError as e:
        err.write("clock error: %s\n" % e)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
