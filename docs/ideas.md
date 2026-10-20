# Ideas for the clock (parked 2026-10-20)

What else the TC001 could show or do now that it runs AWTRIX NG with the
pomodoro timer. Grouped by effort. Nothing here is built.

## One-liners: a curl or cron job on the Mac, no code on the clock

- **Any script's "done" signal.** Claude Code finished, tests passed, deploy done,
  long download complete: `POST /api/v1/notifications` with a color and a melody.
  Hook into Claude Code's Stop hook, Makefiles, CI webhooks.
- **Build / CI status indicator.** Use the three corner indicators
  (`PUT /api/v1/indicators/{1,2,3}`) as green / amber / red dots beside the time
  without taking over the display.
- **Appointment nudges.** Cron job posting "Standup in 10m" from the calendar.
- **Doorbell / appliance alerts** from anything on the LAN that can call a URL.

## Pushed apps: a page in the rotation, fed from the Mac or a small server

`PUT /api/v1/apps/pushed/<name>` with text, icon, color, progress, line chart.

- **Next meeting countdown** from Google Calendar; amber under 5 minutes.
- **USD→INR, a stock, or crypto** with a trend arrow and a 16-point line chart.
- **AQI for the city**, colored by band.
- **Habit streak** from the brain system: seven dots for the week plus the streak
  number, updated by the evening routine.
- **Cronpulse health**: one pixel per monitored job, green or red.
- **Job search dashboard**: applications pending, interviews today.

## Berry scripts on the clock: self-contained, work with the Mac off

Scripting guide: https://blueforcer.github.io/awtrix-ng/esp32/guides/scripting/

- **Is-it-raining / weather**: script fetches an API every 15 min (`http.get`),
  shows icon + temperature. The isitraining project could be the data source.
- **Countdown to a date** (trip, deadline). NG ships a recipe:
  https://blueforcer.github.io/awtrix-ng/esp32/tutorials/recipe-countdown/
- **Word clock, binary clock, or a second timezone.**
- **Room comfort hint** from the built-in sensors (`sensor.temperature()`,
  `sensor.humidity()`): "open a window" past a humidity threshold.
- **Tiny games** on the three buttons: reaction timer, two-button Pong, dice roll.
  `draw()` runs at ~40 fps.
- **Ambient modes**: built-in effects (plasma, fireworks, matrix rain) and mood
  light in the evening, triggered by time or the light sensor.

## Suggested first two

1. Claude Code "done" hook (notification; exercises the interrupt path).
2. Next-meeting countdown (pushed app; exercises the page path).
Every other idea follows one of those two patterns.

## Things learned building the pomodoro that apply to all of these

- Don't upload script source with curl; use Python `urllib` (it reboots the clock).
- `epoch_ms()` is -1 until NTP syncs, about the first 5 s after boot.
- Keep allocations out of `draw()`; rebuild strings once a second in `loop()`.
- `store.set()` writes flash within 5 s; only write on state changes.
- 96 KB shared script heap; the pomodoro script takes ~12 KB.
