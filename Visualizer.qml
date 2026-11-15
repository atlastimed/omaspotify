pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

import "Api.js" as Api

// The live spectrum behind the now-playing view.
//
// scripts/visualizer.sh points cava at the player's own PipeWire stream and
// sends one line per frame ("v;v;v;...", 0..1000 per band), or "idle" while
// nothing plays on this computer. VisualizerStage draws them. The helper runs
// only while the view is open, so a closed player costs nothing.
Item {
  id: root

  property bool active: false
  property bool playing: false
  property string configPath: ""
  property string scriptPath: ""
  property string backendBinary: "omaspotify-backend"
  // Api.normalizedVisualizer's shape: style, palette and the rest.
  property var settings: Api.normalizedVisualizer(null)
  property color accent: "#ffffff"
  property color foreground: "#ffffff"
  property color muted: "#ffffff"
  property string fontFamily: Style.font.family
  // The cover as it is drawn, what identifies it, and a directory a small copy
  // of it may be written to. The palette taken from a cover needs a local
  // file, and the cover on show usually came straight from the network.
  property Item artworkItem: null
  property string artworkKey: ""
  property string swatchDir: ""
  property int swatchTurn: 0
  property string swatchSource: ""
  property rect artRect: Qt.rect(0, 0, 0, 0)
  property real artSpan: 0

  property var levels: []
  // Set only once the helper says nothing plays here, so the note about
  // another device does not flash while cava is still starting.
  property bool streamIdle: false
  property bool unavailable: false
  property string unavailableReason: ""
  property bool restartWanted: false
  property bool alive: false
  property bool stopping: false

  readonly property int bands: settings.bands
  readonly property int smoothing: settings.smoothing
  readonly property var palette: Api.visualizerPalette(settings.palette, accent, foreground,
    quantizer.colors)
  readonly property bool wantsSwatch: active && settings.palette === "artwork"
    && artworkKey !== "" && swatchDir !== "" && artworkItem !== null
  readonly property string note: !streamIdle ? ""
    : (playing ? "Playing on another device · the visualiser follows this computer"
      : "Play something on this computer to light up the visualiser")

  onActiveChanged: active ? start() : stop()
  onScriptPathChanged: restart()
  onConfigPathChanged: restart()
  onBandsChanged: restart()
  onSmoothingChanged: restart()
  onWantsSwatchChanged: wantsSwatch ? swatchTimer.restart() : swatchTimer.stop()
  onArtworkKeyChanged: {
    swatchSource = ""
    if (wantsSwatch) swatchTimer.restart()
  }
  Component.onCompleted: if (active) start()
  Component.onDestruction: {
    restartWanted = false
    if (helper.running) helper.running = false
  }

  // A stopped helper takes a moment to go, and a second one must not be
  // started on top of it. Whatever is asked for meanwhile is done when it exits.
  function start() {
    if (!active || !configPath || !scriptPath || unavailable) return
    if (alive) {
      if (stopping) restartWanted = true
      return
    }
    alive = true
    helper.running = true
  }

  function halt() {
    if (!alive || stopping) return
    stopping = true
    helper.running = false
  }

  function stop() {
    restartWanted = false
    halt()
    levels = []
    streamIdle = false
    // Try again next time the view opens, so installing cava needs no restart.
    unavailable = false
  }

  // The helper reads its settings once, so a change means starting it again.
  function restart() {
    if (!active) return
    if (alive) {
      restartWanted = true
      halt()
    } else start()
  }

  // Two file names taken in turn, so a new cover is never read from the name
  // the last one is still loaded under.
  function takeSwatch() {
    if (!wantsSwatch) return
    var key = artworkKey
    var turn = (swatchTurn + 1) % 2
    var path = swatchDir + "/visualizer-cover-" + turn + ".png"
    artworkItem.grabToImage(function(result) {
      if (key !== root.artworkKey || !result.saveToFile(path)) return
      root.swatchTurn = turn
      root.swatchSource = "file://" + path
    }, Qt.size(64, 64))
  }

  function handleLine(line) {
    var text = String(line || "")
    if (text === "idle") {
      streamIdle = true
      if (levels.length) levels = []
      return
    }
    var parts = text.split(";")
    var next = []
    for (var i = 0; i < parts.length && next.length < bands; i++) {
      if (parts[i] === "") continue
      var v = Number(parts[i])
      if (!isFinite(v)) continue
      next.push(Math.max(0, Math.min(1, v / 1000)))
    }
    if (!next.length) return
    streamIdle = false
    levels = next
  }

  ColorQuantizer {
    id: quantizer
    source: root.wantsSwatch ? root.swatchSource : ""
    depth: 4
    rescaleSize: 64
  }

  Process {
    id: helper
    command: ["/usr/bin/bash", root.scriptPath, root.configPath, String(root.bands),
      root.backendBinary, String(root.smoothing)]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.handleLine(line) }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var asked = root.stopping
      root.alive = false
      root.stopping = false
      root.levels = []
      root.streamIdle = false
      if (root.restartWanted) {
        root.restartWanted = false
        again.start()
        return
      }
      if (asked) return
      // A stop asked for by the view arrives here after active already
      // flipped, so only a failure while still active is worth reporting.
      if (!root.active) return
      if (exitCode === 127) {
        root.unavailable = true
        root.unavailableReason = "Install cava to see the visualiser"
      } else if (exitCode === 126) {
        root.unavailable = true
        root.unavailableReason = "The visualiser needs pw-dump and python3"
      } else if (exitCode !== 0) {
        root.unavailable = true
        root.unavailableReason = "The visualiser could not start (exit " + exitCode + ")"
      }
    }
  }

  // A moment for the cover to finish drawing before it is copied.
  Timer {
    id: swatchTimer
    interval: 250
    onTriggered: root.takeSwatch()
  }

  // A timer, so nothing runs after the view has been unloaded.
  Timer {
    id: again
    interval: 0
    onTriggered: root.start()
  }

  VisualizerStage {
    objectName: "visualizer-stage"
    anchors.fill: parent
    visible: !root.unavailable
    levels: root.levels
    running: root.active && root.playing && !root.streamIdle && root.levels.length > 0
    style: root.settings.style
    bandCount: root.bands
    sensitivity: root.settings.sensitivity
    glow: root.settings.glow
    strength: root.settings.brightness
    // The halo is the same spectrum down both sides, whatever this is set to.
    mirror: root.settings.mirror
    peaks: root.settings.peaks
    low: root.palette[0]
    middle: root.palette[1]
    high: root.palette[2]
    artRect: root.artRect
    artSpan: root.artSpan
  }
}
