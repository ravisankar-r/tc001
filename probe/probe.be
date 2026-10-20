# Throwaway hardware probe for Task 1 of the pomodoro plan.
# Logs raw button events, writes the store once a second, pauses rotation when shown.
class Probe
  var n
  def init()
    self.n = store.get("n", 0)
    log("probe init n=" + str(self.n))
  end
  def loop()
    self.n += 1
    store.set("n", self.n)
  end
  def on_show()
    rotation.pause()
    log("probe paused rotation")
  end
  def on_button_event(btn, event)
    log(format("btn %s %s %d", btn, event, now_ms()))
    return true
  end
  def draw()
    clear()
    text(1, 6, "PRB", 0xFF00FF)
  end
end
return Probe()
