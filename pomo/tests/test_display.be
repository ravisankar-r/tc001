# Display and cue tests
import global

def ready()
  fresh()
  clock["epoch"] = 1000000
  var p = load_pomo()
  reset_calls()
  return p
end

def text_calls() return calls_of("text") end

t("idle_draw", def ()
  var p = ready()
  p.loop()
  p.draw()
  assert(size(calls_of("font")) == 1 && calls_of("font")[0][1] == "small", "small font")
  var tc = text_calls()
  assert(size(tc) == 1, "one text")
  assert(tc[0][1] == (32 - 15) / 2 && tc[0][2] == 6 && tc[0][3] == "POMO" && tc[0][4] == 0xFF8C00, "POMO centered orange")
  assert(size(calls_of("progress")) == 0, "no bar")
end)

t("running_label_and_bar", def ()
  var p = ready()
  p.apply("start", 0)
  clock["epoch"] += 66000
  p.loop()
  reset_calls()
  p.draw()
  assert(calls_of("font")[0][1] == "large", "large font")
  var tc = text_calls()
  assert(tc[0][3] == "23:54" && tc[0][4] == 0xFF8C00, "label " + str(tc[0][3]))
  var pr = calls_of("progress")
  assert(size(pr) == 1 && pr[0][1] == 95 && pr[0][2] == 0xFF8C00 && pr[0][3] == 0x202020, "progress")
end)

t("break_color", def ()
  var p = ready()
  p.apply("start", 0)
  clock["epoch"] = p.endEpoch
  p.loop()
  reset_calls()
  p.draw()
  assert(text_calls()[0][4] == 0x00C8B4, "teal text")
  assert(calls_of("progress")[0][2] == 0x00C8B4, "teal bar")
end)

t("paused_blinks", def ()
  var p = ready()
  p.apply("start", 0)
  p.apply("pause", 0)
  p.loop()
  clock["ms"] = 0
  reset_calls()
  p.draw()
  assert(size(text_calls()) == 1 && size(calls_of("progress")) == 1, "drawn at 0")
  clock["ms"] = 600
  reset_calls()
  p.draw()
  assert(size(text_calls()) == 0 && size(calls_of("progress")) == 1, "hidden at 600")
  clock["ms"] = 1200
  reset_calls()
  p.draw()
  assert(size(text_calls()) == 1, "drawn at 1200")
end)

t("no_time_shows_dashes", def ()
  fresh()
  store.data["phase"] = "FOCUS"
  store.data["endEpoch"] = 5
  store.data["totalMs"] = 1500000
  var p = load_pomo()
  p.loop()
  reset_calls()
  p.draw()
  assert(text_calls()[0][3] == "--:--", "dashes")
  assert(size(calls_of("progress")) == 0, "no bar")
  assert(size(calls_of("rotation")) == 0, "no rotation calls")
end)

t("cue_on_timeup", def ()
  var p = ready()
  p.apply("start", 0)
  clock["epoch"] = p.endEpoch
  reset_calls()
  p.loop()
  var n = calls_of("notify")
  assert(size(n) == 1, "one notify")
  var m = n[0][1]
  assert(m["text"] == "BREAK" && m["textColor"] == "#00C8B4" && m["durationMs"] == 4000, "payload")
  assert(m["scroll"]["mode"] == "static", "static")
  assert(m["sound"].contains("rtttl") && size(m["sound"]["rtttl"]) > 0, "rtttl")
end)

t("cue_rest_and_focus_texts", def ()
  var p = ready()
  for i : 1 .. 3
    p.apply("start", 0)
    clock["epoch"] = p.endEpoch
    p.loop()
    p.apply("skip", 0)
  end
  p.apply("start", 0)
  clock["epoch"] = p.endEpoch
  reset_calls()
  p.loop()
  assert(calls_of("notify")[0][1]["text"] == "REST", "REST")
  clock["epoch"] = p.endEpoch
  reset_calls()
  p.loop()
  var m = calls_of("notify")[0][1]
  assert(m["text"] == "FOCUS" && m["textColor"] == "#FF8C00", "FOCUS orange")
end)

t("cue_without_sound", def ()
  var p = ready()
  store.data["sound"] = false
  p = load_pomo()
  p.apply("start", 0)
  clock["epoch"] = p.endEpoch
  reset_calls()
  p.loop()
  assert(!calls_of("notify")[0][1].contains("sound"), "no sound key")
end)

t("skip_sends_no_cue", def ()
  var p = ready()
  p.apply("start", 0)
  reset_calls()
  p.apply("skip", 0)
  assert(size(calls_of("notify")) == 0, "no notify")
end)
