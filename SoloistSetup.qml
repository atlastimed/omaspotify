import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root
  required property var panel
  readonly property var manager: panel.service ? panel.service.soloist : null
  spacing: Style.space(8)
  Text {
    width: parent.width
    text: "SPOTIFY SOLOIST · LOCAL AUDIO"
    color: root.panel.foreground
    font.family: root.panel.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }
  Text {
    width: parent.width
    text: root.manager && root.manager.credentialsAvailable
      ? "Paired and ready. Soloist starts on demand and follows your system audio output."
      : "Install Spotify's lightweight player, create your personal Soloist API key in the developer dashboard, then save it here. Finally, open the official Spotify app on this network and select OmaSpotify from its device picker once."
    color: root.panel.muted
    font.family: root.panel.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }
  Flow {
    width: parent.width
    spacing: Style.space(7)
    Button {
      text: root.manager && root.manager.setupBusy ? "Installing…" : "Install / repair Soloist"
      visible: root.manager && !root.manager.playbackReady
      enabled: root.manager && !root.manager.setupBusy
      foreground: root.panel.foreground
      onClicked: root.manager.setupPlayback()
    }
    Button {
      text: "Soloist key dashboard"
      foreground: root.panel.foreground
      onClicked: Qt.openUrlExternally("https://developer.spotify.com/dashboard/soloist")
    }
    Button {
      text: "Update Soloist"
      foreground: root.panel.foreground
      visible: root.manager && root.manager.playbackReady
      enabled: root.manager && !root.manager.busy
      onClicked: root.manager.execute("update")
    }
  }
  TextField {
    id: key
    width: parent.width
    password: true
    foreground: root.panel.foreground
    placeholderText: root.manager && root.manager.keyAvailable ? "Replace Soloist API key" : "Soloist API key"
    enabled: root.manager && root.manager.playbackReady && !root.manager.busy
  }
  Button {
    text: "Save key and start pairing"
    foreground: root.panel.foreground
    enabled: root.manager && root.manager.playbackReady && !root.manager.busy && key.text.trim() !== ""
    onClicked: { root.manager.saveKey(key.text); key.text = "" }
  }
  Text {
    width: parent.width
    text: root.manager && root.manager.playbackReady
      ? (root.manager.keyAvailable ? "Key saved in your desktop keyring. " : "No key saved yet. ") + "Builds renew automatically near expiry; updates apply when playback next starts. Current build: " + root.manager.daysRemaining + " days remaining."
      : "Downloads directly from Spotify. Builds expire after 90 days; a user service checks for renewal daily."
    color: root.panel.muted
    font.family: root.panel.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
}
