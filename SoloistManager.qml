import QtQuick
import Quickshell.Io

// Runtime operations never pass a key through argv, settings, logs or the bridge.
Item {
  id: root
  property string pluginDir: ""
  property string deviceName: "OmaSpotify"
  property bool sessionConnected: false
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
    lastError = ""
    operation.action = action
    operation.input = input || ""
    operation.command = ["python3", pluginDir + "/scripts/soloist-runtime.py", action]
    operation.running = true
    return true
  }
  function refreshStatus() {
    if (!pluginDir || status.running) return
    status.command = ["python3", pluginDir + "/scripts/soloist-runtime.py", "status", credentialsChecked ? "--no-key" : "--key"]
    status.running = true
  }
  function checkRequirements() { refreshStatus() }
  function checkCredentials() { refreshStatus() }
  function requestConfiguration() {}
  function setupPlayback() {
    if (busy || !pluginDir) return
    setupBusy = true
    lastError = ""
    setup.command = ["bash", pluginDir + "/scripts/setup-soloist.sh"]
    setup.running = true
  }
  function start(explicit) {
    if (busy || running || !playbackReady || !keyAvailable) return
    if (explicit === true) terminalFailure = false
    if (terminalFailure) return
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
  onPluginDirChanged: if (pluginDir) refreshStatus()
  Timer { interval: root.authenticationBusy ? 2000 : 60000; running: root.pluginDir !== ""; repeat: true; onTriggered: root.refreshStatus() }
  Process {
    id: status
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      root.credentialsChecked = true
      root.requirementsChecked = true
      if (code !== 0) return
      var data
      try { data = JSON.parse(stdout.text) } catch (_) { return }
      root.binaryAvailable = data.installed === true
      root.unitAvailable = data.unit === true
      if (typeof data.key === "boolean") root.keyAvailable = data.key
      root.paired = data.paired === true
      root.serviceActive = data.running === true
      root.version = String(data.version || "")
      root.daysRemaining = Number(data.daysRemaining) || 0
    }
  }
  Process {
    id: configure
    stdinEnabled: true
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: { write(root.deviceName + "\n"); stdinEnabled = false }
    onExited: function(code) {
      stdinEnabled = true
      if (code === 0) Qt.callLater(function() { root.execute("start") })
      else root.lastError = "Could not update the local player name"
    }
  }
  Process {
    id: setup
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      root.setupBusy = false
      root.refreshStatus()
      if (code === 0) { root.binaryAvailable = true; root.unitAvailable = true; root.setupSucceeded() }
      else { root.lastError = "Soloist setup failed. Check the network and Rust toolchain, then retry."; root.setupFailed(root.lastError) }
    }
  }
  Process {
    id: operation
    property string action: ""
    property string input: ""
    stdinEnabled: true
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: { if (input) write(input); input = ""; stdinEnabled = false }
    onExited: function(code) {
      var completedAction = action
      input = ""
      stdinEnabled = true
      root.credentialsClearBusy = false
      root.refreshStatus()
      if (code !== 0) {
        root.startAfterSave = false
        root.lastError = "Soloist could not complete this operation. Check your key and try again."
        if (completedAction === "start") root.terminalFailure = true
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
