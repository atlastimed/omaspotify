pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

import "Api.js" as Api

// What is playing, full size: the artwork carries the page, with the names and
// what comes next beside it and a live equalizer underneath. The player bar
// below keeps playback controls, seek and volume.
Item {
  id: page

  property var panel: null
  // The equalizer runs only while this is true, so a closed view costs nothing.
  property bool active: false

  readonly property var service: panel ? panel.service : null
  readonly property bool hasCurrent: !!service && service.title !== ""
  readonly property var idleItem: service ? service.lastPlayedItem : null
  readonly property var upNext: service ? service.queue.slice(0, nextRows) : []
  readonly property int nextRows: stage.height > Style.space(460) ? 3 : 0

  onActiveChanged: if (active && service) service.loadQueue()

  Item {
    id: stage
    anchors.fill: parent
    anchors.margins: Style.space(10)

    readonly property bool equalizerUseful: !equalizer.unavailable
    readonly property real artSize: Math.max(Style.space(120), Math.min(
      height * (equalizerUseful ? 0.62 : 1), width * 0.44, Style.space(460)))

    Button {
      id: closeButton
      z: 2
      anchors.top: parent.top
      anchors.right: parent.right
      iconText: "󰅖"
      foreground: page.panel.foreground
      horizontalPadding: Style.space(7)
      focusable: false
      tooltipText: page.panel.shortcutHint("Back to browsing", "Esc")
      onClicked: page.panel.toggleNowPlayingExpanded()
    }

    BorderSurface {
      id: heroArt
      width: page.service && page.service.artworkEnabled ? stage.artSize : 0
      height: width
      visible: width > 0
      anchors.left: parent.left
      anchors.top: parent.top
      radius: Style.cornerRadius
      color: Style.normalFillFor(page.panel.foreground, page.panel.accent)
      borderSpec: Border.none()
      clip: true

      RetryImage {
        id: heroImage
        anchors.fill: parent
        requestedSource: page.service && page.service.artworkEnabled
          ? page.service.artworkFor(Api.idleMediaText(page.service.artUrl, page.idleItem, "imageUrl", ""))
          : ""
        sourceSize.width: 920
        sourceSize.height: 920
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: status === Image.Ready
        opacity: page.hasCurrent ? 1 : 0.5
      }

      Text {
        anchors.centerIn: parent
        visible: heroImage.status !== Image.Ready
        text: "󰎈"
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.displayLarge * 2
      }
    }

    Column {
      id: nameColumn
      anchors.left: heroArt.right
      anchors.leftMargin: heroArt.visible ? Style.space(22) : 0
      anchors.right: closeButton.left
      anchors.rightMargin: Style.space(8)
      anchors.top: heroArt.top
      spacing: Style.space(5)

      Text {
        objectName: "now-playing-title"
        width: parent.width
        text: Api.idleMediaText(page.service ? page.service.title : "", page.idleItem,
          "name", "Nothing playing")
        textFormat: Text.PlainText
        color: page.hasCurrent ? page.panel.foreground : page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.displayLarge
        font.bold: true
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }

      ArtistLinks {
        width: parent.width
        artists: page.service ? page.service.currentArtists : []
        fallbackText: Api.idleMediaText(page.service ? page.service.artist : "", page.idleItem,
          "subtitle", "Choose something to play")
        fallbackClickable: page.service && page.service.artist !== ""
          && page.service.currentArtistContextAvailable
          && artists.length === 0
        color: page.panel.accent
        accent: page.panel.accent
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.title
        maximumLineCount: 1
        elide: Text.ElideRight
        onArtistRequested: function(item) { page.panel.openItem(item) }
        onFallbackRequested: page.panel.openCurrentArtist()
      }

      Text {
        width: parent.width
        visible: text !== ""
        text: page.service && page.service.album !== "" ? page.service.album : ""
        textFormat: Text.PlainText
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.subtitle
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: page.service && page.service.playbackDeviceName !== ""
        text: page.service
          ? ((page.service.playing ? "Playing on " : "Connected to ")
            + page.service.playbackDeviceName)
          : ""
        textFormat: Text.PlainText
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      Button {
        visible: !page.hasCurrent && page.service && page.service.canResumeLastPlayed
        text: "Resume"
        iconText: "󰐊"
        foreground: page.panel.foreground
        bordered: true
        focusable: false
        onClicked: page.service.togglePlayback()
      }

      Item { width: 1; height: Style.space(6) }

      PanelSectionHeader {
        visible: page.upNext.length > 0
        text: "Up next"
        color: page.panel.muted
        fontFamily: page.panel.fontFamily
      }

      Repeater {
        model: page.upNext

        Text {
          required property var modelData
          width: nameColumn.width
          text: String(modelData.name || "") + (modelData.subtitle ? "  ·  " + modelData.subtitle : "")
          textFormat: Text.PlainText
          color: page.panel.muted
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }
    }

    Equalizer {
      id: equalizer
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: heroArt.visible && heroArt.height > nameColumn.height
        ? heroArt.bottom : nameColumn.bottom
      anchors.topMargin: Style.space(16)
      anchors.bottom: parent.bottom
      visible: !unavailable || !heroArt.visible
      active: page.active
      playing: page.service && page.service.playing
      backendBinary: page.service && page.service.usesSoloist ? "soloist" : "omaspotify-backend"
      configPath: page.service && page.service.stateDir
        ? page.service.stateDir + "/cava.conf" : ""
      scriptPath: page.service && page.service.pluginDir
        ? page.service.pluginDir + "/scripts/equalizer.sh" : ""
      mode: page.panel.equalizerMode
      muted: page.panel.muted
      onModeCycleRequested: page.panel.cycleEqualizerMode()
    }

    Text {
      anchors.left: nameColumn.left
      anchors.right: nameColumn.right
      anchors.bottom: heroArt.bottom
      visible: equalizer.unavailable
      text: equalizer.unavailableReason
      textFormat: Text.PlainText
      color: page.panel.muted
      font.family: page.panel.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }
  }
}
