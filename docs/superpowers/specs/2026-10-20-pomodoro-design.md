# Pomodoro timer on the Ulanzi TC001

Date: 2026-10-20
Status: SUPERSEDED by 2026-10-20-pomodoro-ng-design.md (clock moved to AWTRIX NG; timer now runs on-device)

## Intent

A pomodoro timer that lives on the Ulanzi TC001 pixel clock (running AWTRIX 3 v0.98)
and can be driven from two places with equal standing: the clock's own hardware
buttons, and a command line on the Mac. The Mac is where durations get configured.

The clock is already set up: AWTRIX 3 at `http://192.168.1.104`, time zone and
styles configured, and the developer setting `button_callback` points at
`http://192.168.1.102:8484/button`. A spike confirmed the clock POSTs
`button=left|right&state=1|0` (form-encoded) on every press and release of the
left and right buttons. The middle button is not delivered over HTTP (MQTT only)
and is out of scope.

## Goals

- Start, pause/resume, skip, and stop a pomodoro cycle from the clock buttons.
- Do the same from a `pomo` CLI on the Mac.
- Edit the focus, short-break, long-break durations and cycle length on the Mac,
  with changes taking effect without restarting anything.
- Show the timer on the clock: remaining time, a draining progress bar, a color
  per phase, an audible and visual cue at phase end.
- Return the clock to its normal page rotation when the timer stops.
- Survive the daemon dying: the timer page must disappear from the clock on its
  own rather than freeze on a stale time.

## Non-goals

- Middle button, MQTT, Home Assistant integration.
- Menu-bar app, notifications on the Mac, or any Mac-side UI beyond the CLI.
- Custom firmware on the clock. Everything uses the stock AWTRIX HTTP API.
- Multiple clocks, multiple users, or remote (off-LAN) control.
- Syncing with calendars or task managers.

## Anti-goals (would make this a failure even if it works)

- The clock getting stuck showing a timer page after the daemon or Mac goes
  away.
- Button presses that sometimes do nothing, or do the wrong thing because the
  clock's own button behavior (page switching) fought the timer.
- Wearing the clock's flash: never use AWTRIX's `save` flag on the timer app.
- A setup that needs the user to remember IPs or edit files on the clock after
  the first install.

## Constraints

- Mac: macOS, Python 3.13 at `/Library/Frameworks/Python.framework/Versions/3.13`.
  Standard library only, no third-party packages. (Owner is a Python engineer;
  stdlib keeps install to "copy files".)
- Clock reaches the Mac only by IP. The ESP32's HTTP client does not resolve
  `.local` names, so the callback URL carries the Mac's LAN IP. The Mac is on
  DHCP at 192.168.1.102 today.
- AWTRIX custom-app API: `POST /api/custom?name=<app>` with JSON; empty body
  deletes the app. Relevant keys: `text`, `color`, `progress` (0–100),
  `progressC`, `progressBC`, `noScroll`, `center`, `blinkText`, `lifetime`
  (seconds; app auto-removed if not refreshed), `duration`.
  `POST /api/notify` for one-shot overlays with `rtttl` melodies.
  `POST /api/switch {"name": ...}` jumps to an app. `POST /api/settings`
  can set `ATRANS` (auto page transition) on/off.
- Button presses on the clock also perform their built-in action (switch to
  the previous/next page). The daemon must counteract this.
- Only left and right buttons are available.

## Decisions (made in conversation with the owner)

### Architecture

Three pieces, all in `~/Workspace/tc001/pomo/`:

1. **`pomod`**, a long-running daemon on the Mac. Owns the timer state machine.
   Listens on `0.0.0.0:8484` (HTTP, stdlib `http.server`) for:
   - `POST /button` from the clock (form-encoded, as above).
   - `POST /cmd` from the CLI (JSON `{"cmd": "start", "minutes": 25}` etc.).
   - `GET /status` (JSON) for the CLI and for debugging.
   Pushes a frame to the clock once per second while a phase is running, and on
   every state change.
2. **`pomo`**, a CLI. A thin HTTP client for `pomod`. Never talks to the clock.
3. **A launchd user agent** (`~/Library/LaunchAgents/com.ravisankar.pomod.plist`)
   with `RunAtLoad` and `KeepAlive`, so `pomod` is always up. An `install.sh`
   writes the plist, loads it, and also points the clock's button callback at
   the Mac's current IP. Re-run `install.sh` if the Mac's IP changes. The owner
   is advised to give the Mac a DHCP reservation.

   How the callback is set (verified against the firmware source and the real
   clock): `button_callback` lives only in `/dev.json` on the clock's
   filesystem and is read at boot. There is no settings-API key for it.
   `install.sh` must `GET http://<clock>/dev.json` (404 or empty means start
   from `{}`), set `button_callback` to `http://<mac-ip>:8484/button`, upload
   the file with a multipart `POST /edit` (form field `file`, filename
   `/dev.json`), then `POST /api/reboot` and wait for `/api/stats` to answer
   again (about 10 s). Rebooting the clock during install is acceptable.

Why a Mac daemon rather than something on the clock: AWTRIX has no scripting; the
only way to react to buttons is an HTTP callback to something that is listening.
Accepted tradeoff: buttons do nothing while the Mac is asleep.

### State machine

States: `IDLE`, `FOCUS`, `SHORT_BREAK`, `LONG_BREAK`, each of the three running
states with a `paused` flag. A `cycle` counter tracks completed focus blocks since
the last long break.

Events and transitions:

| Event | IDLE | FOCUS / breaks (running) | (paused) |
|---|---|---|---|
| `start [minutes]` | → FOCUS | ignored | → resume |
| `pause` | ignored | → paused | ignored |
| `resume` | ignored | ignored | → running |
| `toggle` | → FOCUS | → paused | → running |
| `skip` | ignored | → next phase, no cue | → next phase |
| `stop` | ignored | → IDLE | → IDLE |
| `tick` (time up) | — | → next phase, with cue | — |

Next phase after FOCUS: `LONG_BREAK` if `cycle` just reached `long_break_every`
(then `cycle` resets), else `SHORT_BREAK`. Next phase after any break: `FOCUS`.
A `skip` out of FOCUS counts as not completed (logged as such) and does not
advance `cycle`.

Timing is wall-clock based: each phase stores its end timestamp, and remaining
time is `end - now`. Pausing stores remaining seconds; resuming sets a new end
timestamp.

`stop` resets `cycle` to 0 (builder-check call: a fresh start the next day
should not inherit yesterday's count).

**Overdue rule** (builder-check call): on any tick, if the phase is overdue by
less than 5 minutes it ends normally with its cue. If it is overdue by 5 minutes
or more (Mac was asleep, daemon was down), the daemon goes to `IDLE` quietly: no
cue, FOCUS logged as `completed: false`, clock cleaned up as on `stop`.

**Persistence** (builder-check call): the daemon writes
`~/.local/share/pomo/state.json` on every state change: phase, paused flag,
end timestamp or remaining seconds, cycle, per-block minutes override, and the
clock's `ATRANS` value recorded at takeover. On startup it loads this file and
applies the overdue rule: a running phase overdue by under 5 minutes resumes
(frames start pushing again); anything else becomes `IDLE`, with the clock
cleaned up and `ATRANS` restored from the file. This is what makes
launchd `KeepAlive` restarts safe.

### Button mapping

Press and release are both delivered, so the daemon measures hold time.

| Button | Short press (< 1.0 s) | Long press (≥ 1.0 s) |
|---|---|---|
| Left | `toggle` (start / pause / resume) | nothing |
| Right | `skip` | `stop` |

Actions fire on release, so a long press is never mistaken for a short one.

Known consequence, accepted by the owner: while `IDLE`, any left tap starts a
focus block and takes over the display, so the left button no longer serves as
"previous page". If this proves annoying, the agreed fallback is "left long
press to start" and short press reserved for pause/resume.
Because the clock also switches pages on each press, after handling any button
event while not `IDLE` the daemon sends `POST /api/switch {"name":"pomo"}` to
bring the timer page back.

### CLI

```
pomo start [MINUTES]   start a focus block (default from config; MINUTES overrides this block only)
pomo pause
pomo resume
pomo toggle
pomo skip
pomo stop
pomo status            one line: phase, mm:ss left, cycle n/N, paused?
pomo config            print current config
pomo config KEY VALUE  set a key (focus, short_break, long_break, long_break_every, sound, clock)
```

### Configuration

File: `~/.config/pomo/config.json`. Created with defaults on first run.

```json
{
  "focus": 25,
  "short_break": 5,
  "long_break": 15,
  "long_break_every": 4,
  "sound": true,
  "clock": "http://192.168.1.104",
  "listen_port": 8484
}
```

`pomod` reads the file at the start of every phase, so edits (via `pomo config`
or a text editor) apply from the next phase on, without a restart. `listen_port`
and `clock` are read at daemon start only.

### Display

The timer is an AWTRIX custom app named `pomo`, refreshed once per second.

- Text: `MM:SS` remaining, centered, no scroll. Five characters fit the 32 px
  width in AWTRIX's default font.
- Progress bar on the bottom row: `progress` = percent remaining, so it drains.
- Colors: FOCUS orange `#FF8C00`; SHORT_BREAK and LONG_BREAK teal `#00C8B4`;
  bar background dim gray `#202020`. Paused: `blinkText` 600 ms, same color.
- `lifetime: 10` on every push. If `pomod` stops pushing, the clock drops the
  page by itself within 10 s. This is the anti-stuck guarantee.
- No `save` flag, ever.

Taking over the display: on leaving `IDLE`, the daemon records the clock's
current `ATRANS` setting, sets `ATRANS` false, pushes the first frame, and
switches to `pomo`. On entering `IDLE`, it deletes the `pomo` app (empty body)
and restores `ATRANS`.

Phase-end cue (on `tick`, not on `skip`): `POST /api/notify` with text `BREAK`,
`REST` (long break) or `FOCUS`, the next phase's color, `duration` 4, and a
short RTTTL melody if `sound` is true. The next phase starts counting
immediately underneath; the notification simply overlays it.

### Logging

Append-only JSONL at `~/.local/share/pomo/log.jsonl`, one line per focus block
ended: `{"started": ISO8601, "ended": ISO8601, "minutes": n, "completed": bool}`.
Breaks are not logged. Daemon stdout/stderr go to
`~/Library/Logs/pomod.log` via the launchd plist.

### Failure handling

- Every HTTP call to the clock has a 2 s timeout. Failures are logged and
  ignored; the timer keeps running on the Mac and the next frame retries.
- If the clock is unreachable at `start`, the daemon still starts the timer and
  the CLI prints a warning taken from `/status`.
- Bad or missing config keys fall back to defaults with a warning.

### Testing

The state machine is a pure class with injected `now()` and no I/O, unit-tested
with the standard `unittest` module: every transition in the table, cycle
counting, pause/resume timing, overdue-after-sleep. The clock client is a small
class behind an interface so tests use a fake that records calls. The HTTP
handlers are tested with a real `HTTPServer` on an ephemeral port. Button
long-press detection is tested with injected timestamps.

## Left to the builder

- Module layout within `pomo/`, naming, and how `pomo` finds `pomod` (fixed
  `localhost:8484` is fine).
- The exact RTTTL melodies.
- Debounce details for button chatter, if any shows up.
- Whether `pomod` logs with `logging` or plain prints.
- How `install.sh` discovers the Mac's LAN IP (`ipconfig getifaddr en0` is
  acceptable; prompt if it fails).
- README content.
