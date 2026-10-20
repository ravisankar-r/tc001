# tc001: hacking the Ulanzi TC001 pixel clock

Everything for a Ulanzi TC001 (32×8 RGB LED matrix, ESP32-D0WD, 4 MB flash)
that was reflashed from the stock firmware to AWTRIX NG and now runs a
pomodoro timer. Start here when picking this up again.

## State of the clock (as of 2026-10-20)

| | |
|---|---|
| Firmware | AWTRIX NG 1.2.2 (`firmware/awtrix-ng/usb-awtrix-ng-4mb.bin`, not in git) |
| Hostname | `clock` (mDNS `clock.local`, unreliable on this network) |
| Address | DHCP; was 192.168.1.7, then 192.168.1.102. Give it a DHCP reservation. |
| Timezone | `IST-5:30` / Asia/Kolkata, NTP `in.pool.ntp.org` (set via `PUT /api/v1/system`) |
| Time style | big digits (`timeMode` 5 on the built-in Time app) |
| Rotation | Time, pomo, Date, Temperature, Humidity, Battery |
| Scripts | `pomo` (this repo's `pomo/pomo.be`) |
| Web UI | `http://<address>/` |
| API | `http://<address>/api/v1/...` (JSON bodies need `Content-Type: application/json`) |

Find the clock when its address is unknown:

```
for i in $(seq 1 254); do curl -s -m 1 http://192.168.1.$i/api/v1/version | grep -q 1.2 && echo 192.168.1.$i; done
```

## Layout

```
firmware/   flashing scripts and (gitignored) images; see below
pomo/       the pomodoro timer: Berry script for the clock + `pomo` CLI for the Mac (its own README)
docs/superpowers/specs/   design documents (the NG one is current; the AWTRIX 3 one is superseded)
docs/superpowers/plans/   the implementation plan that was executed
docs/ideas.md             parked ideas for what else to put on the clock
probe/      throwaway Berry script used to verify button, store and rotation behaviour
tools/      build-berry.sh builds the reference Berry interpreter used by the tests
```

## Firmware history

1. **Stock Ulanzi firmware** was dumped in full before anything else:
   `firmware/tc001-stock-backup.bin` (4 MB, kept out of git). `firmware/restore-stock.sh`
   writes it back and returns the clock to factory state.
2. **AWTRIX 3 v0.98** was flashed first (`firmware/flash-awtrix.sh`). It works but the
   project is archived, so it was replaced the same day.
3. **AWTRIX NG 1.2.2** is what runs now (`firmware/flash-awtrix-ng.sh`). It has a different
   HTTP API (`/api/v1/`) and on-device Berry scripting, which is what makes the pomodoro
   run on the clock itself. Docs: https://blueforcer.github.io/awtrix-ng/esp32/

Flashing goes over USB-C. The clock shows up as `/dev/cu.usbserial-*` (CH340, no driver
needed). `esptool` is installed with `pip3 install --user esptool`.

## Hard-won facts

- **Use 115200 baud for esptool writes.** 230400 and above fail intermittently through a
  USB hub. Retry on "Failed to communicate with the flash chip"; it is transient.
- **Opening the USB serial port from the Mac resets the clock** (the CH340 toggles the
  ESP32's EN line). Don't read the serial log while testing anything.
- **Don't upload script source with curl.** `curl -X PUT .../api/v1/apps/script/<name>` reboots
  the clock, with or without `Expect: 100-continue`. Python `urllib` (what the `pomo` CLI
  uses) works fine.
- `PATCH /api/v1/apps/<name>/data` restarts the script and keeps unflushed `store` values.
  That restart is how the Mac sends the script a command.
- `GET /api/v1/apps` reports `slot` as null on this firmware; the list is in rotation order.
- `GET /api/v1/display/screen` returns the framebuffer; `pomo screen` renders it as text, which
  is how the display was verified without looking at it.
- Holding the select button opens the device menu and delivers only a `press` to the shown
  script, never a `release`. Left/right `long` fires at 500 ms.
- After a reboot the script restores about 3 s in, before NTP has synced; `epoch_ms()` is
  `-1` until then and the script must not act on time until it is valid.

## Pomodoro quick start

```
cd pomo
./bin/pomo install      # upload the script, place it after Time
./bin/pomo start        # or press right from the time page, then tap select
./bin/pomo status
```

Buttons, CLI verbs, config keys and the design are in `pomo/README.md` and
`docs/superpowers/specs/2026-10-20-pomodoro-ng-design.md`.

## Tests

```
./tools/build-berry.sh                       # once
cd pomo && ../tools/berry tests/run.be       # 47 Berry tests against a stub harness
python3 -m unittest discover -s tests -v     # 27 Python tests against a fake clock
```
