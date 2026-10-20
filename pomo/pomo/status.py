"""Pure formatting of what the clock reports."""
from datetime import datetime

PHASE_NAMES = {"FOCUS": "FOCUS", "SHORT": "BREAK", "LONG": "REST"}


def status_line(data: dict, config: dict, now_ms: int) -> str:
    phase = data.get("phase", "IDLE")
    if phase not in PHASE_NAMES:
        return "IDLE"
    paused = bool(data.get("paused", False))
    if paused:
        remaining = int(data.get("remainMs", 0))
    else:
        remaining = max(0, int(data.get("endEpoch", 0)) - now_ms)
    secs = remaining // 1000
    name = PHASE_NAMES[phase] + (" (paused)" if paused else "")
    return "%s %02d:%02d left, cycle %d/%d" % (
        name, secs // 60, secs % 60, int(data.get("cycle", 0)), int(config.get("every", 4)))


def log_lines(data: dict, n: int) -> list:
    entries = list(data.get("log", []))[-n:] if n > 0 else []
    out = []
    for e in reversed(entries):
        stamp = datetime.fromtimestamp(int(e.get("s", 0)) / 1000).strftime("%Y-%m-%d %H:%M")
        out.append("%s  %d min  %s" % (stamp, int(e.get("m", 0)), "done" if e.get("ok") else "aborted"))
    return out


def render_screen(screen: dict) -> str:
    w, h, px = int(screen["width"]), int(screen["height"]), screen["pixels"]
    return "\n".join("".join("█" if px[y * w + x] else "·" for x in range(w)) for y in range(h))
