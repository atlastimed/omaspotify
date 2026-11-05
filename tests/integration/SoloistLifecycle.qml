import QtQuick
import Quickshell
import "plugin" as Plugin

ShellRoot {
  id: root
  property int starts: 0
  property int stops: 0
  Plugin.SoloistManager {
    id: manager
    pluginDir: Qt.resolvedUrl("plugin").toString().replace("file://", "")
    onStarted: {
      root.starts++
      if (root.starts === 1) Qt.callLater(function() { manager.saveKey("replacement-fixture-key") })
      else {
        if (root.stops === 1 && manager.keyAvailable && manager.lastError === "")
          console.log("SOLOIST_LIFECYCLE_PASS")
        else console.log("SOLOIST_LIFECYCLE_FAIL: replacement did not stop and restart")
        Qt.quit()
      }
    }
    onStopped: root.stops++
  }
  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      if (!manager.requirementsChecked) return
      stop()
      manager.saveKey("first-fixture-key")
    }
  }
  Timer { interval: 8000; running: true; onTriggered: { console.log("SOLOIST_LIFECYCLE_FAIL: timed out"); Qt.quit() } }
}
