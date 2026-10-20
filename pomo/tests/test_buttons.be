# Button handling tests
import global

def idle()
  fresh()
  clock["epoch"] = 1000000
  var p = load_pomo()
  reset_calls()
  return p
end

def running()
  var p = idle()
  p.apply("start", 0)
  reset_calls()
  return p
end

def tap(p, btn)
  p.on_button_event(btn, "press")
  p.on_button_event(btn, "release")
end

def hold(p, btn)
  p.on_button_event(btn, "press")
  p.on_button_event(btn, "long")
  p.on_button_event(btn, "repeat")
  p.on_button_event(btn, "repeat")
  p.on_button_event(btn, "release")
end

t("idle_left_short_navigates", def ()
  var p = idle()
  tap(p, "left")
  var r = calls_of("rotation")
  assert(size(r) == 1 && r[0][1] == "previous", "previous")
  assert(p.phase == "IDLE", "still idle")
end)

t("idle_right_short_navigates", def ()
  var p = idle()
  tap(p, "right")
  var r = calls_of("rotation")
  assert(size(r) == 1 && r[0][1] == "next", "next")
end)

t("idle_left_long_starts", def ()
  var p = idle()
  hold(p, "left")
  assert(p.phase == "FOCUS" && !p.paused, "started once, not toggled on release")
end)

t("running_left_short_toggles", def ()
  var p = running()
  tap(p, "left")
  assert(p.paused, "paused")
  tap(p, "left")
  assert(!p.paused, "resumed")
end)

t("running_right_short_skips", def ()
  var p = running()
  tap(p, "right")
  assert(p.phase == "SHORT", "skipped to break")
end)

t("running_right_long_stops", def ()
  var p = running()
  hold(p, "right")
  assert(p.phase == "IDLE", "stopped")
  assert(size(store.data["log"]) == 1, "release did not also skip")
end)

t("running_left_long_nothing", def ()
  var p = running()
  hold(p, "left")
  assert(p.phase == "FOCUS" && !p.paused, "unchanged")
end)

t("release_without_press_ignored", def ()
  var p = idle()
  var r = p.on_button_event("left", "release")
  assert(r == false, "returns false")
  assert(size(calls) == 0, "no calls")
  assert(p.phase == "IDLE", "idle")
end)

t("press_returns_true", def ()
  var p = idle()
  assert(p.on_button_event("left", "press") == true, "left")
  assert(p.on_button_event("right", "press") == true, "right")
end)

t("select_tap_toggles", def ()
  var p = idle()
  tap(p, "select")
  assert(p.phase == "FOCUS", "started")
  tap(p, "select")
  assert(p.paused, "paused")
end)

t("select_hold_without_release_does_nothing", def ()
  var p = idle()
  p.on_button_event("select", "press")
  assert(p.phase == "IDLE", "press alone is not a tap")
end)

t("unknown_button_false", def ()
  var p = idle()
  assert(p.on_button_event("menu", "press") == false, "unknown")
end)
