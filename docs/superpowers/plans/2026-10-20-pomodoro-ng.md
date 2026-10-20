# Pomodoro on AWTRIX NG Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pomodoro timer running as a Berry script on the Ulanzi TC001 (AWTRIX NG 1.2.2), driven by the clock's buttons and by a `pomo` CLI on the Mac.

**Architecture:** One Berry script (`pomo.be`) owns the state machine, buttons, display and cues, with all state in its persistent `store`. A stdlib-Python CLI talks only HTTP to the clock: commands via `PATCH /api/v1/apps/pomo/data` (which restarts the script, which applies the command in `init()`), status via `GET .../data` + `GET .../config`. Berry logic is unit-tested on the Mac with a stub harness and the reference Berry interpreter.

**Tech Stack:** Berry (AWTRIX NG 1.2.2 scripting), Python 3.13 standard library, reference Berry interpreter built from `github.com/berry-lang/berry`.

**Spec:** `docs/superpowers/specs/2026-10-20-pomodoro-ng-design.md`

## Global Constraints

- Clock: `http://192.168.1.7` (`http://clock.local`), AWTRIX NG 1.2.2. All JSON requests need `Content-Type: application/json`. Script upload is raw source.
- Python at `/Library/Frameworks/Python.framework/Versions/3.13/bin/python3`, standard library only.
- Berry script: no allocations in `draw()`; `store.set()` only on transitions; log list capped at 50; config keys `focus` 25 (1–180), `shortBreak` 5 (1–60), `longBreak` 15 (1–60), `every` 4 (1–12), `sound` true.
- Store keys: `phase` (`"IDLE"|"FOCUS"|"SHORT"|"LONG"`), `paused`, `endEpoch`, `remainMs`, `cycle`, `startedEpoch`, `totalMs`, `log`, `cmd` (`""` when none), `cmdMinutes` (0 when none).
- Colors: FOCUS `0xFF8C00`, SHORT/LONG `0x00C8B4`, bar background `0x202020`. Cue texts `BREAK` (SHORT), `REST` (LONG), `FOCUS`; cue `durationMs` 4000. Blink period 600 ms. Idle `duration()` 3000 ms. Overdue cutoff 300000 ms. Long press is firmware-defined (500 ms).
- Project root `~/Workspace/tc001/pomo/`. Berry tests: `../tools/berry tests/run.be` from that directory. Python tests: `python3 -m unittest discover -s tests -v`.
- Commits end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

1. A `release` with no preceding taken `press` (script restarted mid-press): ignored, no action. Test in Task 4.
2. `pomo start 0`, `-5`, `abc`: stderr message, exit 2, no request sent. Test in Task 8.
3. The clock's `/data` returning `{}` (fresh install, nothing stored yet): status prints `IDLE`, no KeyError. Test in Task 7.
4. `pomo install` when the upload compiles with an error: prints the message and line, exit 1, does not touch rotation order. Test in Task 9.
5. A `PATCH /data` command arriving while `epoch_ms()` is `-1`: command stays pending and is applied on the first valid `loop()` tick, not lost. Test in Task 3.

---

## File structure

```
tc001/
  .gitignore
  tools/build-berry.sh        clones berry-lang/berry (depth 1) into tools/berry-src and builds tools/berry
  probe/probe.be              Task 1 throwaway hardware probe (kept for reference)
  pomo/
    pomo.be                   the Berry script, class Pomo
    pomo/__init__.py
    pomo/config.py            load_config() -> {"clock": url}
    pomo/client.py            ClockClient: every HTTP call to the clock; ClockUnreachable, NotInstalled
    pomo/status.py            pure: status_line(), log_lines(), render_screen()
    pomo/cli.py               main(argv, ...) verbs; python3 -m pomo.cli
    bin/pomo                  bash wrapper
    tests/harness.be          stub AWTRIX globals, FakeStore, call recorder, load_pomo()
    tests/run.be              runs every test_*.be, prints "N passed, M failed"
    tests/test_machine.be  test_commands.be  test_buttons.be  test_display.be
    tests/fakes.py            FakeNG: http.server fake of the endpoints the CLI uses
    tests/test_client.py  test_status.py  test_cli.py  test_install.py
    README.md
```

---

### Task 1: Repo, Berry toolchain, hardware probe

**Files:**
- Create: `.gitignore`, `tools/build-berry.sh`, `probe/probe.be`
- Modify: `docs/superpowers/specs/2026-10-20-pomodoro-ng-design.md` (record probe results)

**Interfaces:**
- Produces: `tools/berry` executable; verified facts (a) select hold behaviour, (b) store/PATCH consistency, (c) whether a consumed press ends `rotation.pause()`.

- [ ] **Step 1: Init repo and commit the specs**

```bash
cd ~/Workspace/tc001 && git init
printf 'firmware/*.bin\nfirmware/awtrix/\nfirmware/awtrix-ng/\ntools/berry-src/\ntools/berry\n__pycache__/\n*.pyc\n.DS_Store\n' > .gitignore
git add .gitignore docs firmware/*.sh firmware/.gitignore
git commit -m "docs: pomodoro design (AWTRIX NG, on-device) and firmware scripts"
```

- [ ] **Step 2: Write `tools/build-berry.sh`** (`set -euo pipefail`; `git clone --depth 1 https://github.com/berry-lang/berry tools/berry-src` unless present; `make -C tools/berry-src -j4`; `cp tools/berry-src/berry tools/berry`). Run it; `tools/berry -e 'print(1+1)'` prints `2`. Commit: `git add tools/build-berry.sh && git commit -m "chore: script to build the Berry interpreter for tests"`.

- [ ] **Step 3: Write `probe/probe.be`**, a throwaway script, class `Probe`:
  - `init()`: `self.n = store.get("n", 0)`; `log("probe init n=" + str(self.n))`.
  - `loop()`: `self.n += 1; store.set("n", self.n)` (once per second, probe only).
  - `on_show()`: `rotation.pause(); log("probe paused rotation")`.
  - `on_button_event(btn, event)`: `log(format("btn %s %s %d", btn, event, now_ms())); return true`.
  - `draw()`: `clear(); text(1, 6, "PRB", 0xFF00FF)`.
  - `return Probe()`.

- [ ] **Step 4: Upload and show it**

```bash
curl -s -X PUT http://192.168.1.7/api/v1/apps/script/probe --data-binary @probe/probe.be; echo
curl -s -X PUT http://192.168.1.7/api/v1/apps/active -H 'Content-Type: application/json' -d '{"name":"probe","fast":true}'
```
Expected: first reply has `"error":null`.

- [ ] **Step 5: Ask the owner to press, in order: left tap, right hold 1 s, select tap, select hold 1 s (menu opens; then hold select again to leave the menu if needed), then wait 10 s.** Then read the log:

```bash
curl -s http://192.168.1.7/api/v1/logs | grep -E "script:probe|btn " | tail -40
```
Record: (a) which events arrived for the select hold; (c) whether the display stayed on PRB for the whole time (it should, if the pause survived the consumed presses; also confirm via `GET /api/v1/display/screen` showing `PRB` 10 s after the last press).

- [ ] **Step 6: Store consistency.** Run:

```bash
N1=$(curl -s http://192.168.1.7/api/v1/apps/probe/data | python3 -c 'import json,sys; print(json.load(sys.stdin).get("n"))'); sleep 1.5
curl -s -X PATCH http://192.168.1.7/api/v1/apps/probe/data -H 'Content-Type: application/json' -d '{"marker":1}'; sleep 1
N2=$(curl -s http://192.168.1.7/api/v1/apps/probe/data | python3 -c 'import json,sys; print(json.load(sys.stdin).get("n"))'); echo "before=$N1 after=$N2"
```
Expected for Outcome A: `after` ≥ `before` + 1 (live value kept, GET reflected it). If `after` < `before`, that is Outcome B.

- [ ] **Step 7: Remove the probe** `curl -s -X DELETE http://192.168.1.7/api/v1/apps/probe` and `curl -s -X PUT .../apps/active -d '{"name":"Time"}'`.

- [ ] **Step 8: Record results** in the spec under "Decisions" as a short "Verified on hardware (Task 1)" list stating (a), (b) with outcome A/B, (c). If (a) shows a tap is delivered on hold, delete select from the button table. If (b) is Outcome B, note that Task 8's `send_command` must send full state. Commit: `git add probe docs && git commit -m "chore: hardware probe results for buttons, store and rotation"`.

---

### Task 2: Berry harness and the state machine core

**Files:**
- Create: `pomo/tests/harness.be`, `pomo/tests/run.be`, `pomo/tests/test_machine.be`, `pomo/pomo.be`

**Interfaces:**
- `harness.be` (loaded first by every test file via `import global` then defining globals):
  - `FakeStore` with `.data` (map) and `.writes` (int); `store.get(k)`/`store.get(k, d)`/`store.set(k, v)`; seeded with `focus=25, shortBreak=5, longBreak=15, every=4, sound=true`.
  - `clock` map: `clock["epoch"]` (default `-1`), `clock["ms"]` (default `0`); globals `epoch_ms()` and `now_ms()` return them.
  - `calls` list; stub globals append lists: `["clear"]`, `["font", name]`, `["text", x, y, s, color]`, `["progress", pct, color, bg]`, `["notify", map]`, `["sound", map]`, `["rotation", op]` for `show|pause|resume|next|previous`, `["log", v]`. `text_ink_width(s)` returns `4 * size(s) - 1`; `width()` 32; `height()` 8; `sound.play(m)` records and returns `true`; `notify(m)` records and returns `true`; `rotation.show()` returns `true`.
  - `load_pomo()` → fresh `Pomo` instance from `../pomo.be` via `compile(path, "file")()`; keeps the same `store`.
  - `reset_calls()`, `calls_of(name)` → list of matching entries, `fresh()` → new `FakeStore`, `clock` reset, calls cleared.
  - `t(name, fn)` registers a test into global `tests`.
- `run.be`: loads harness, every `tests/test_*.be`, runs each test in a `try`, prints `PASS name` / `FAIL name: <msg>`, final `N passed, M failed`, and calls `os.exit(1)` when `M > 0` (via `import os`).
- `pomo.be` class `Pomo`, members: `phase, paused, endEpoch, remainMs, cycle, startedEpoch, totalMs, label, pct, color, leftLong, rightLong`. Methods this task: `init()`, `load()` (store → members), `save()` (members → store; one `store.set` per key, only called from transitions), `enter(phase, minutes)` (sets `startedEpoch = epoch_ms()`, `totalMs = minutes*60000`, `endEpoch = startedEpoch + totalMs`, `paused = false`, then `save()`, `rotation.show()`, `rotation.pause()`), `advance(withCue)` (FOCUS → `cycle += 1` and log `ok:true` only when `withCue`; picks SHORT/LONG; breaks → FOCUS via `enter`), `go_idle(quiet)` (FOCUS → log `ok:false`; `phase = "IDLE"`, `cycle = 0`, `save()`, `rotation.resume()`), `apply(cmd, minutes)` (the transition table: `start|pause|resume|toggle|skip|stop`), `loop()` (epoch gate; time-up and overdue rule; then label/pct/color rebuild, added in Task 5), `should_show()` → `true`, `duration()` → `3000` when IDLE else `0`.
  Log entry shape: `{"s": startedEpoch, "e": epoch_ms(), "m": totalMs/60000, "ok": bool}`, appended to `log`, trimmed with `remove(0)` while `size > 50`.

- [ ] **Step 1: Write `harness.be` and `run.be`** as specified. `tools/berry tests/run.be` with no test files prints `0 passed, 0 failed`.

- [ ] **Step 2: Write the failing tests** in `test_machine.be` (each uses `fresh()`, sets `clock["epoch"] = 1000000`, then `p = load_pomo()`):

```
t("idle_initially", ...)            # p.phase == "IDLE"; p.duration() == 3000; store.data["phase"] == nil (nothing written yet)
t("start_enters_focus", ...)        # p.apply("start", 0); phase "FOCUS"; endEpoch == 1000000 + 25*60000; totalMs == 1500000; calls_of("rotation") == [["rotation","show"],["rotation","pause"]]; store.data["phase"] == "FOCUS"; p.duration() == 0
t("start_minutes_override", ...)    # apply("start", 45); endEpoch - startedEpoch == 2700000
t("start_while_running_ignored", ...)   # second apply("start", 0) leaves endEpoch unchanged and writes nothing more (store.writes unchanged)
t("pause_resume", ...)              # start; epoch += 60000; apply("pause",0): paused true, remainMs == 1440000; epoch += 500000; apply("resume",0): paused false, endEpoch == epoch + 1440000
t("toggle", ...)                    # IDLE->FOCUS, ->paused, ->running
t("skip_focus_no_cue", ...)         # start; apply("skip",0): phase "SHORT", cycle 0, log size 1 with ok false, calls_of("notify") empty
t("skip_break_to_focus", ...)       # from SHORT apply("skip",0): phase "FOCUS", log unchanged
t("stop_resets", ...)               # start; p.cycle = 2; apply("stop",0): phase "IDLE", cycle 0, last log ok false, calls_of("rotation")[-1] == ["rotation","resume"]
t("timeup_to_short_break", ...)     # start; epoch = endEpoch; p.loop(): phase "SHORT", cycle 1, log[-1]["ok"] == true, endEpoch == epoch + 300000
t("fourth_focus_long_break", ...)   # three times (start, epoch=endEpoch, loop(), skip the break) then a fourth: phase "LONG", cycle 0
t("overdue_under_cutoff_advances", ...)  # epoch = endEpoch + 299999; loop(): phase "SHORT"
t("overdue_at_cutoff_idles", ...)   # epoch = endEpoch + 300000; loop(): phase "IDLE", log[-1]["ok"] == false, no notify
t("loop_without_time_is_noop", ...) # clock["epoch"] = -1; start via store (phase FOCUS, endEpoch 5); loop(): phase still "FOCUS", no rotation calls
t("restore_from_store", ...)        # store seeded with phase "FOCUS", endEpoch epoch+100000, cycle 2 → load_pomo(): members match; rotation show+pause called by init when epoch valid
```

- [ ] **Step 3: Run to verify they fail** `tools/berry tests/run.be` → FAIL lines (file missing / attribute errors).

- [ ] **Step 4: Write `pomo.be`** with the header lines (`# @name pomo`, `# @desc Pomodoro timer`, `# @version 0.1`, five `# @config` lines per Global Constraints) and the methods above. `loop()` for now: return if `epoch_ms() <= 0`; if running and not paused and `epoch_ms() >= endEpoch`: overdue → `go_idle(true)` if `>= 300000` else `advance(true)`. Notify in `advance(true)` is added in Task 5; here `advance` only logs and enters.

- [ ] **Step 5: Run to verify 15 tests pass.** Also check memory hygiene by eye: no `+` string building or list/map literals in `draw()` (none yet).

- [ ] **Step 6: Commit** `git add pomo && git commit -m "feat(pomo): Berry test harness and pomodoro state machine"`

---

### Task 3: Commands from the store and persistence

**Files:**
- Modify: `pomo/pomo.be` (`init()`), Create: `pomo/tests/test_commands.be`

**Interfaces:**
- `init()`: `load()`; if `store.get("cmd", "") != ""` and `epoch_ms() > 0`: `apply(cmd, store.get("cmdMinutes", 0))`, then `store.set("cmd", "")`, `store.set("cmdMinutes", 0)`. If epoch invalid, leave `cmd` in the store; `loop()` checks `store.get("cmd","")` on the first valid tick and applies it the same way.
- `save()` must not write `cmd`/`cmdMinutes`/`log` except where they change.

- [ ] **Step 1: Write the failing tests**

```
t("cmd_applied_on_init", ...)       # store cmd "start", cmdMinutes 30 → load_pomo(): phase FOCUS, totalMs 1800000, store cmd "" and cmdMinutes 0
t("cmd_cleared_even_if_ignored", ...)   # store phase "IDLE", cmd "pause" → load_pomo(): IDLE, cmd ""
t("cmd_pending_without_time", ...)  # clock epoch -1, cmd "start" → load_pomo(): IDLE, store cmd still "start"; then clock epoch 1000000; p.loop(): FOCUS, cmd ""   (Review Focus 5)
t("restart_mid_phase_keeps_state", ...) # start; epoch += 100000; p2 = load_pomo(): p2.endEpoch == p.endEpoch, cycle equal, phase equal
t("log_capped_at_50", ...)          # 55 × (start, skip): size(store.data["log"]) == 50 and the oldest kept is the 6th
```

- [ ] **Step 2–4:** run (fail), implement, run (20 pass total).

- [ ] **Step 5: Commit** `git add pomo && git commit -m "feat(pomo): apply CLI commands from the store on restart"`

---

### Task 4: Buttons

**Files:**
- Modify: `pomo/pomo.be` (`on_button_event`), Create: `pomo/tests/test_buttons.be`

**Interfaces:**
- `on_button_event(btn, event)` per the spec table. Left/right: `press` → set `leftLong=false`/`rightLong=false`, return `true`. `long` → mark the flag; left long in IDLE → `apply("start", 0)`; right long while running/paused → `apply("stop", 0)`. `release` → if flag not set: IDLE: left → `rotation.previous()`, right → `rotation.next()`; running/paused: left → `apply("toggle",0)`, right → `apply("skip",0)`. Always return `true` after a taken press. Select: `press` → `true`; `release` → `apply("toggle", 0)` **only if Task 1 (a) allowed select**; otherwise select events return `false`. A `release` for a button whose `press` was not seen (flag `nil`) → return `false`, no action. Any other button name → `false`.

- [ ] **Step 1: Write the failing tests**

```
t("idle_left_short_navigates", ...)     # press,release → calls_of("rotation") == [["rotation","previous"]], phase IDLE
t("idle_right_short_navigates", ...)    # → [["rotation","next"]]
t("idle_left_long_starts", ...)         # press,long,release → FOCUS; exactly one start (no toggle on release)
t("running_left_short_toggles", ...)    # start; press,release → paused true; again → false
t("running_right_short_skips", ...)     # → phase SHORT
t("running_right_long_stops", ...)      # press,long,repeat,repeat,release → IDLE, and release did not skip
t("running_left_long_nothing", ...)     # press,long,release → still FOCUS, not paused
t("release_without_press_ignored", ...) # fresh instance, on_button_event("left","release") == false, no calls   (Review Focus 1)
t("press_returns_true", ...)            # on_button_event("left","press") == true; ("right","press") == true
t("select_tap_toggles", ...)            # IDLE: press,release → FOCUS   (skip this test if Task 1 dropped select; then assert select returns false)
t("unknown_button_false", ...)          # ("menu","press") == false
```

- [ ] **Step 2–4:** run (fail), implement, run (all pass).

- [ ] **Step 5: Commit** `git add pomo && git commit -m "feat(pomo): button handling with short/long and idle navigation"`

---

### Task 5: Display and cues

**Files:**
- Modify: `pomo/pomo.be` (`loop()` rebuild, `draw()`, `advance()` cue), Create: `pomo/tests/test_display.be`

**Interfaces:**
- In `loop()` after the time logic: `label` = `format("%02d:%02d", mm, ss)` from remaining (clamped ≥ 0), or `"--:--"` when epoch invalid and a phase is stored, or `"POMO"` when IDLE; `pct` = `remaining * 100 / totalMs` (integer, 0–100); `color` per phase. These three are the only strings/numbers `draw()` reads.
- `draw()`: `clear()`; IDLE → `font("small")`, `text((32 - text_ink_width(label)) / 2, 6, label, 0xFF8C00)`; running/paused → `font("large")`, draw the label the same way in `color` unless paused and `(now_ms() / 600) % 2 == 1`; then `progress(pct, color, 0x202020)` (skipped when label is `"--:--"`).
- `advance(true)` sends `notify({"text": T, "textColor": "#RRGGBB" string of the next color, "durationMs": 4000, "scroll": {"mode": "static"}})` plus `"sound": {"rtttl": melody}` when `store.get("sound", true)`. Build the two notification maps once in `init()` (fields `cueBreak`, `cueFocus`), not in `advance`.
- Melodies: builder's choice, each under 80 chars, one for "to break", one for "to focus".

- [ ] **Step 1: Write the failing tests**

```
t("idle_draw", ...)                 # loop(); draw(): calls include ["font","small"], a ["text", x, 6, "POMO", 0xFF8C00] with x == (32-15)/2, and no progress
t("running_label_and_bar", ...)     # start; epoch += 66000; loop(); draw(): ["font","large"], text "23:54" color 0xFF8C00, ["progress", 95, 0xFF8C00, 0x202020]
t("break_color", ...)               # after timeup: text color 0x00C8B4, progress color 0x00C8B4
t("paused_blinks", ...)             # pause; clock ms 0 → text drawn; ms 600 → no text call; ms 1200 → drawn; progress drawn both times
t("no_time_shows_dashes", ...)      # epoch -1 with stored FOCUS; loop(); draw(): text "--:--", no progress, no rotation calls
t("cue_on_timeup", ...)             # notify called once with text "BREAK", textColor "#00C8B4", durationMs 4000, sound map with key "rtttl"
t("cue_rest_and_focus_texts", ...)  # LONG → "REST"; break timeup → "FOCUS" with textColor "#FF8C00"
t("cue_without_sound", ...)         # store sound=false → notify map has no "sound" key
t("skip_sends_no_cue", ...)
```

- [ ] **Step 2–4:** run (fail), implement, run (all pass). Then eyeball `draw()`: only calls and member reads, no `+`, no literals.

- [ ] **Step 5: Commit** `git add pomo && git commit -m "feat(pomo): display, blink, progress bar and phase cues"`

---

### Task 6: Python config and clock client

**Files:**
- Create: `pomo/pomo/__init__.py`, `pomo/pomo/config.py`, `pomo/pomo/client.py`, `pomo/tests/__init__.py`, `pomo/tests/fakes.py`, `pomo/tests/test_client.py`

**Interfaces:**
- `config.py`: `DEFAULT_CLOCK = "http://clock.local"`, `CONFIG_PATH = Path("~/.config/pomo/config.json").expanduser()`, `load_config(path=CONFIG_PATH) -> dict` returning `{"clock": url}`; missing file → default and `warned=True` key so the CLI can print once; invalid JSON → default.
- `client.py`: `class ClockUnreachable(Exception)`, `class NotInstalled(Exception)`, `class ClockError(Exception)` (non-2xx with body). `class ClockClient(base_url: str, timeout: float = 5.0)` with `get_data() -> dict`, `patch_data(d: dict) -> dict`, `get_config() -> dict` (flattened `key -> value` from `fields`), `patch_config(d: dict) -> dict`, `put_script(name: str, source: str) -> dict` (the reply JSON), `get_apps() -> list`, `put_order(order: list, disabled: list) -> None`, `put_active(name: str) -> None`, `get_screen() -> dict`. 404 on data/config → `NotInstalled`; connection errors/timeouts → `ClockUnreachable`.
- `fakes.py`: `class FakeNG` wrapping `http.server.ThreadingHTTPServer` on port 0 with `.url`, `.data` (dict), `.config` (dict of key→value, served in NG `fields` shape with defaults), `.script` (last uploaded source), `.script_error` (None or dict to return), `.order` (last PUT body), `.active`, `.apps` (list), `.screen` (dict), `.installed` (bool; False → 404 on data/config), `.requests` (list of (method, path, body)). `start()`, `stop()`.

- [ ] **Step 1: Write the failing tests**

```python
def test_get_data_and_patch_merge(self)         # patch_data({"cmd":"start"}) → fake.data has cmd; request content-type application/json
def test_not_installed_raises(self)             # fake.installed=False → NotInstalled
def test_get_config_flattens(self)              # {"focus":25,...}
def test_put_script_raw_and_error(self)         # body == source, no JSON content type; returns {"error": None}; with fake.script_error set returns it
def test_unreachable(self)                      # base_url "http://127.0.0.1:1" → ClockUnreachable within 3 s
def test_load_config_defaults(self)             # missing → {"clock": "http://clock.local", "warned": True}
```

- [ ] **Step 2–4:** run (fail), implement, run (6 pass).

- [ ] **Step 5: Commit** `git add pomo && git commit -m "feat(pomo): clock HTTP client and config"`

---

### Task 7: Status and log formatting

**Files:**
- Create: `pomo/pomo/status.py`, `pomo/tests/test_status.py`

**Interfaces:**
- `status_line(data: dict, config: dict, now_ms: int) -> str`: `IDLE` when `data.get("phase","IDLE") == "IDLE"`; else `<NAME>[ (paused)] MM:SS left, cycle N/E` with NAME `FOCUS|BREAK|REST`, remaining = `remainMs` if paused else `max(0, endEpoch - now_ms)`, `E = config.get("every", 4)`.
- `log_lines(data: dict, n: int) -> list[str]`: newest first, `YYYY-MM-DD HH:MM  25 min  done|aborted` in local time.
- `render_screen(screen: dict) -> str`: `█` for non-zero pixel, `·` otherwise, `height` rows of `width` chars.

- [ ] **Step 1: Write the failing tests**

```python
def test_idle_and_empty(self)        # status_line({}, {}, 0) == "IDLE"   (Review Focus 3)
def test_running(self)               # FOCUS, endEpoch = now+1394000 → "FOCUS 23:14 left, cycle 1/4"
def test_paused(self)                # "FOCUS (paused) 10:00 left, cycle 2/4"
def test_break_names(self)           # SHORT → BREAK, LONG → REST
def test_overdue_clamps_to_zero(self)
def test_log_lines(self)             # 3 entries, n=2 → 2 lines newest first, "done"/"aborted"
def test_render_screen(self)         # 2x2 → "█·\n·█"
```

- [ ] **Step 2–4:** run (fail), implement, run. **Step 5: Commit** `git commit -m "feat(pomo): status and log formatting"`

---

### Task 8: CLI

**Files:**
- Create: `pomo/pomo/cli.py`, `pomo/bin/pomo`, `pomo/tests/test_cli.py`

**Interfaces:**
- `main(argv: list[str], *, client_factory=ClockClient, config_path=CONFIG_PATH, out=sys.stdout, err=sys.stderr, now_ms=lambda: int(time.time()*1000)) -> int`.
- Verbs: `start [MINUTES]`, `pause`, `resume`, `toggle`, `skip`, `stop` → `send_command(client, cmd, minutes)` = `patch_data({"cmd": cmd, "cmdMinutes": minutes or 0})` (Outcome B from Task 1: merge `get_data()` into the body first), then `get_data()` and print `status_line`. `status`, `config` (prints `key = value` for the five keys), `config KEY VALUE` (`patch_config({KEY: parsed})`; `sound` accepts true/false/on/off/1/0; unknown key or bad value → stderr, exit 2), `log [N]` (default 10), `screen`. `install` is Task 9 (stub returning 2 with "not implemented" here).
- Errors: bad MINUTES → `minutes must be a positive integer` on stderr, exit 2, no request; `ClockUnreachable` → `cannot reach clock at <url>` exit 1; `NotInstalled` → `pomo is not installed on the clock; run: pomo install` exit 1; no verb → usage, exit 2. If `load_config` warned, print `using default clock url http://clock.local (no ~/.config/pomo/config.json)` to stderr once.
- `bin/pomo`: `exec /Library/Frameworks/Python.framework/Versions/3.13/bin/python3 -m pomo.cli "$@"` with `PYTHONPATH` = script's parent dir; `chmod +x`.

- [ ] **Step 1: Write the failing tests** (each starts a `FakeNG` with `installed=True`, `config={"focus":25,"shortBreak":5,"longBreak":15,"every":4,"sound":True}`):

```python
def test_start_sends_cmd_and_prints_status(self)   # fake.data gets cmd "start", cmdMinutes 0; after the PATCH the fake sets phase FOCUS/endEpoch itself (simulate the script) → out "FOCUS 25:00 left, cycle 0/4"
def test_start_minutes(self)                        # cmdMinutes 40
def test_bad_minutes(self)                          # "0", "-3", "abc" → exit 2, err contains "minutes", fake.requests empty   (Review Focus 2)
def test_status_idle(self)
def test_config_print_and_set(self)                 # ["config"] prints 5 lines; ["config","focus","30"] → fake.config focus 30; ["config","sound","off"] → False; ["config","nope","1"] → exit 2
def test_log(self)
def test_unreachable_and_not_installed(self)        # exit 1 with the two messages
def test_screen(self)
```

- [ ] **Step 2–4:** run (fail), implement, run. **Step 5:** `./bin/pomo status` against the real clock prints the not-installed message, exit 1. **Step 6: Commit** `git commit -m "feat(pomo): pomo CLI"`

---

### Task 9: Install verb and README

**Files:**
- Modify: `pomo/pomo/cli.py`; Create: `pomo/tests/test_install.py`, `pomo/README.md`

**Interfaces:**
- `install(client, source_path=Path(__file__).parent.parent / "pomo.be", out, err) -> int`: `put_script("pomo", source)`; if reply `error` is not `None` → print `install failed: <message> (line <n>)`, return 1, no further calls (Review Focus 4). Then `get_apps()`; build `order` = current in-loop names by `slot`, with `pomo` removed and re-inserted right after `Time` (appended if no `Time`); `disabled` = names with `enabled == False`; `put_order(order, disabled)`; print `installed pomo (after Time in rotation)`; return 0.
- README: what it is, flashing pointer (`firmware/`), `pomo install`, verbs, button table (as finalized in Task 1), config keys and that they're also in the web UI under Apps ⚙, how status is computed, where the log lives (on the clock, `pomo log`), uninstall (`curl -X DELETE http://clock.local/api/v1/apps/pomo`).

- [ ] **Step 1: Write the failing tests**

```python
def test_install_uploads_and_orders(self)   # fake.apps = Time, Date, Temperature (enabled), Battery (disabled) → fake.script == file contents; fake.order == {"order":["Time","pomo","Date","Temperature"],"disabled":["Battery"]}; exit 0
def test_install_compile_error(self)        # fake.script_error = {"message":"syntax_error: x","line":12} → exit 1, err contains "line 12", fake.order is None
```

- [ ] **Step 2–4:** run (fail), implement, run all Python tests (`python3 -m unittest discover -s tests -v`) and Berry tests → all pass. Write README.

- [ ] **Step 5: Commit** `git add pomo && git commit -m "feat(pomo): install verb and README"`

---

### Task 10: Hardware verification

- [ ] **Step 1:** `cd ~/Workspace/tc001/pomo && ./bin/pomo install` → `installed pomo (after Time in rotation)`. `curl -s http://192.168.1.7/api/v1/apps | python3 -m json.tool | grep -A3 '"pomo"'` shows `"error": null`.
- [ ] **Step 2:** `pomo start 1` → `FOCUS 01:00 left, cycle 0/4`; `pomo screen` shows large digits and a bar on row 7; wait 10 s, `pomo screen` again still shows the timer (rotation paused).
- [ ] **Step 3:** After ~65 s the clock plays the melody and shows BREAK; `pomo status` → `BREAK 04:5x left, cycle 1/4`; `pomo log 1` shows one `done` line.
- [ ] **Step 4 (owner presses):** left tap → `(paused)`; left tap → running; right tap → `FOCUS ...`; right hold → `IDLE`; the rotation resumes (wait 10 s, `pomo screen` shows the time page). From the time page: right → idle `POMO` page; select tap (or left hold) → FOCUS.
- [ ] **Step 5:** During a block: `pomo config focus 30` (script restarts) → `pomo status` still shows the same phase and remaining time; next focus uses 30. Reboot the clock (`curl -X POST .../device/reboot`) mid-block; after ~20 s `pomo status` shows the same phase, remaining continued.
- [ ] **Step 6:** Memory: `curl -s http://192.168.1.7/api/v1/logs | grep "vm heap"` and `GET /api/v1/device` `freeHeapBytes` > 60000 after an hour of running.
- [ ] **Step 7:** Commit any fixes; `git tag pomo-v0.1`.
