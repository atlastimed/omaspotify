import QtQuick
import Quickshell
import Quickshell.Io

import "Api.js" as Api

// The UI sends keys to the helper over stdin, never via settings or the bridge.
Item {
  id: root
  property string pluginDir: ""
  property string deviceName: "OmaSpotify"
  property bool sessionConnected: false
  // Status costs a Python start and a systemctl, so it runs when someone can see
  // the answer, and when the backend's own connection says something changed.
  property bool uiVisible: false
  property bool backendConnected: false
  property bool binaryAvailable: false
  property bool unitAvailable: false
  property bool keyAvailable: false
  property bool paired: false
  property bool credentialsChecked: false
  property bool requirementsChecked: false
  property bool serviceActive: false
  property bool setupBusy: false
  property bool authenticationBusy: false
  property bool credentialsClearBusy: false
  property bool terminalFailure: false
  property string lastError: ""
  property string version: ""
  property int daysRemaining: 0
  property bool startAfterSave: false
  property int statusGeneration: 0
  property bool helperSynced: false
  property int pairingTimeoutMs: 300000
  readonly property bool statusPollNeeded: pluginDir !== "" && (authenticationBusy || uiVisible)
  readonly property string failurePath: {
    var runtime = Quickshell.env("XDG_RUNTIME_DIR")
    return runtime ? runtime + "/omaspotify/startup-error.json" : ""
  }
  readonly property bool credentialsAvailable: keyAvailable && (paired || sessionConnected)
  readonly property bool playbackReady: binaryAvailable && unitAvailable
  readonly property bool running: serviceActive
  readonly property bool busy: operation.running || configure.running || setup.running
  signal started()
  signal stopped()
  signal setupSucceeded()
  signal setupFailed(string reason)
  signal authenticationSucceeded()
  signal authenticationFailed(string reason)
  signal credentialsCleared()
  signal credentialsClearFailed(string reason)

  function execute(action, input) {
    if (!pluginDir || operation.running) return false
    statusGeneration++
    lastError = ""
    operation.action = action
    operation.input = input || ""
    operation.command = ["python3", pluginDir + "/scripts/soloist-runtime.py", action]
    operation.running = true
    return true
  }
  function refreshStatus() {
    if (!pluginDir || status.running || busy) return
    status.generation = statusGeneration
    // A keyring still locked at the first check must not read as no key for ever.
    status.command = ["python3", pluginDir + "/scripts/soloist-runtime.py", "status",
      keyAvailable ? "--no-key" : "--key"]
    status.running = true
  }
  function applyStatus(generation, data) {
    if (generation !== statusGeneration || !data || typeof data !== "object") return false
    credentialsChecked = true
    requirementsChecked = true
    binaryAvailable = data.installed === true
    unitAvailable = data.unit === true
    if (typeof data.key === "boolean") keyAvailable = data.key
    paired = data.paired === true
    serviceActive = data.running === true
    version = String(data.version || "")
    daysRemaining = Number(data.daysRemaining) || 0
    syncInstalledHelper()
    if (serviceActive) terminalFailure = false
    else if (failurePath) failureFile.reload()
    return true
  }
  // A plugin update replaces this file's helper, not the copy the service runs.
  function syncInstalledHelper() {
    if (helperSynced || !binaryAvailable || !pluginDir) return
    helperSynced = true
    sync.command = ["python3", pluginDir + "/scripts/soloist-runtime.py", "sync"]
    sync.running = true
  }
  function applyFailureFile(raw) {
    var record = Api.parseJson(raw, null)
    var message = record ? Api.playbackFailureMessage(String(record.code || "")) : ""
    if (!message) return
    terminalFailure = true
    lastError = message
    authenticationBusy = false
  }
  function clearFailureFile() {
    if (failurePath) Quickshell.execDetached(["rm", "-f", "--", failurePath])
  }
  function checkRequirements() { refreshStatus() }
  function checkCredentials() { refreshStatus() }
  function requestConfiguration() {}
  function setupPlayback() {
    if (busy || !pluginDir) return
    setupBusy = true
    statusGeneration++
    lastError = ""
    setup.command = ["bash", pluginDir + "/scripts/setup-soloist.sh"]
    setup.running = true
  }
  function start(explicit) {
    if (busy || running || !playbackReady || !keyAvailable) return
    if (explicit === true) {
      terminalFailure = false
      clearFailureFile()
    }
    if (terminalFailure) return
    statusGeneration++
    configure.generation = statusGeneration
    configure.command = ["bash", pluginDir + "/scripts/configure-playback.sh"]
    configure.running = true
  }
  function stop() { execute("stop") }
  function authenticate() {
    if (!keyAvailable) { lastError = "Add your Soloist API key below, then select OmaSpotify in the official Spotify app."; return }
    authenticationBusy = true
    start(true)
  }
  function saveKey(value) {
    if (!playbackReady || busy || !value.trim()) return
    startAfterSave = true
    execute("save-key", value.trim())
  }
  function cancelAuthentication() { authenticationBusy = false }
  function clearCredentials() {
    credentialsClearBusy = true
    if (!execute("clear")) credentialsClearBusy = false
  }
  onSessionConnectedChanged: {
    refreshStatus()
    if (sessionConnected) {
      paired = true
      authenticationBusy = false
      authenticationSucceeded()
    }
  }
  onBackendConnectedChanged: refreshStatus()
  onUiVisibleChanged: if (uiVisible) refreshStatus()
  onPluginDirChanged: if (pluginDir) refreshStatus()
  onAuthenticationBusyChanged: {
    if (authenticationBusy) pairingDeadline.restart()
    else pairingDeadline.stop()
  }
  Timer {
    interval: root.authenticationBusy ? 2000 : 60000
    running: root.statusPollNeeded
    repeat: true
    onTriggered: root.refreshStatus()
  }
  Timer {
    id: pairingDeadline
    interval: root.pairingTimeoutMs
    onTriggered: {
      root.authenticationBusy = false
      root.lastError = "Pairing did not finish. Select OmaSpotify in the official Spotify app, then try again."
      root.authenticationFailed(root.lastError)
    }
  }
  FileView {
    id: failureFile
    path: root.failurePath
    watchChanges: false
    printErrors: false
    onLoaded: root.applyFailureFile(text())
  }
  Process {
    id: status
    property int generation: 0
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (generation !== root.statusGeneration) {
        Qt.callLater(root.refreshStatus)
        return
      }
      if (code !== 0) return
      var data
      try { data = JSON.parse(stdout.text) } catch (_) { return }
      root.applyStatus(generation, data)
    }
  }
  Process {
    id: sync
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }
  Process {
    id: configure
    property int generation: 0
    stdinEnabled: true
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: { write(root.deviceName + "\n"); stdinEnabled = false }
    onExited: function(code) {
      stdinEnabled = true
      if (generation !== root.statusGeneration) return
      if (code === 0) Qt.callLater(function() {
        if (configure.generation === root.statusGeneration) root.execute("start")
      })
      else root.lastError = "Could not update the local player name"
    }
  }
  Process {
    id: setup
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      root.setupBusy = false
      Qt.callLater(root.refreshStatus)
      if (code === 0) { root.binaryAvailable = true; root.unitAvailable = true; root.setupSucceeded() }
      else { root.lastError = "Soloist setup failed. Check the network and Rust toolchain, then retry."; root.setupFailed(root.lastError) }
    }
    // A command that cannot start never reports an exit.
    onRunningChanged: if (!running) Qt.callLater(function() {
      if (!root || !root.setupBusy || setup.running) return
      root.setupBusy = false
      root.lastError = "Soloist setup could not start."
      root.setupFailed(root.lastError)
    })
  }
  Process {
    id: operation
    property string action: ""
    property string input: ""
    stdinEnabled: true
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: { if (input) write(input); input = ""; stdinEnabled = false }
    onRunningChanged: if (!running) Qt.callLater(function() {
      if (root && root.credentialsClearBusy && !operation.running) {
        root.credentialsClearBusy = false
        root.lastError = "Soloist could not complete this operation."
        root.credentialsClearFailed(root.lastError)
      }
    })
    onExited: function(code) {
      var completedAction = action
      input = ""
      stdinEnabled = true
      root.credentialsClearBusy = false
      Qt.callLater(root.refreshStatus)
      if (code !== 0) {
        root.startAfterSave = false
        root.lastError = "Soloist could not complete this operation. Check your key and try again."
        if (completedAction === "start") root.terminalFailure = true
        root.authenticationBusy = false
        if (completedAction === "clear") root.credentialsClearFailed(root.lastError)
        return
      }
      if (completedAction === "start") { root.serviceActive = true; root.started() }
      if (completedAction === "stop") { root.serviceActive = false; root.stopped() }
      if (completedAction === "save-key") {
        root.keyAvailable = true
        root.startAfterSave = false
        root.authenticationBusy = true
        // A new key must reach a newly launched receiver.
        if (root.serviceActive) { root.startAfterSave = true; Qt.callLater(function() { root.execute("stop") }) }
        else Qt.callLater(function() { root.start(true) })
      }
      if (completedAction === "stop" && root.startAfterSave) { root.startAfterSave = false; Qt.callLater(function() { root.start(true) }) }
      if (completedAction === "clear") { root.keyAvailable = false; root.paired = false; root.serviceActive = false; root.credentialsCleared() }
    }
  }
}
