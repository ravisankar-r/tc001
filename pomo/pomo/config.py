"""Where the clock is. The only Mac-side state the CLI keeps."""
import json
from pathlib import Path

DEFAULT_CLOCK = "http://clock.local"
CONFIG_PATH = Path("~/.config/pomo/config.json").expanduser()


def load_config(path: Path = CONFIG_PATH) -> dict:
    """Return {"clock": url, "warned": bool}; warned is True when the default was used."""
    try:
        data = json.loads(path.read_text())
        clock = data.get("clock") if isinstance(data, dict) else None
        if isinstance(clock, str) and clock:
            return {"clock": clock.rstrip("/"), "warned": False}
    except (OSError, ValueError):
        pass
    return {"clock": DEFAULT_CLOCK, "warned": True}
