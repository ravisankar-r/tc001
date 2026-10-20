# Command application from the store (what the CLI's PATCH /data triggers)
import global

t("cmd_applied_on_init", def ()
  fresh()
  clock["epoch"] = 1000000
  store.data["cmd"] = "start"
  store.data["cmdMinutes"] = 30
  var p = load_pomo()
  assert(p.phase == "FOCUS", "phase")
  assert(p.totalMs == 1800000, "30 min")
  assert(store.data["cmd"] == "" && store.data["cmdMinutes"] == 0, "cmd cleared")
end)

t("cmd_cleared_even_if_ignored", def ()
  fresh()
  clock["epoch"] = 1000000
  store.data["phase"] = "IDLE"
  store.data["cmd"] = "pause"
  var p = load_pomo()
  assert(p.phase == "IDLE", "still idle")
  assert(store.data["cmd"] == "", "cmd cleared")
end)

t("cmd_pending_without_time", def ()
  fresh()
  store.data["cmd"] = "start"
  var p = load_pomo()
  assert(p.phase == "IDLE", "idle while no time")
  assert(store.data["cmd"] == "start", "cmd still pending")
  clock["epoch"] = 1000000
  p.loop()
  assert(p.phase == "FOCUS", "applied on first valid tick")
  assert(store.data["cmd"] == "", "cmd cleared after loop")
end)

t("restart_mid_phase_keeps_state", def ()
  fresh()
  clock["epoch"] = 1000000
  var p = load_pomo()
  p.apply("start", 0)
  p.cycle = 2
  p.save()
  clock["epoch"] += 100000
  var p2 = load_pomo()
  assert(p2.endEpoch == p.endEpoch, "endEpoch")
  assert(p2.cycle == 2, "cycle")
  assert(p2.phase == "FOCUS", "phase")
end)

t("log_capped_at_50", def ()
  fresh()
  clock["epoch"] = 1000000
  var p = load_pomo()
  for i : 1 .. 55
    clock["epoch"] += 1000
    p.apply("start", 0)
    p.apply("skip", 0)
    p.apply("stop", 0)
  end
  var l = store.data["log"]
  assert(size(l) == 50, "size " + str(size(l)))
  assert(l[0]["s"] == 1000000 + 6 * 1000, "oldest kept is the 6th")
end)
