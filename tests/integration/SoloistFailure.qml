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
      // Asking again must count even while the helper is busy with something else.
      manager.setupBusy = true
      manager.authenticate()
      manager.setupBusy = false
      if (manager.terminalFailure) return root.fail("a retry while busy kept the failure")
      // A status check that started before the retry can still read the old file.
      manager.terminalFailure = false
      manager.applyFailureFile('{"code":"soloist_expired","timestamp":1}')
      if (manager.terminalFailure) return root.fail("a failure from before the retry came back")
      manager.applyFailureFile('{"code":"soloist_expired","timestamp":' + Math.ceil(Date.now() / 1000 + 5) + '}')
      if (!manager.terminalFailure) return root.fail("a new failure was ignored")
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
