# @name    pomo
# @desc    Pomodoro timer, driven by the clock buttons or the pomo CLI
# @version 0.1
# @config  focus      number "Focus minutes"      default=25 min=1 max=180
# @config  shortBreak number "Short break minutes" default=5  min=1 max=60
# @config  longBreak  number "Long break minutes"  default=15 min=1 max=60
# @config  every      number "Long break every"    default=4  min=1 max=12
# @config  sound      bool   "Sound"               default=true

class Pomo
  var phase, paused, endEpoch, remainMs, cycle, startedEpoch, totalMs
  var label, pct, color
  var leftLong, rightLong

  def init()
    self.load()
    if epoch_ms() > 0
      self.take_cmd()
      if self.phase != "IDLE"
        rotation.show()
        rotation.pause()
      end
    end
  end

  # Apply a command the CLI left in the store (PATCH /data restarts the script).
  def take_cmd()
    var cmd = store.get("cmd", "")
    if cmd == "" return end
    self.apply(cmd, store.get("cmdMinutes", 0))
    store.set("cmd", "")
    store.set("cmdMinutes", 0)
  end

  def load()
    self.phase = store.get("phase", "IDLE")
    self.paused = store.get("paused", false)
    self.endEpoch = store.get("endEpoch", 0)
    self.remainMs = store.get("remainMs", 0)
    self.cycle = store.get("cycle", 0)
    self.startedEpoch = store.get("startedEpoch", 0)
    self.totalMs = store.get("totalMs", 0)
  end

  def save()
    store.set("phase", self.phase)
    store.set("paused", self.paused)
    store.set("endEpoch", self.endEpoch)
    store.set("remainMs", self.remainMs)
    store.set("cycle", self.cycle)
    store.set("startedEpoch", self.startedEpoch)
    store.set("totalMs", self.totalMs)
  end

  # Record the end of a focus block; ok = completed naturally.
  def log_focus(ok)
    var l = store.get("log", nil)
    if l == nil l = [] end
    l.push({"s": self.startedEpoch, "e": epoch_ms(), "m": self.totalMs / 60000, "ok": ok})
    while size(l) > 50 l.remove(0) end
    store.set("log", l)
  end

  def enter(phase, minutes)
    self.phase = phase
    self.startedEpoch = epoch_ms()
    self.totalMs = minutes * 60000
    self.endEpoch = self.startedEpoch + self.totalMs
    self.remainMs = 0
    self.paused = false
    self.save()
    rotation.show()
    rotation.pause()
  end

  # Move to the next phase. withCue = the phase ended on its own (not skipped).
  def advance(withCue)
    if self.phase == "FOCUS"
      self.log_focus(withCue)
      if withCue self.cycle += 1 end
      if self.cycle >= store.get("every", 4)
        self.cycle = 0
        self.enter("LONG", store.get("longBreak", 15))
      else
        self.enter("SHORT", store.get("shortBreak", 5))
      end
    else
      self.enter("FOCUS", store.get("focus", 25))
    end
  end

  def go_idle()
    if self.phase == "FOCUS" self.log_focus(false) end
    self.phase = "IDLE"
    self.paused = false
    self.cycle = 0
    self.endEpoch = 0
    self.remainMs = 0
    self.save()
    rotation.resume()
  end

  def apply(cmd, minutes)
    var running = self.phase != "IDLE"
    if cmd == "start"
      if !running
        self.enter("FOCUS", minutes > 0 ? minutes : store.get("focus", 25))
      elif self.paused
        self.apply("resume", 0)
      end
    elif cmd == "pause"
      if running && !self.paused
        self.paused = true
        self.remainMs = self.endEpoch - epoch_ms()
        self.save()
      end
    elif cmd == "resume"
      if running && self.paused
        self.paused = false
        self.endEpoch = epoch_ms() + self.remainMs
        self.remainMs = 0
        self.save()
      end
    elif cmd == "toggle"
      if !running
        self.apply("start", minutes)
      elif self.paused
        self.apply("resume", 0)
      else
        self.apply("pause", 0)
      end
    elif cmd == "skip"
      if running self.advance(false) end
    elif cmd == "stop"
      if running self.go_idle() end
    end
  end

  def loop()
    var now = epoch_ms()
    if now <= 0 return end
    self.take_cmd()
    if self.phase != "IDLE" && !self.paused && now >= self.endEpoch
      if now - self.endEpoch >= 300000
        self.go_idle()
      else
        self.advance(true)
      end
    end
  end

  def should_show() return true end
  def duration() return self.phase == "IDLE" ? 3000 : 0 end
end

return Pomo()
