# pomo: a pomodoro timer on the Ulanzi TC001

The timer runs on the clock itself as a Berry script under AWTRIX NG 1.2.2.
The `pomo` command on the Mac controls it over Wi‑Fi; the clock's buttons
control it directly. Nothing runs on the Mac in the background.

## Setup

The clock must already run AWTRIX NG (see `../firmware/flash-awtrix-ng.sh`)
and be on your network. `clock.local` is the default address; if mDNS does not
resolve on your network, write the clock's IP to `~/.config/pomo/config.json`
and give the clock a DHCP reservation in your router so it stays put:

```json
{"clock": "http://192.168.1.NNN"}
```

Then:

```
cd ~/Workspace/tc001/pomo
./bin/pomo install        # uploads pomo.be and places it right after Time in the rotation
ln -s "$PWD/bin/pomo" ~/.local/bin/pomo   # optional, if ~/.local/bin is on your PATH
```

## From the Mac

```
pomo start [MINUTES]   start a focus block (MINUTES overrides this block only)
pomo pause | resume | toggle | skip | stop
pomo status            IDLE | FOCUS 23:14 left, cycle 1/4 | FOCUS (paused) ... | BREAK ... | REST ...
pomo config            print focus, shortBreak, longBreak, every, sound
pomo config focus 30   set one (applies from the next phase; also editable in the web UI under Apps ⚙)
pomo log [N]           last N focus blocks (kept on the clock, newest first)
pomo screen            render the clock's display as text
```

Status is computed from the end time the clock stores and your Mac's clock,
so both need correct time (NTP on both).

## On the clock

The `POMO` page sits right after the time page. Press right from the time
page to reach it.

| State | Left | Right | Select (middle) |
|---|---|---|---|
| Idle page | tap: previous page. Hold: **start** | tap: next page | tap: **start** |
| Running or paused | tap: pause / resume | tap: skip phase. Hold: stop | tap: pause / resume |

While a block runs the timer stays on screen (orange for focus, teal for
breaks, bar draining along the bottom). A phase end buzzes and flashes
BREAK, REST or FOCUS, then the next phase starts. Stopping returns the clock
to its normal rotation. Settings and the running phase survive reboots; a
phase found more than five minutes overdue after a reboot is quietly ended.

## Development

```
./tools/build-berry.sh                      # once, from the repo root
cd pomo && ../tools/berry tests/run.be      # Berry tests (state machine, buttons, display)
python3 -m unittest discover -s tests -v    # Python tests (CLI, client)
```

## Uninstall

```
curl -X DELETE http://clock.local/api/v1/apps/pomo
```
