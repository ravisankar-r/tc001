# Pomodoro timer on the Ulanzi TC001 (AWTRIX NG, on-device)

Date: 2026-10-20
Status: builder check done, awaiting owner approval
Supersedes: `2026-10-20-pomodoro-design.md` (Mac-daemon design for AWTRIX 3)

## Intent

A pomodoro timer that runs on the Ulanzi TC001 pixel clock itself, as a Berry
script under AWTRIX NG 1.2.2, and can be driven with equal standing from the
clock's buttons and from a `pomo` command line on the Mac. Durations are edited
from the Mac (and, as a side effect of how NG works, also in the clock's web UI).

Why on-device: the earlier design needed a daemon on the Mac because AWTRIX 3
had no scripting. NG has Berry scripts with button events, timers, persistent
storage and a data API, so the clock can own the timer and the buttons work
whether or not the Mac is awake.

Current state of the clock: AWTRIX NG 1.2.2 at `http://192.168.1.7`, hostname
`clock` (`http://clock.local`), timezone set, Wi‑Fi joined, no scripts installed.

## Goals

- Start, pause/resume, skip and stop a pomodoro cycle from the clock's buttons.
- Do the same from the `pomo` CLI on the Mac.
- Edit focus, short break, long break and cycle length from the Mac, taking
  effect from the next phase, with no reinstall.
- Show the timer on the clock: remaining time, a draining progress bar, a color
  per phase, an audible and visual cue at phase end.
- While a phase runs, the timer stays on screen; when idle, the normal rotation
  continues and the timer has only a small idle page.
- Survive clock reboots and script restarts mid-phase: the phase resumes with
  the right remaining time.

## Non-goals

- MQTT, Home Assistant, the AWTRIX Hub, any Mac daemon or launchd agent.
- Mac-side UI beyond the CLI. Mac notifications.
- Multiple clocks, remote (off-LAN) control, authentication on the clock.
- Changing clock firmware. Only the stock NG HTTP API and scripting are used.

## Anti-goals

- The clock stuck showing a timer after it should have ended (rotation paused
  with nothing to show).
- Buttons that sometimes do the wrong thing because the clock's built-in
  navigation got the press.
- Burning the clock's flash: `store.set()` only on state transitions, never
  once per second or inside `draw()`.
- Blowing the 96 KB shared script heap: no allocations in `draw()`, bounded
  lists, few methods.
- A setup that needs the user to remember the clock's IP or edit files on the
  clock after `pomo install`.

## Constraints and verified facts (NG 1.2.2, from docs and the live clock)

Script lifecycle: a script is a Berry class returned at the end of the file.
`init()` runs when the script loads or restarts; `setup()` once after loading;
`loop()` about once a second whether or not shown; `draw()` about 40×/s while
shown; `on_button_event(btn, event)` with `btn` in `left|select|right` and
`event` in `press|long|repeat|release`. Returning `true` for `press` takes the
button for the rest of that press. `long` fires after 500 ms for left/right
only; select has no long event (holding it opens the device menu).
`should_show()` and `duration()` control the app's turn in the rotation.

Persistence: `store.get(key, default)` / `store.set(key, value)` keep
JSON-able values across reboots; written to flash within 5 s. `# @config`
header lines declare user settings that `store.get()` reads and the web UI and
`PATCH /api/v1/apps/{name}/config` edit (the script restarts on edit).

Time: `epoch_ms()` is UTC ms since 1970, `-1` until NTP has synced. `now_ms()`
is ms since boot.

Rotation control from a script: `rotation.show()` brings the rotation to this
app; `rotation.pause()` stops automatic switching ("any move by the user ends
the pause"); `rotation.resume()`.

Drawing: `clear()`, `font("small"|"large")` (reset every frame), `text(x, y,
str, color)` with `y` as baseline (`large` capitals fill rows 0–6 at `y=6`),
`text_ink_width(str)`, `progress(pct, color, bg)` draws the bottom row,
`pixel()`, `rect_fill()`. Colors are `0xRRGGBB` integers.

Sound and cues: `sound.play({'rtttl': "..."})`; `notify(map)` with the
notification payload (`text`, `textColor`, `durationMs`, `sound`,
`scroll: {"mode": "static"}`). Melody source max 512 chars.

Limits: 96 KiB heap shared by all scripts; 200k Berry instructions per entry;
8 timers per app; each `def` costs ~200 bytes; avoid string building in
`draw()`.

HTTP API (all JSON with `Content-Type: application/json`):
- `PUT /api/v1/apps/script/{name}` body = raw Berry source; answer `200` even
  on compile error, so check `error` is `null` in the JSON reply.
- `GET /api/v1/apps/{name}/data` → the script's stored values.
  `PATCH /api/v1/apps/{name}/data` merges keys (`null` deletes) and **restarts
  the script**, which "keeps its place in the rotation". This is the only way
  to send a script a command from outside without MQTT.
- `GET/PATCH /api/v1/apps/{name}/config` → `@config` values; restarts too.
- `PUT /api/v1/apps/active {"name": ..., "fast": true}` shows an app now.
- `PUT /api/v1/apps/order {"order": [...], "disabled": [...]}`.
- `GET /api/v1/display/screen` → `{width, height, pixels[]}` for verification.
- `GET /api/v1/apps` lists apps with `origin`, `error`, `inLoop`.

Only the shown app receives button events. Default left/right switch apps.

## Decisions

### Verified on hardware (Task 1 probe, 2026-10-20)

- (a) Select: a tap delivers `press` then `release` (~170 ms apart). A hold
  delivers only `press`; the device menu swallows the rest, so no `release`
  arrives. Therefore select's action fires on `release`: a tap toggles, a hold
  never does. Select stays in the button table.
- (b) Store: `PATCH /data` sent 1.5 s after `store.set()` kept the live value
  (counter 12 → 13 → restart → 14) and `GET /data` showed it. Outcome A: the
  command path stays as designed.
- (c) `rotation.pause()` survived four consumed presses; the probe was still
  the shown app 10 s later. No re-pause needed after button events. The
  script also restarts in place after a data PATCH (`on_show` fires again).
- Left/right `press`/`release` arrive as documented. `long` was not exercised
  (the hold was 432 ms); Task 10 covers it.

### Architecture

Two pieces, both in `~/Workspace/tc001/pomo/`:

1. **`pomo.be`**, a Berry script installed on the clock as app `pomo`. Owns the
   state machine, button handling, display, cues, the overdue rule and a small
   bounded log. All state lives in the script's `store` so a restart (which
   every data or config PATCH causes) or a reboot loses nothing.
2. **`pomo`**, a Python 3.13 standard-library CLI on the Mac. It only talks
   HTTP to the clock: commands go in through `PATCH .../pomo/data`, status comes
   out of `GET .../pomo/data` and `GET .../pomo/config`, durations through
   `PATCH .../pomo/config`, and `pomo install` uploads the script. Its only
   local state is `~/.config/pomo/config.json` holding `{"clock":
   "http://clock.local"}`.

### State machine (in the script)

Stored keys (all in `store`): `phase` (`"IDLE"|"FOCUS"|"SHORT"|"LONG"`),
`paused` (bool), `endEpoch` (ms, when running), `remainMs` (when paused),
`cycle` (focus blocks completed since the last long break), `startedEpoch`,
`totalMs`, `log` (list, newest last, max 50 entries of
`{"s": startedEpoch, "e": endedEpoch, "m": minutes, "ok": bool}`),
`cmd` (`""` or a pending command name), `cmdMinutes` (int, 0 = none).

Config keys (via `# @config`): `focus` 25 (1–180), `shortBreak` 5 (1–60),
`longBreak` 15 (1–60), `every` 4 (1–12), `sound` true. Read with
`store.get()` at each phase start, so edits apply from the next phase.

Transitions, as in the superseded design:

| Event | IDLE | running | paused |
|---|---|---|---|
| `start [minutes]` | → FOCUS | ignored | → running |
| `pause` | ignored | → paused | ignored |
| `resume` | ignored | ignored | → running |
| `toggle` | → FOCUS | → paused | → running |
| `skip` | ignored | → next phase, no cue | → next phase |
| `stop` | ignored | → IDLE | → IDLE |
| time up (in `loop()`) | — | → next phase, with cue | — |

Next after FOCUS: `LONG` if `cycle` reaches `every` (then `cycle = 0`), else
`SHORT`. After any break: `FOCUS`. Leaving FOCUS by time-up appends a log entry
with `ok: true` and increments `cycle`; by `skip` or `stop`, `ok: false` and no
increment. `stop` resets `cycle` to 0.

Timing is epoch-based: `endEpoch = epoch_ms() + minutes*60000`. `loop()` does
nothing while `epoch_ms() <= 0` (no NTP yet). Overdue rule: when
`epoch_ms() >= endEpoch`, if overdue by less than 300 000 ms the phase ends
normally with its cue; otherwise the timer goes `IDLE` quietly (log `ok:
false` if it was FOCUS, no cue). Because state is in the store, this one rule
also covers reboots and script restarts.

Commands from the Mac: `init()` reads `cmd`; if non-empty and
`epoch_ms() > 0` it applies the transition (using `cmdMinutes` when > 0), then
writes `cmd = ""` and `cmdMinutes = 0`. If the time is not yet known, `cmd`
stays pending and `loop()` applies it on the first tick with a valid epoch.
Each command PATCH restarts the script, which applies the command on the way
back up.

Store consistency (builder-check call, gated by the Task-1 hardware probe):
`store.set()` reaches flash within 5 s and `PATCH /data` "merges keys" and
restarts. The probe checks whether a PATCH sent 1–2 s after a `store.set()`
preserves the unflushed value and whether `GET /data` shows it. Outcome A
(live store wins, expected): the command path stays as above. Outcome B
(flash copy wins): the CLI first `GET`s `/data` and sends the full current
state plus `cmd` in one PATCH, and the script treats the 5 s window as a known
limitation documented in the README.

Before time sync: while `epoch_ms() <= 0`, `loop()` does nothing, no command
is applied, `rotation.pause()` is not called even if the store says a phase
is running, and the page shows `--:--` in the phase color. The first valid
tick restores normal behaviour (and applies the overdue rule).

### Buttons (handled in `on_button_event`, only while the pomo page is shown)

A button is either fully taken by the script (return `true` on `press`, then
`long`/`release` arrive) or fully left to the clock's navigation; there is no
way to pass a short press through while still seeing a long one. So the
mapping depends on state:

| State | Left | Right | Select |
|---|---|---|---|
| IDLE | short: `rotation.previous()`; long: **start** | short: `rotation.next()` | tap: **start** |
| running / paused | short: `toggle`; long: nothing | short: `skip`; long: `stop` | tap: `toggle` |

The script takes every left/right `press` in every state, and in IDLE it
reproduces navigation itself with `rotation.previous()`/`rotation.next()`, so
walking through the idle page feels like any other page. Short vs. long: a
per-button flag records that `long` fired (firmware threshold 500 ms) so the
following `release` is not also treated as a short press; short actions fire on
`release`.

Select (builder-check call, gated by the Task-1 hardware probe): a select tap
is `start`/`toggle` only if the probe shows that holding select to open the
device menu does **not** also deliver a tap (`press`+`release`) to the script.
If it does, select is dropped from the mapping and long-left is the only
on-clock start; the doc and README are updated to say so.

### Reaching the timer from the clock

The pomo app stays in the rotation always. When `IDLE` it shows a small idle
page (`POMO` in orange, small font) with `duration()` = 3000 ms so it costs
little rotation time; the user presses right/left until it is on screen, then
taps select (or holds left). `pomo install` places `pomo` directly after
`Time` in the rotation order (`PUT /api/v1/apps/order`), so from the time page
it is one press away.

When a phase starts (from a button, a command or a restart that finds a running
phase and a valid epoch), the transition calls `rotation.show()` then
`rotation.pause()`. On `IDLE`, `rotation.resume()`. Hardware risk checked by
the Task-1 probe: whether a button press the script consumes counts as "a move
by the user" that ends the pause. If it does, re-call `rotation.pause()` after
every handled button event.

**Task-1 hardware probe.** Before any product code, a throwaway Berry script is
uploaded that logs every `on_button_event` (button, event, `now_ms()`), writes
a store value in `loop()`, and calls `rotation.pause()` on show. With it the
builder answers: (a) does a select hold deliver press/release to the script,
(b) does PATCH `/data` 1–2 s after `store.set()` keep the live value and does
GET show it, (c) does a consumed press end `rotation.pause()`. Results go into
this document's "Decisions" as verified facts and pick the gated branches
above.

### Display (`draw()`, no allocations)

Strings and numbers are rebuilt in `loop()` once a second into member fields:
`self.label` (`"MM:SS"`), `self.pct`, `self.color`.

- Running: `font("large")`, label centered using `text_ink_width`, color
  `0xFF8C00` for FOCUS, `0x00C8B4` for breaks; `progress(pct, color,
  0x202020)` on the bottom row, `pct` = percent remaining so it drains.
- Paused: same, but the label is drawn only when `(now_ms() / 600) % 2 == 0`.
- Idle: `font("small")`, `POMO` centered in `0xFF8C00`.
- No time yet (`epoch_ms() <= 0`) with a stored running phase: `--:--` in the
  phase color, no progress bar.

Phase-end cue (time-up only, not `skip`): `notify({"text": "BREAK"|"REST"|
"FOCUS", "textColor": next color, "durationMs": 4000, "scroll": {"mode":
"static"}, "sound": {"rtttl": melody}})`, the `sound` key only when the
`sound` setting is true. The next phase starts counting immediately beneath
the notification.

### CLI

```
pomo start [MINUTES]   focus block; MINUTES overrides this block only
pomo pause | resume | toggle | skip | stop
pomo status            IDLE | FOCUS 23:14 left, cycle 1/4 | FOCUS (paused) 10:00 left, cycle 2/4 | BREAK ... | REST ...
pomo config            print focus, shortBreak, longBreak, every, sound
pomo config KEY VALUE  set one key (same names as above)
pomo log [N]           last N completed/aborted focus blocks (default 10), local time
pomo install           upload pomo.be, verify error == null, set rotation order
pomo screen            render the clock's framebuffer as text (debug aid)
```

Status is computed on the Mac from `endEpoch`/`remainMs` and the Mac's clock
(both NTP-synced). Bad `MINUTES` (non-integer or `<= 0`) → message on stderr,
exit 2, nothing sent. Clock unreachable → `cannot reach clock at <url>` on
stderr, exit 1. Script missing (404 on data) → `pomo is not installed on the
clock; run: pomo install`, exit 1. Config file missing → defaults to
`http://clock.local` and says so once.

### Testing

- **Berry logic on the Mac.** Build the reference Berry interpreter from
  source (`github.com/berry-lang/berry`, plain `make`) into
  `~/Workspace/tc001/tools/berry`. `tests/harness.be` defines stub globals
  the script expects (`store`, `clear`, `text`, `font`, `text_ink_width`,
  `progress`, `width`, `height`, `rotation`, `notify`, `sound`, `epoch_ms`,
  `now_ms`, `log`) with a fake clock and call recorders, loads `pomo.be`, and
  the test files assert every transition in the table, cycle counting,
  pause/resume timing, the overdue rule, command application on `init()`,
  button short/long handling, and log bounding. Run with `tools/berry
  tests/run.be`. Verified 2026-10-20: `git clone --depth 1
  https://github.com/berry-lang/berry && make` builds in seconds on this Mac
  with the stock toolchain; integer division and `format()` behave as the
  script will assume.
- **CLI** with `unittest` against a local `http.server` fake of the four
  endpoints it uses.
- **Hardware pass** at the end: install, start from CLI, read
  `/api/v1/display/screen`, press buttons, reboot mid-phase, confirm resume.

## Left to the builder

- Berry file layout (one class, three or four methods, per the memory
  guidance), member names, exact RTTTL melodies (two, short).
- Exact idle page look within "POMO, small font, orange".
- Whether `rotation.show()`/`pause()` go in `setup()` or at the end of the
  transition helper, as long as a restart mid-phase ends up paused on pomo.
- How `pomo install` finds `pomo.be` (next to the Python package is fine).
- README wording.
