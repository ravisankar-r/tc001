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
