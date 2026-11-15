pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

import "Api.js" as Api

// What is playing, full size: the artwork carries the page, with the names and
// what comes next beside it, over a live visualiser that fills the view behind
// them. The player bar below keeps playback controls, seek and volume.
Item {
  id: page

  property var panel: null
  // The visualiser runs only while this is true, so a closed view costs nothing.
  property bool active: false

  readonly property var service: panel ? panel.service : null
  readonly property bool hasCurrent: !!service && service.title !== ""
  readonly property var idleItem: service ? service.lastPlayedItem : null
  readonly property var upNext: service ? service.queue.slice(0, nextRows) : []
  readonly property int nextRows: stage.height > Style.space(460) ? 3 : 0

  onActiveChanged: {
    if (active && service) service.loadQueue()
    if (!active && panel) panel.visualizerTrayOpen = false
  }

  Item {
    id: stage
    anchors.fill: parent
    anchors.margins: Style.space(10)

    readonly property bool visualizerUseful: !visualizer.unavailable
    // The halo is drawn around the artwork, which steps in to leave it room.
    readonly property bool haloed: visualizerUseful && page.active
      && page.panel.visualizer.style === "halo" && heroArt.visible
    property real haloSpan: haloed
      ? Math.round(Math.min(height * 0.16, width * 0.1, Style.space(130))) : 0
    // Without a visualiser the artwork carries the whole page, centred in it.
    // With one it keeps to the top half, so the lower half is the visualiser's
    // and nothing it draws is hidden behind the cover. The halo is drawn round
    // the cover instead, so there the cover can be larger.
    readonly property real artSize: Math.max(Style.space(120), !visualizerUseful
      ? Math.min(height * 0.8, width * 0.5)
      : (haloed ? Math.min((height - haloSpan * 2) * 0.62, width * 0.44, Style.space(460))
        : Math.min(height * 0.5, width * 0.4, Style.space(460))))
    // How far down the cover and the names reach, in the visualiser's own
    // coordinates. Everything below is its room.
    readonly property real deck: Math.max(heroArt.y + heroArt.height,
      nameColumn.y + nameColumn.height) + Style.space(24)
    readonly property real heroTop: visualizerUseful ? 0 : Math.max(0, (height - artSize) / 2)
    Behavior on haloSpan { NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutCubic } }

    Visualizer {
      id: visualizer
      anchors.fill: parent
      // Out to the edges of the view, behind everything on it.
      anchors.margins: -Style.space(10)
      active: page.active
      playing: page.service && page.service.playing
      backendBinary: page.service && page.service.usesSoloist ? "soloist" : "omaspotify-backend"
      configPath: page.service && page.service.stateDir
        ? page.service.stateDir + "/cava.conf" : ""
      scriptPath: page.service && page.service.pluginDir
        ? page.service.pluginDir + "/scripts/visualizer.sh" : ""
      settings: page.panel.visualizer
      accent: page.panel.accent
      foreground: page.panel.foreground
      muted: page.panel.muted
      fontFamily: page.panel.fontFamily
      artworkItem: heroImage
      artworkKey: heroImage.status === Image.Ready ? String(heroImage.source) : ""
      swatchDir: page.service ? page.service.artworkDir : ""
      artRect: Qt.rect(heroArt.x + Style.space(10), heroArt.y + Style.space(10),
        heroArt.width, heroArt.height)
      artSpan: stage.haloSpan
      deck: stage.deck
    }

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

    Button {
      id: tuneButton
      z: 2
      anchors.top: parent.top
      anchors.right: closeButton.left
      anchors.rightMargin: Style.space(4)
      visible: stage.visualizerUseful
      iconText: "󰒓"
      text: Api.visualizerChoiceName(page.panel.visualizer, "style")
      foreground: page.panel.foreground
      horizontalPadding: Style.space(7)
      focusable: false
      selected: page.panel.visualizerTrayOpen
      tooltipText: page.panel.shortcutHint("Visualiser options", "V")
      onClicked: page.panel.visualizerTrayOpen = !page.panel.visualizerTrayOpen
    }

    // Every choice is a short list, so a click steps to the next one and the
    // view behind shows the change straight away.
    BorderSurface {
      id: tray
      objectName: "visualizer-tray"
      z: 3
      visible: page.panel.visualizerTrayOpen && stage.visualizerUseful
      anchors.top: tuneButton.bottom
      anchors.topMargin: Style.space(6)
      anchors.right: closeButton.right
      width: Style.space(250)
      height: trayRows.implicitHeight + Style.space(12)
      radius: Style.cornerRadius
      color: page.panel.popupBackground
      borderSpec: page.panel.popupBorderSpec

      readonly property string style: page.panel.visualizer.style
      readonly property var rows: [
        { key: "style", label: "Style", shown: true },
        { key: "palette", label: "Colours", shown: true },
        { key: "sensitivity", label: "Sensitivity", shown: true },
        { key: "smoothing", label: "Motion", shown: true },
        { key: "glow", label: "Glow", shown: true },
        { key: "brightness", label: "Brightness", shown: true },
        { key: "bands", label: "Bands", shown: true },
        { key: "mirror", label: "Bass in the middle", shown: style !== "halo" },
        { key: "peaks", label: "Falling caps", shown: ["bars", "halo", "pixels"].indexOf(style) >= 0 }
      ]

      Column {
        id: trayRows
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(6)

        Repeater {
          model: tray.rows

          Button {
            required property var modelData
            width: trayRows.width
            visible: modelData.shown
            leftAlign: true
            focusable: false
            foreground: page.panel.foreground
            fontFamily: page.panel.fontFamily
            text: modelData.label
            onClicked: page.panel.stepVisualizer(modelData.key)

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: Api.visualizerChoiceName(page.panel.visualizer, parent.modelData.key)
              textFormat: Text.PlainText
              color: page.panel.accent
              font.family: page.panel.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }
      }
    }

    BorderSurface {
      id: heroArt
      width: page.service && page.service.artworkEnabled ? stage.artSize : 0
      height: width
      visible: width > 0
      anchors.left: parent.left
      anchors.leftMargin: stage.haloSpan
      anchors.top: parent.top
      anchors.topMargin: stage.heroTop + stage.haloSpan
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
        onLocalSourceMissing: page.service.forgetArtwork(
          Api.idleMediaText(page.service.artUrl, page.idleItem, "imageUrl", ""))
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
      anchors.leftMargin: (heroArt.visible ? Style.space(22) : 0) + stage.haloSpan
      anchors.right: tuneButton.left
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

    // Why the view is still: nothing local is playing.
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(18)
      visible: stage.visualizerUseful && visualizer.note !== ""
      width: Math.min(parent.width, Style.space(460))
      text: visualizer.note
      textFormat: Text.PlainText
      color: page.panel.muted
      font.family: page.panel.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }

    Text {
      anchors.left: nameColumn.left
      anchors.right: nameColumn.right
      anchors.bottom: heroArt.bottom
      visible: visualizer.unavailable
      text: visualizer.unavailableReason
      textFormat: Text.PlainText
      color: page.panel.muted
      font.family: page.panel.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }
  }
}
