import QtQuick
import Quickshell
import Quickshell.Io
import "fork" as Fork
import "companion" as Companion

ShellRoot {
  QtObject {
    id: player
    property bool accountConnected: true
    property bool hasPlayer: true
    property bool playing: false
    property string title: "Fixture song"
    property string artist: "Fixture artist"
    property string album: "Fixture album"
    property bool artworkEnabled: false
    property real positionSeconds: 10
    property real lengthSeconds: 120
    property real volume: 0.5
    property bool volumeSupported: true
    property bool playbackStartable: true
    property bool playbackControllable: true
    property bool currentTrackSaveAvailable: true
    property string currentTrackItemUri: "spotify:track:fixture"
    property bool currentTrackSaved: false
    property var queue: []
    property var devices: []
    property int queueRequests: 0
    property int deviceRequests: 0
    property int visibleCount: 0
    function setUiVisible(key, visible) { visibleCount += visible ? 1 : -1 }
    function refreshPosition() {}
    function syncCurrentTrackSaved(force) {}
    function loadQueue() { queueRequests++; queue = [{name:"Queued song",subtitle:"Queued artist"}] }
    function loadDevices() { deviceRequests++; devices = [{id:"fixture",name:"Desk",active:false}] }
    function togglePlayback() { playing = !playing }
    function setVolume(value) { volume = value }
    function seekSeconds(value) { positionSeconds = value }
    function next() { title = "Next fixture" }
    function previous() { title = "Previous fixture" }
    function setShuffle(value) {}
    function cycleRepeat() {}
    function toggleCurrentTrackSaved() { currentTrackSaved = !currentTrackSaved }
    function selectDevice(id) {}
  }
  Fork.CompanionBridge { id: bridge; service: player }
  Companion.Service { id: client }
  property int stage: 0
  property int ticks: 0
  function check(condition, message) { if (!condition) { console.error(message); Qt.exit(1) } }
  Timer {
    interval: 150
    repeat: true
    running: true
    onTriggered: {
      if (++ticks > 70) { console.error("Integration timeout stage " + stage); Qt.exit(1) }
      if (stage === 0 && client.connected) {
        check(client.title === "Fixture song", "initial snapshot")
        check(player.queueRequests === 0 && player.deviceRequests === 0, "idle fetched extras")
        client.watch("monitor1", true, "queue")
        client.playPause()
        stage = 1
      } else if (stage === 1 && client.playing && client.queue.length) {
        check(client.queue[0].title === "Queued song", "queue mapping")
        check(player.queueRequests === 1 && player.deviceRequests === 0, "queue requested twice")
        client.watch("monitor2", true, "queue")
        client.watch("monitor1", false, "")
        client.setVolume(0.75)
        client.seekTo(40)
        stage = 2
      } else if (stage === 2 && client.volume === 0.75 && client.position === 40) {
        check(player.queueRequests === 1 && player.visibleCount === 1, "multi-monitor duplicate watch")
        client.watch("monitor2", true, "devices")
        stage = 3
      } else if (stage === 3 && client.devices.length) {
        check(player.deviceRequests === 1, "devices not on demand")
        client.watch("monitor2", false, "")
        bridge.serving = false
        stage = 4
      } else if (stage === 4 && !client.connected) {
        check(!client.title && !client.playing, "stale state after disconnect")
        // setUiVisible is idempotent in the real service.
        bridge.serving = true
        player.title = "Reconnected"
        stage = 5
      } else if (stage === 5 && client.connected && client.title === "Reconnected") {
        console.log("COMPANION_INTEGRATION_PASS")
        Qt.quit()
      }
    }
  }
}
