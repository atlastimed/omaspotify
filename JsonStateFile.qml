import QtQuick
import Quickshell.Io

// One JSON file in the private state directory. It is read once when active and
// written one save at a time, so a change made during a write is never marked
// as saved, and a write that fails is tried again.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  property string path: ""
  property bool active: true
  property int saveDelay: 400
  // Returns the text to write. Only called when a save actually happens.
  property var encode: null

  property bool loaded: false
  property bool dirty: false

  property int generation: 0
  property int savingGeneration: -1
  property bool saving: false
  property int failures: 0
  property bool discardNextRead: false
  // Fingerprint of what FileView last held, since these files run to megabytes.
  // Giving it the same text again saves nothing and reports nothing, which would
  // leave this waiting for ever.
  property string heldHash: ""

  readonly property int maxRetries: 3

  signal contentRead(string text)
  signal saved()
  signal saveFailed()

  function markDirty() {
    dirty = true
    generation++
    if (loaded) saveTimer.restart()
  }

  function flush() {
    saveTimer.stop()
    if (!loaded || !dirty || typeof encode !== "function") return
    if (saving) {
      saveTimer.restart()
      return
    }
    var text = String(encode())
    // JSON ignores trailing whitespace, and a retry has to differ to be written.
    for (var i = 0; i < failures; i++) text += "\n"
    savingGeneration = generation
    var hash = Qt.md5(text)
    if (hash === heldHash) {
      finishSave()
      return
    }
    heldHash = hash
    saving = true
    saveWatchdog.restart()
    file.setText(text)
  }

  // For signing out: what is on disk must never come back, read or not.
  function replaceContents() {
    if (!loaded) discardNextRead = true
    active = true
    markDirty()
    if (loaded) flush()
  }

  function finishSave() {
    saving = false
    saveWatchdog.stop()
    failures = 0
    if (savingGeneration === generation) dirty = false
    else if (loaded) saveTimer.restart()
    saved()
  }

  function failSave() {
    // What the file holds is no longer known, so the next save must really write.
    heldHash = ""
    saving = false
    saveWatchdog.stop()
    saveFailed()
    if (failures < maxRetries) {
      failures++
      retryTimer.interval = failures * 1000
      retryTimer.restart()
    }
  }

  function finishRead(text) {
    if (loaded) return
    loaded = true
    heldHash = Qt.md5(text)
    var discarded = discardNextRead
    discardNextRead = false
    contentRead(discarded ? "" : text)
    if (dirty) discarded ? flush() : saveTimer.restart()
  }

  Timer {
    id: saveTimer
    interval: root.saveDelay
    onTriggered: root.flush()
  }

  Timer {
    id: retryTimer
    onTriggered: root.flush()
  }

  // A save that never reports back must not block every later one.
  Timer {
    id: saveWatchdog
    interval: 10000
    onTriggered: root.failSave()
  }

  FileView {
    id: file
    path: root.active ? root.path : ""
    watchChanges: false
    atomicWrites: true
    // Megabyte files, written with a sync: never on the thread that draws the bar.
    blockWrites: false
    printErrors: false
    onLoaded: root.finishRead(text())
    onLoadFailed: root.finishRead("")
    onSaved: root.finishSave()
    onSaveFailed: root.failSave()
  }
}
