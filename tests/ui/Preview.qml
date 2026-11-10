import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "plugin" as Plugin
import "plugin/Api.js" as Api
import "FixtureApi.js" as Fixture

// Drives the real Service and Panel through every page, answering the real
// requests with made-up music, and asks the runner to capture each one. No
// network or real account is involved.
ShellRoot {
  id: harness

  readonly property string artDir: Quickshell.env("PREVIEW_ART")
  readonly property string outDir: Quickshell.env("PREVIEW_OUT")
  readonly property var only: String(Quickshell.env("PREVIEW_ONLY") || "").split(",").filter(Boolean)
  readonly property int settleMs: Number(Quickshell.env("PREVIEW_SETTLE_MS")) || 900

  Plugin.Service { id: service }
  Plugin.Panel { id: panel; service: service }

  // Just enough of a bar for the widget and its popup to believe in.
  QtObject {
    id: fakeBar
    readonly property color foreground: Commons.Color.foreground
    readonly property color background: Commons.Color.background
    readonly property color barForeground: Commons.Color.foreground
    readonly property color urgent: Commons.Color.urgent
    readonly property string fontFamily: Style.font.family
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: 26
    readonly property bool foregroundAnimationEnabled: false
    readonly property var clickTargets: []
    property var activePopout: null
    readonly property var shell: ({
      serviceFor: function() { return service },
      isPluginOpen: function() { return false },
      hide: function() {},
      summon: function() { return true },
      toggle: function() {}
    })
    function barSizeFor() { return barSize }
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function notePopoutCard() {}
    function popoutCardFor() { return null }
    function targetBelongsToWindow() { return false }
    function showTooltip() {}
    function hideTooltip() {}
    function run() {}
  }

  PanelWindow {
    anchors { top: true; left: true; right: true }
    implicitHeight: 26
    color: Commons.Color.background

    Plugin.BarWidget {
      id: widget
      bar: fakeBar
      x: 600
      settings: ({})
    }
  }

  property var pendingRequests: []
  property bool holdRequests: false

  Component {
    id: fakeRequest

    QtObject {
      property int readyState: 0
      property int status: 0
      property string responseText: ""
      property var onreadystatechange: null
      property string method: "GET"
      property string url: ""

      function open(requestMethod, requestUrl) {
        method = requestMethod
        url = requestUrl
      }
      function setRequestHeader() {}
      function getResponseHeader() { return "" }
      function abort() {}
      function send() {
        var next = harness.pendingRequests.slice()
        next.push(this)
        harness.pendingRequests = next
        flush.start()
      }
      function answer() {
        var result = Fixture.respond(method, url)
        status = result[0]
        responseText = result[1] === null ? "" : JSON.stringify(result[1])
        readyState = XMLHttpRequest.DONE
        if (onreadystatechange) onreadystatechange()
      }
    }
  }

  Timer {
    id: flush
    interval: 15
    onTriggered: {
      if (harness.holdRequests) return
      var batch = harness.pendingRequests
      harness.pendingRequests = []
      for (var i = 0; i < batch.length; i++) batch[i].answer()
    }
  }

  function connectFixture() {
    Fixture.artDir = artDir
    service.api.xhrFactory = function() { return fakeRequest.createObject(harness) }
    // Changing the app identity drains the session, so sign in once that settles.
    service.auth.customClientId = "0123456789abcdef0123456789abcdef"
    var days = ({}), now = Date.now()
    for (var d = 0; d < 300; d++) {
      var count = Math.floor(Math.max(0, Math.sin(d / 9) * 18 + (d * 7919 % 13) - 4))
      if (count > 0) days[Api.playDayKey(now - d * 86400000)] = count
    }
    service.playDays = days
  }

  function signIn() {
    var auth = service.auth
    auth.accessToken = "fixture-token"
    auth.accessTokenExpiresAt = Date.now() + 86400000
    auth.loggedIn = true
    auth.sessionChecked = true
  }

  readonly property var steps: [
    { shot: "home", tab: "home", wait: 4000, run: function() { panel.homeType = "recent" } },
    { shot: "home-artists", tab: "home", run: function() { panel.homeType = "artists" } },
    { shot: "library", tab: "library", run: function() { panel.libraryType = "tracks" } },
    { shot: "library-albums", tab: "library", run: function() {
      panel.libraryType = "albums"
      service.loadLibrary("albums", false)
    } },
    { shot: "playlist", tab: "playlists", run: function() {
      service.openPlaylist(Api.normalizePlaylist(Fixture.playlistObject(0), 128))
    } },
    { shot: "album", tab: "home", run: function() {
      panel.openItem(Api.normalizeContext(Fixture.albumObject(1), 128))
    } },
    { shot: "artist", tab: "home", run: function() {
      panel.openItem(Api.normalizeContext(Fixture.artistObject(0), 128))
    } },
    { shot: "search", tab: "search", run: function() {
      panel.searchText = "lane"
      service.search("lane", "track")
    } },
    { shot: "queue", tab: "queue" },
    { shot: "stats", tab: "stats" },
    { shot: "devices", tab: "devices", wait: 5000 },
    // Once the background library crawl has filled the sidebar.
    { shot: "home-settled", tab: "home", run: function() { panel.homeType = "recent" } },
    { shot: "settings", tab: "setup" },
    { shot: "discover", tab: "discover" },
    { shot: "nowplaying", tab: "home", run: function() {
      panel.equalizerMode = "bars"
      panel.nowPlayingExpanded = true
    } },
    { shot: "shortcuts", tab: "home", run: function() { panel.toggleShortcutHelp() },
      after: function() { panel.toggleShortcutHelp() } },
    { shot: "context-menu", tab: "home", settled: function() {
      panel.openMediaContext(service.recentTracks[1], 320, 220, service.recentTracks, "", 1)
    }, after: function() { panel.dismissTransientPopup() } },
    // Ctrl held: the chords it starts.
    { shot: "hints", tab: "home", settled: function() {
      panel.heldModifierFlags = Qt.ControlModifier
      panel.modifierHintsShown = true
    }, after: function() { panel.resetKeyboardState() } },
    // Steering by keyboard: the cursor, and the keys that need no modifier.
    { shot: "hints-keyboard", tab: "home", settled: function() {
      panel.showKeyboardCursor()
      panel.ensurePanelCursor("page")
      panel.movePanelCursor(1)
    }, after: function() { panel.resetKeyboardState() } },
    { shot: "error", tab: "home", settled: function() {
      service.fail("Spotify could not complete this request. Try again in a moment.")
    }, after: function() { service.lastError = "" } },
    { shot: "status", tab: "home", settled: function() { service.succeed("Added to queue") } },
    { shot: "empty", tab: "library", before: function() { Fixture.mode = "empty"; service.savedTracks = [] },
      after: function() { Fixture.mode = "full" } },
    { shot: "empty-queue", tab: "queue", before: function() { Fixture.mode = "empty" },
      after: function() { Fixture.mode = "full" } },
    { shot: "idle", tab: "home", before: function() {
      Fixture.mode = "idle"
      service.remotePlayback = null
    }, after: function() { Fixture.mode = "full" } },
    { shot: "loading", tab: "library", run: function() {
      harness.holdRequests = true
      panel.libraryType = "albums"
      service.savedAlbums = []
      service.savedAlbumsLoaded = false
      service.loadLibrary("albums", false)
    }, after: function() { harness.holdRequests = false; flush.start() } },
    { shot: "confirm", tab: "setup", settled: function() {
      panel.askToConfirm("Log out of Spotify on this computer?", "Log out", function() {})
    }, after: function() { panel.dismissTransientPopup() } },
    { shot: "eq-pixels", tab: "home", run: function() {
      panel.equalizerMode = "pixels"
      panel.nowPlayingExpanded = true
    } },
    { shot: "eq-scope", tab: "home", run: function() {
      panel.equalizerMode = "scope"
      panel.nowPlayingExpanded = true
    } },
    { shot: "eq-matrix", tab: "home", run: function() {
      panel.equalizerMode = "matrix"
      panel.nowPlayingExpanded = true
    } },
    { shot: "mini", tab: "home", settled: function() {
      panel.close()
      widget.open()
    } },
    { shot: "mini-help", tab: "home", settled: function() {
      panel.close()
      widget.open()
      widget.toggleMiniShortcutHelp()
    }, after: function() { widget.close() } },
    { shot: "mini-menu", tab: "home", settled: function() {
      panel.close()
      widget.contextMenuVisible = true
      widget.open()
    }, after: function() { widget.close(); widget.contextMenuVisible = false } }
  ]

  property int stepIndex: -1
  readonly property var current: stepIndex >= 0 && stepIndex < steps.length ? steps[stepIndex] : null

  function runStep() {
    if (current && current.after) current.after()
    stepIndex++
    while (stepIndex < steps.length && only.length && only.indexOf(steps[stepIndex].shot) < 0) stepIndex++
    if (stepIndex >= steps.length) {
      console.log("UI_PREVIEW_DONE")
      Quickshell.execDetached(["swaymsg", "exit"])
      return
    }
    var step = current
    try {
      harness.signIn()
      panel.nowPlayingExpanded = false
      panel.universalSearchActive = false
      panel.navigationStack = []
      service.lastError = ""
      service.statusMessage = ""
      if (step.before) step.before()
      panel.open(JSON.stringify({ tab: step.tab }))
      panel.chooseTab(step.tab)
      if (step.run) step.run()
    } catch (e) {
      console.log("UI_PREVIEW_ERROR", step.shot, e)
    }
    settle.restart()
  }

  Timer {
    id: settle
    interval: harness.current && harness.current.wait ? harness.current.wait : harness.settleMs
    onTriggered: {
      try {
        if (harness.current.settled) harness.current.settled()
      } catch (e) {
        console.log("UI_PREVIEW_ERROR", harness.current.shot, e)
      }
      shortly.restart()
    }
  }

  Timer {
    id: shortly
    interval: 260
    onTriggered: capture.running = true
  }

  Process {
    id: capture
    command: ["grim", harness.outDir + "/" + (harness.current || { shot: "x" }).shot + ".png"]
    onExited: harness.runStep()
  }

  Timer {
    interval: 200
    running: true
    onTriggered: {
      harness.connectFixture()
      started.start()
    }
  }

  Timer {
    id: started
    interval: 700
    onTriggered: harness.runStep()
  }
}
