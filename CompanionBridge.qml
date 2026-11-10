pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "Companion.js" as Protocol

Item {
  id: root
  required property var service
  property bool serving: true
  property string socketPath: Quickshell.env("XDG_RUNTIME_DIR")
    + "/atlastimed-omaspotify-" + Qt.md5(Quickshell.env("WAYLAND_DISPLAY")).slice(0, 12) + ".sock"
  property var clients: []
  property int nextClient: 0
  readonly property string snapshot: JSON.stringify(Protocol.snapshot(service))
  readonly property bool watched: clients.some(function(c) { return c && c.watching })
  onSnapshotChanged: publish.restart()

  function remove(client) {
    service.setUiVisible(client.surfaceKey, false)
    clients = clients.filter(function(c) { return c !== client })
  }
  function receive(client, line) {
    var message = Protocol.command(line)
    if (!message) { client.connected = false; return }
    if (message.action === "watch") {
      const wasVisible = client.watching
      const oldSection = client.section
      client.watching = message.visible
      client.section = message.visible ? message.section : ""
      if (wasVisible !== client.watching) service.setUiVisible(client.surfaceKey, client.watching)
      // Reassign so the timer follows visibility changes on any connection.
      clients = clients.slice()
      if (client.watching && (!wasVisible || oldSection !== client.section)) {
        if ((client.section === "queue" || client.section === "both")) service.loadQueue()
        if ((client.section === "devices" || client.section === "both")) service.loadDevices(null, undefined, true)
        service.refreshPosition()
        service.syncCurrentTrackSaved(false)
      }
      client.sendSnapshot()
      return
    }
    switch (message.action) {
    case "playPause": if (service.playbackStartable || service.playbackControllable) service.togglePlayback(); break
    case "next": if (service.playbackControllable) service.next(); break
    case "previous": if (service.playbackControllable) service.previous(); break
    case "seek": if (service.playbackControllable) service.seekSeconds(message.value); break
    case "volume": if (service.volumeSupported) service.setVolume(message.value, true); break
    case "shuffle": if (service.playbackControllable) service.setShuffle(!service.shuffle); break
    case "repeat": if (service.playbackControllable) service.cycleRepeat(); break
    case "like": if (service.currentTrackSaveAvailable) service.toggleCurrentTrackSaved(); break
    case "device": if (service.accountConnected) service.selectDevice(message.value, true); break
    }
  }

  Timer {
    id: publish
    interval: 80
    onTriggered: root.clients.forEach(function(c) { if (c) c.sendSnapshot() })
  }
  Timer {
    interval: 1000
    repeat: true
    running: root.watched && root.service.playing
    onTriggered: root.service.refreshPosition()
  }
  Timer {
    id: queueRefresh
    interval: 1200
    onTriggered: {
      if (root.clients.some(function(c) { return c && c.watching && (c.section === "queue" || c.section === "both") }))
        root.service.loadQueue()
    }
  }
  Connections {
    target: root.service
    function onCurrentTrackItemUriChanged() { queueRefresh.restart() }
  }
  SocketServer {
    active: root.serving && Quickshell.env("XDG_RUNTIME_DIR") !== ""
    path: root.socketPath
    handler: Socket {
      id: client
      property string surfaceKey: ""
      property bool watching: false
      property string section: ""
      function sendSnapshot() {
        if (connected) { write(root.snapshot + "\n"); flush() }
      }
      Component.onCompleted: {
        if (root.clients.length >= 8) { connected = false; return }
        surfaceKey = "tunemarchy-" + (++root.nextClient)
        root.clients = root.clients.concat([client])
        Qt.callLater(sendSnapshot)
      }
      onConnectedChanged: if (!connected) root.remove(client)
      Component.onDestruction: root.remove(client)
      parser: SplitParser { onRead: line => root.receive(client, line) }
    }
  }
}
