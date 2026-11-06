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
        if (manager.applyStatus(manager.statusGeneration - 1,
            { installed: false, unit: false, key: false, paired: false, running: false })
            || !manager.serviceActive || !manager.keyAvailable) {
          console.log("SOLOIST_LIFECYCLE_FAIL: stale status overwrote a completed start")
          Qt.quit()
          return
        }
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
  Timer {
    interval: 8000
    running: true
    onTriggered: {
      console.log("SOLOIST_LIFECYCLE_FAIL: timed out; starts=" + root.starts
        + " stops=" + root.stops + " ready=" + manager.playbackReady
        + " checked=" + manager.requirementsChecked + " key=" + manager.keyAvailable
        + " active=" + manager.serviceActive + " busy=" + manager.busy
        + " error=" + manager.lastError)
      Qt.quit()
    }
  }
}
