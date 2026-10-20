# State machine tests for pomo.be
import global

def start_at(epoch)
  fresh()
  clock["epoch"] = epoch
  var p = load_pomo()
  return p
end

t("idle_initially", def ()
  var p = start_at(1000000)
  assert(p.phase == "IDLE", "phase")
  assert(p.duration() == 3000, "duration")
  assert(!store.data.contains("phase"), "nothing written yet")
end)

t("start_enters_focus", def ()
  var p = start_at(1000000)
  reset_calls()
  p.apply("start", 0)
  assert(p.phase == "FOCUS", "phase")
  assert(p.endEpoch == 1000000 + 25 * 60000, "endEpoch " + str(p.endEpoch))
  assert(p.totalMs == 1500000, "totalMs")
  var r = calls_of("rotation")
  assert(size(r) == 2 && r[0][1] == "show" && r[1][1] == "pause", "rotation show+pause")
  assert(store.data["phase"] == "FOCUS", "stored phase")
  assert(p.duration() == 0, "duration running")
end)

t("start_minutes_override", def ()
  var p = start_at(1000000)
  p.apply("start", 45)
  assert(p.endEpoch - p.startedEpoch == 2700000, "45 min")
end)

t("start_while_running_ignored", def ()
  var p = start_at(1000000)
  p.apply("start", 0)
  var e = p.endEpoch
  var w = store.writes
  clock["epoch"] = 1000000 + 5000
  p.apply("start", 0)
  assert(p.endEpoch == e, "endEpoch unchanged")
  assert(store.writes == w, "no extra writes")
end)

t("pause_resume", def ()
  var p = start_at(1000000)
  p.apply("start", 0)
  clock["epoch"] += 60000
  p.apply("pause", 0)
  assert(p.paused, "paused")
  assert(p.remainMs == 1440000, "remainMs " + str(p.remainMs))
  clock["epoch"] += 500000
  p.apply("resume", 0)
  assert(!p.paused, "resumed")
  assert(p.endEpoch == clock["epoch"] + 1440000, "endEpoch after resume")
end)

t("toggle", def ()
  var p = start_at(1000000)
  p.apply("toggle", 0)
  assert(p.phase == "FOCUS" && !p.paused, "idle->focus")
  p.apply("toggle", 0)
  assert(p.paused, "->paused")
  p.apply("toggle", 0)
  assert(!p.paused, "->running")
end)

t("skip_focus_no_cue", def ()
  var p = start_at(1000000)
  p.apply("start", 0)
  reset_calls()
  p.apply("skip", 0)
  assert(p.phase == "SHORT", "phase")
  assert(p.cycle == 0, "cycle")
  assert(size(store.data["log"]) == 1 && store.data["log"][0]["ok"] == false, "log aborted")
  assert(size(calls_of("notify")) == 0, "no notify")
end)

t("skip_break_to_focus", def ()
  var p = start_at(1000000)
  p.apply("start", 0)
  p.apply("skip", 0)
  var n = size(store.data["log"])
  p.apply("skip", 0)
  assert(p.phase == "FOCUS", "phase")
  assert(size(store.data["log"]) == n, "log unchanged")
end)

t("stop_resets", def ()
  var p = start_at(1000000)
  p.apply("start", 0)
  p.cycle = 2
  reset_calls()
  p.apply("stop", 0)
  assert(p.phase == "IDLE", "phase")
  assert(p.cycle == 0, "cycle")
  assert(store.data["log"][-1]["ok"] == false, "log aborted")
  var r = calls_of("rotation")
  assert(r[-1][1] == "resume", "rotation resume")
end)

t("timeup_to_short_break", def ()
  var p = start_at(1000000)
  p.apply("start", 0)
  clock["epoch"] = p.endEpoch
  p.loop()
  assert(p.phase == "SHORT", "phase")
  assert(p.cycle == 1, "cycle")
  assert(store.data["log"][-1]["ok"] == true, "log done")
  assert(p.endEpoch == clock["epoch"] + 300000, "break length")
end)

t("fourth_focus_long_break", def ()
  var p = start_at(1000000)
  for i : 1 .. 4
    p.apply("start", 0)
    clock["epoch"] = p.endEpoch
    p.loop()
    if i < 4
      assert(p.phase == "SHORT", "short after " + str(i))
      p.apply("skip", 0)
    end
  end
  assert(p.phase == "LONG", "long break")
  assert(p.cycle == 0, "cycle reset")
end)

t("overdue_under_cutoff_advances", def ()
  var p = start_at(1000000)
  p.apply("start", 0)
  clock["epoch"] = p.endEpoch + 299999
  p.loop()
  assert(p.phase == "SHORT", "phase")
end)

t("overdue_at_cutoff_idles", def ()
  var p = start_at(1000000)
  p.apply("start", 0)
  clock["epoch"] = p.endEpoch + 300000
  reset_calls()
  p.loop()
  assert(p.phase == "IDLE", "phase")
  assert(store.data["log"][-1]["ok"] == false, "log aborted")
  assert(size(calls_of("notify")) == 0, "no notify")
end)

t("loop_without_time_is_noop", def ()
  fresh()
  store.data["phase"] = "FOCUS"
  store.data["endEpoch"] = 5
  store.data["totalMs"] = 1500000
  var p = load_pomo()
  reset_calls()
  p.loop()
  assert(p.phase == "FOCUS", "phase")
  assert(size(calls_of("rotation")) == 0, "no rotation calls")
end)

t("restore_from_store", def ()
  fresh()
  clock["epoch"] = 1000000
  store.data["phase"] = "FOCUS"
  store.data["endEpoch"] = 1100000
  store.data["startedEpoch"] = 1000000 - 1400000
  store.data["totalMs"] = 1500000
  store.data["cycle"] = 2
  var p = load_pomo()
  assert(p.phase == "FOCUS" && p.endEpoch == 1100000 && p.cycle == 2, "members")
  var r = calls_of("rotation")
  assert(size(r) == 2 && r[0][1] == "show" && r[1][1] == "pause", "init re-pauses")
end)

t("pin_after_time_sync", def ()
  fresh()
  store.data["phase"] = "FOCUS"
  store.data["endEpoch"] = 1000000 + 900000
  store.data["totalMs"] = 1500000
  var p = load_pomo()
  p.loop()
  assert(size(calls_of("rotation")) == 0, "nothing while no time")
  clock["epoch"] = 1000000
  p.loop()
  var r = calls_of("rotation")
  assert(size(r) == 2 && r[0][1] == "show" && r[1][1] == "pause", "pinned on first valid tick")
  p.loop()
  assert(size(calls_of("rotation")) == 2, "pinned only once")
end)

# --- fixes from the final review ---

t("button_before_time_sync_changes_nothing", def ()
  fresh()
  store.data["phase"] = "FOCUS"
  store.data["endEpoch"] = 1000000 + 900000
  store.data["totalMs"] = 1500000
  var p = load_pomo()
  p.on_button_event("left", "press")
  p.on_button_event("left", "release")
  assert(!p.paused, "pause ignored before sync")
  assert(p.remainMs == 0, "no garbage remainMs")
  p.on_button_event("right", "press")
  p.on_button_event("right", "release")
  assert(p.phase == "FOCUS", "skip ignored before sync")
  assert(size(calls_of("rotation")) == 0, "no rotation calls before sync")
end)

t("idle_select_before_time_sync_does_not_start", def ()
  fresh()
  var p = load_pomo()
  p.on_button_event("select", "press")
  p.on_button_event("select", "release")
  assert(p.phase == "IDLE", "still idle")
  assert(!store.data.contains("log"), "nothing logged")
  p.on_button_event("right", "press")
  p.on_button_event("right", "release")
  assert(calls_of("rotation")[-1][1] == "next", "idle navigation still works")
end)

t("cmd_start_after_stale_phase_starts_fresh", def ()
  fresh()
  clock["epoch"] = 1000000
  store.data["phase"] = "FOCUS"
  store.data["endEpoch"] = 1000000 - 400000
  store.data["startedEpoch"] = 1000000 - 1900000
  store.data["totalMs"] = 1500000
  store.data["cmd"] = "start"
  var p = load_pomo()
  assert(p.phase == "FOCUS", "phase")
  assert(p.endEpoch == 1000000 + 1500000, "fresh block, not the stale one")
  assert(store.data["log"][-1]["ok"] == false, "stale block logged as aborted")
  assert(store.data["cmd"] == "", "cmd consumed")
end)

t("cmd_pause_on_stale_phase_does_not_freeze", def ()
  fresh()
  clock["epoch"] = 1000000
  store.data["phase"] = "FOCUS"
  store.data["endEpoch"] = 1000000 - 400000
  store.data["totalMs"] = 1500000
  store.data["cmd"] = "pause"
  var p = load_pomo()
  assert(p.phase == "IDLE", "stale phase ended, pause had nothing to pause")
  assert(!p.paused, "not paused")
end)

t("pause_at_timeup_ignored", def ()
  fresh()
  clock["epoch"] = 1000000
  var p = load_pomo()
  p.apply("start", 0)
  clock["epoch"] = p.endEpoch
  p.apply("pause", 0)
  assert(!p.paused, "pause in the last instant is ignored")
  p.loop()
  assert(p.phase == "SHORT", "phase ends normally")
end)
