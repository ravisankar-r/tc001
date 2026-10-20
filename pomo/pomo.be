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
  var cueBreak, cueRest, cueFocus
  var leftLong, rightLong, selectDown
  var pinned   # rotation is parked on this app for the running phase

  def init()
    self.load()
    self.cueBreak = self.make_cue("BREAK", "#00C8B4", "tobreak:d=8,o=5,b=180:e,g,b")
    self.cueRest = self.make_cue("REST", "#00C8B4", "torest:d=8,o=5,b=140:e,g,b,4e6")
    self.cueFocus = self.make_cue("FOCUS", "#FF8C00", "tofocus:d=8,o=5,b=180:b,g,e")
    self.refresh(epoch_ms())
    self.pinned = false
    if epoch_ms() > 0
      self.settle(epoch_ms())
      self.take_cmd()
      self.pin()
    end
  end

  # End a phase whose time is up (with cue) or long overdue (quietly). Runs before commands.
  def settle(now)
    if self.phase != "IDLE" && !self.paused && now >= self.endEpoch
      if now - self.endEpoch >= 300000
        self.go_idle()
      else
        self.advance(true)
      end
    end
  end

  # Park the rotation on this app while a phase runs (once per phase).
  def pin()
    if self.phase == "IDLE" || self.pinned return end
    rotation.show()
    rotation.pause()
    self.pinned = true
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
    self.pinned = false
    self.pin()
  end

  # Move to the next phase. withCue = the phase ended on its own (not skipped).
  def advance(withCue)
    if self.phase == "FOCUS"
      self.log_focus(withCue)
      if withCue self.cycle += 1 end
      if self.cycle >= store.get("every", 4)
        self.cycle = 0
        self.enter("LONG", store.get("longBreak", 15))
        if withCue notify(self.cueRest) end
      else
        self.enter("SHORT", store.get("shortBreak", 5))
        if withCue notify(self.cueBreak) end
      end
    else
      self.enter("FOCUS", store.get("focus", 25))
      if withCue notify(self.cueFocus) end
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
    self.pinned = false
    rotation.resume()
  end

  def apply(cmd, minutes)
    if epoch_ms() <= 0 return end
    var running = self.phase != "IDLE"
    if cmd == "start"
      if !running
        self.enter("FOCUS", minutes > 0 ? minutes : store.get("focus", 25))
      elif self.paused
        self.apply("resume", 0)
      end
    elif cmd == "pause"
      if running && !self.paused && self.endEpoch > epoch_ms()
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
    if now <= 0
      self.refresh(now)
      return
    end
    self.settle(now)
    self.take_cmd()
    self.pin()
    self.refresh(now)
  end

  # Buttons: a press is taken (return true); the action fires on release unless a long press fired.
  # leftLong/rightLong: nil = not pressed, false = pressed, true = long fired. selectDown: press seen.
  def on_button_event(btn, event)
    var idle = self.phase == "IDLE"
    if btn == "select"
      if event == "press"
        self.selectDown = true
        return true
      elif event == "release"
        if !self.selectDown return false end
        self.selectDown = false
        self.apply("toggle", 0)
        return true
      end
      return false
    end
    if btn != "left" && btn != "right" return false end
    var left = btn == "left"
    if event == "press"
      if left self.leftLong = false else self.rightLong = false end
      return true
    end
    var state = left ? self.leftLong : self.rightLong
    if state == nil return false end
    if event == "long"
      if left self.leftLong = true else self.rightLong = true end
      if left
        if idle self.apply("start", 0) end
      elif !idle
        self.apply("stop", 0)
      end
    elif event == "release"
      if left self.leftLong = nil else self.rightLong = nil end
      if state == false
        if idle
          if left rotation.previous() else rotation.next() end
        elif left
          self.apply("toggle", 0)
        else
          self.apply("skip", 0)
        end
      end
    end
    return true
  end

  def make_cue(txt, hex, melody)
    var m = {"text": txt, "textColor": hex, "durationMs": 4000, "scroll": {"mode": "static"}}
    if store.get("sound", true) m["sound"] = {"rtttl": melody} end
    return m
  end

  # Rebuild what draw() shows. Called once a second from loop(), never from draw().
  def refresh(now)
    if self.phase == "IDLE"
      self.label = "POMO"
      self.pct = -1
      self.color = 0xFF8C00
      return
    end
    self.color = self.phase == "FOCUS" ? 0xFF8C00 : 0x00C8B4
    if now <= 0
      self.label = "--:--"
      self.pct = -1
      return
    end
    var rem = self.paused ? self.remainMs : self.endEpoch - now
    if rem < 0 rem = 0 end
    var secs = rem / 1000
    self.label = format("%02d:%02d", secs / 60, secs % 60)
    self.pct = self.totalMs > 0 ? rem * 100 / self.totalMs : 0
  end

  def draw()
    clear()
    if self.phase == "IDLE"
      font("small")
      text((32 - text_ink_width(self.label)) / 2, 6, self.label, self.color)
      return
    end
    font("large")
    if !self.paused || (now_ms() / 600) % 2 == 0
      text((32 - text_ink_width(self.label)) / 2, 6, self.label, self.color)
    end
    if self.pct >= 0 progress(self.pct, self.color, 0x202020) end
  end

  def should_show() return true end
  def duration() return self.phase == "IDLE" ? 3000 : 0 end
end

return Pomo()
