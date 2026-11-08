import QtQuick
import Quickshell
import "plugin" as Plugin

// The runner leaves a startup failure where the backend writes it.
ShellRoot {
  id: root

  Plugin.SoloistManager {
    id: manager
    pluginDir: Qt.resolvedUrl("plugin").toString().replace("file://", "")
    pairingTimeoutMs: 100
  }

  function fail(message) {
    console.log("SOLOIST_FAILURE_FAIL: " + message)
    Qt.quit()
  }

  Timer {
    id: waitForFailure
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      if (!manager.terminalFailure) return
      stop()
      if (manager.lastError.indexOf("expired") < 0)
        return root.fail("the backend's reason was not shown: " + manager.lastError)
      if (manager.statusPollNeeded)
        return root.fail("status is polled with nothing on screen")
      manager.uiVisible = true
      if (!manager.statusPollNeeded) return root.fail("status is not polled while visible")
      manager.uiVisible = false
      manager.keyAvailable = true
      manager.authenticate()
      if (manager.terminalFailure) return root.fail("an explicit retry kept the failure")
      if (!manager.statusPollNeeded) return root.fail("pairing does not poll")
      pairingEnds.start()
    }
  }

  Timer {
    id: pairingEnds
    interval: 400
    onTriggered: {
      if (manager.authenticationBusy) return root.fail("pairing polled past its deadline")
      if (manager.statusPollNeeded) return root.fail("the poll outlived pairing")
      console.log("SOLOIST_FAILURE_PASS")
      Qt.quit()
    }
  }

  Timer {
    interval: 8000
    running: true
    onTriggered: root.fail("timed out; failure=" + manager.terminalFailure
      + " error=" + manager.lastError + " checked=" + manager.requirementsChecked)
  }
}
