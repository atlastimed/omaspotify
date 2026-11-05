import QtQuick
import Quickshell
import Quickshell.Io

// Independent wire-protocol consumer; the real Tunemarchy pair is tested
// locally with TUNEMARCHY_SOURCE without granting CI access to another repo.
Item {
  id: root
  property var snapshot: ({})
  property var viewers: ({})
  readonly property bool connected: wire.connected && snapshot.v === 1
  readonly property string title: connected ? snapshot.title : ""
  readonly property bool playing: connected && snapshot.playing === true
  readonly property var queue: snapshot.queue || []
  readonly property var devices: snapshot.devices || []
  readonly property real volume: snapshot.volume || 0
  readonly property real position: snapshot.position || 0
  function send(message) { message.v = 1; wire.write(JSON.stringify(message) + "\n"); wire.flush() }
  function playPause() { send({action:"playPause"}) }
  function setVolume(value) { send({action:"volume",value:value}) }
  function seekTo(value) { send({action:"seek",value:value}) }
  function watch(key, visible, section) {
    if (visible) viewers[key] = section
    else delete viewers[key]
    var values = Object.values(viewers)
    send({action:"watch",visible:values.length > 0,section:values.indexOf("devices") >= 0 ? "devices" : (values.indexOf("queue") >= 0 ? "queue" : "")})
  }
  Socket {
    id: wire
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/atlastimed-omaspotify-" + Qt.md5(Quickshell.env("WAYLAND_DISPLAY")).slice(0,12) + ".sock"
    onConnectedChanged: if (!connected) root.snapshot = ({})
    parser: SplitParser { onRead: line => { root.snapshot = JSON.parse(line) } }
  }
  Timer { interval: 150; repeat: true; running: !wire.connected; triggeredOnStart: true; onTriggered: wire.connected = true }
}
