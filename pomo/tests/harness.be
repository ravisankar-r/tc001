# Test harness: stub AWTRIX NG globals so pomo.be runs under the reference Berry interpreter.
import global
import string

class FakeStore
  var data
  var writes
  def init()
    self.data = {"focus": 25, "shortBreak": 5, "longBreak": 15, "every": 4, "sound": true}
    self.writes = 0
  end
  def get(k, d)
    if self.data.contains(k) return self.data[k] end
    return d
  end
  def set(k, v)
    self.data[k] = v
    self.writes += 1
  end
end

global.calls = []
global.clock = {"epoch": -1, "ms": 0}
global.tests = []

global.epoch_ms = def () return global.clock["epoch"] end
global.now_ms = def () return global.clock["ms"] end
global.width = def () return 32 end
global.height = def () return 8 end
global.clear = def (c) global.calls.push(["clear"]) end
global.font = def (n) global.calls.push(["font", n]) end
global.text = def (x, y, s, c) global.calls.push(["text", x, y, s, c]) return 4 * size(s) end
global.text_ink_width = def (s) return 4 * size(s) - 1 end
global.progress = def (pct, c, bg) global.calls.push(["progress", pct, c, bg]) end
global.notify = def (m) global.calls.push(["notify", m]) return true end
global.log = def (v) global.calls.push(["log", v]) end

class FakeSound
  def play(m) global.calls.push(["sound", m]) return true end
  def can(k) return true end
end
global.sound = FakeSound()

class FakeRotation
  def show() global.calls.push(["rotation", "show"]) return true end
  def pause() global.calls.push(["rotation", "pause"]) end
  def resume() global.calls.push(["rotation", "resume"]) end
  def next() global.calls.push(["rotation", "next"]) end
  def previous() global.calls.push(["rotation", "previous"]) end
end
global.rotation = FakeRotation()

global.fresh = def ()
  global.store = FakeStore()
  global.clock = {"epoch": -1, "ms": 0}
  global.calls = []
end
global.reset_calls = def () global.calls = [] end
global.calls_of = def (name)
  var out = []
  for c : global.calls
    if c[0] == name out.push(c) end
  end
  return out
end
global.load_pomo = def ()
  var f = compile("pomo.be", "file")
  return f()
end
global.t = def (name, fn) global.tests.push([name, fn]) end
global.fresh()
