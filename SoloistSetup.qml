pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root
  required property var panel
  readonly property var manager: panel.service ? panel.service.soloist : null
  readonly property bool paired: !!manager && manager.credentialsAvailable
  spacing: Style.space(7)

  PanelSectionHeader {
    text: "Local audio with Spotify Soloist"
    color: root.panel.muted
    fontFamily: root.panel.fontFamily
    fontSize: Style.font.bodySmall
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: root.paired
      ? "Paired and ready. Soloist starts on demand and follows your system audio output."
      : "Install Spotify's lightweight player, create your personal Soloist API key in the developer dashboard, then save it here. Finally, open the official Spotify app on this network and select OmaSpotify from its device picker once."
    color: root.panel.muted
    font.family: root.panel.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  Flow {
    width: parent.width
    spacing: Style.space(6)

    SettingButton {
      panel: root.panel
      cursorId: "set-soloist-install"
      text: root.manager && root.manager.setupBusy ? "Installing…" : "Install or repair Soloist"
      visible: root.manager && !root.manager.playbackReady
      enabled: root.manager && !root.manager.setupBusy
      onClicked: root.manager.setupPlayback()
    }
    SettingButton {
      panel: root.panel
      cursorId: "set-soloist-dashboard"
      text: "Soloist key dashboard"
      iconText: "󰏌"
      onClicked: Qt.openUrlExternally("https://developer.spotify.com/dashboard/soloist")
    }
    SettingButton {
      panel: root.panel
      cursorId: "set-soloist-update"
      text: "Update Soloist"
      visible: root.manager && root.manager.playbackReady
      enabled: root.manager && !root.manager.busy
      onClicked: root.manager.execute("update")
    }
  }

  SettingField {
    id: key
    panel: root.panel
    cursorId: "set-soloist-key"
    width: parent.width
    password: true
    placeholderText: root.manager && root.manager.keyAvailable
      ? "Replace Soloist API key" : "Soloist API key"
    enabled: root.manager && root.manager.playbackReady && !root.manager.busy
  }

  SettingButton {
    panel: root.panel
    cursorId: "set-soloist-save"
    text: "Save key and start pairing"
    enabled: root.manager && root.manager.playbackReady && !root.manager.busy && key.text.trim() !== ""
    onClicked: {
      root.manager.saveKey(key.text)
      key.text = ""
    }
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: root.manager && root.manager.playbackReady
      ? (root.manager.keyAvailable ? "Key saved in your desktop keyring. " : "No key saved yet. ") + "Builds renew automatically near expiry; updates apply when playback next starts. Current build: " + root.manager.daysRemaining + " days remaining."
      : "Downloads directly from Spotify. Builds expire after 90 days; a user service checks for renewal daily."
    color: root.panel.muted
    font.family: root.panel.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }
}
