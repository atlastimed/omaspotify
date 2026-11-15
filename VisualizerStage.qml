pragma ComponentBehavior: Bound

import QtQuick

// Draws a spectrum. It is handed the levels and knows nothing about where they
// come from, so it can be previewed and tested without any audio.
//
// The levels are eased toward what was last heard on every frame, written into
// a one-row texture, and a fragment shader per style paints from that. While
// nothing changes no frame is drawn at all.
Item {
  id: stage

  // What the analyser last heard, one value from 0 to 1 per band.
  property var levels: []
  // False lets the picture fall to rest and then stop.
  property bool running: false
  property string style: "bars"
  readonly property var styles: ["bars", "wave", "halo", "aurora", "pixels"]
  property int bandCount: 64
  property real sensitivity: 1
  property real glow: 0.6
  property bool mirror: false
  property bool peaks: true
  property real strength: 1
  property color low: "#3b82f6"
  property color middle: "#a855f7"
  property color high: "#f472b6"
  // The artwork, in this item's coordinates. The halo is drawn around it.
  property rect artRect: Qt.rect(0, 0, 0, 0)
  // How far out from the artwork the halo may reach.
  property real artSpan: 0
  // How far down the view the artwork and names reach. Below it is the
  // visualiser's alone, and no style but the halo draws its shapes above it.
  property real deck: 0

  Behavior on low { ColorAnimation { duration: 700 } }
  Behavior on middle { ColorAnimation { duration: 700 } }
  Behavior on high { ColorAnimation { duration: 700 } }

  property var shown: []
  property var held: []
  property real bass: 0
  property real mid: 0
  property real treble: 0
  property real clock: 0
  property bool settled: true

  readonly property string shaderStyle: styles.indexOf(style) >= 0 ? style : "bars"

  onLevelsChanged: if (running) settled = false
  onRunningChanged: if (running) settled = false
  onBandCountChanged: {
    shown = []
    held = []
    settled = false
  }

  function average(values, from, to) {
    var sum = 0
    for (var i = from; i < to; i++) sum += values[i]
    return to > from ? sum / (to - from) : 0
  }

  // One frame nearer to what was heard. Rising is quick so a hit lands on the
  // beat; falling is slower so the eye can follow it down.
  function advance(seconds) {
    var dt = Math.max(0, Math.min(0.1, Number(seconds) || 0))
    var count = bandCount
    var rise = 1 - Math.exp(-dt * 40)
    var fall = 1 - Math.exp(-dt * 9)
    var next = new Array(count)
    var caps = new Array(count)
    var quiet = true
    for (var i = 0; i < count; i++) {
      var heard = running ? Math.min(1, Math.max(0, (Number(levels[i]) || 0) * sensitivity)) : 0
      var was = shown[i] || 0
      var now = was + (heard - was) * (heard > was ? rise : fall)
      if (now < 0.003 && heard === 0) now = 0
      var cap = Math.max(now, (held[i] || 0) - dt * 0.4)
      if (cap < 0.003) cap = 0
      if (now > 0 || cap > 0) quiet = false
      next[i] = now
      caps[i] = cap
    }
    shown = next
    held = caps
    var third = Math.max(1, Math.floor(count / 3))
    bass = average(next, 0, Math.max(1, Math.floor(count / 6)))
    mid = average(next, third, third * 2)
    treble = average(next, third * 2, count)
    if (running) clock += dt
    settled = quiet && !running
  }

  FrameAnimation {
    running: stage.visible && !stage.settled
    onTriggered: stage.advance(frameTime)
  }

  // The texture the shaders read: red is the level, green the falling cap.
  Row {
    id: strip
    visible: false
    Repeater {
      model: stage.bandCount
      Rectangle {
        required property int index
        width: 1
        height: 1
        color: Qt.rgba(stage.shown[index] || 0, stage.held[index] || 0, 0, 1)
      }
    }
  }

  ShaderEffectSource {
    id: bandTexture
    sourceItem: strip
    textureSize: Qt.size(stage.bandCount, 1)
    hideSource: true
    smooth: false
    live: !stage.settled
    visible: false
    width: stage.bandCount
    height: 1
  }

  ShaderEffect {
    objectName: "visualizer-shader"
    anchors.fill: parent
    visible: !stage.settled && stage.width > 0 && stage.height > 0
    blending: true

    property var bands: bandTexture
    property real time: stage.clock
    property real count: stage.bandCount
    property real glow: stage.glow
    property real mirror: stage.mirror ? 1 : 0
    property real peaks: stage.peaks ? 1 : 0
    property real bass: stage.bass
    property real mid: stage.mid
    property real treble: stage.treble
    property real strength: stage.strength
    property real span: stage.artSpan
    property real deck: stage.deck
    property vector2d area: Qt.vector2d(width, height)
    property vector4d art: Qt.vector4d(stage.artRect.x, stage.artRect.y,
      stage.artRect.width, stage.artRect.height)
    property color c0: stage.low
    property color c1: stage.middle
    property color c2: stage.high

    fragmentShader: Qt.resolvedUrl("shaders/" + stage.shaderStyle + ".frag.qsb")
  }
}
