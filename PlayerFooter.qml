pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

import "Api.js" as Api

// The player bar: what is playing, the transport with its seek bar, and where it
// is going out. It stays on screen under every page.
Item {
  id: part

  property var panel: null

  readonly property var service: panel ? panel.service : null
  readonly property bool expanded: panel && panel.nowPlayingExpanded
  readonly property bool narrow: panel && panel.extraNarrowWidth
  readonly property bool remote: service && service.useRemotePlayback
  readonly property bool muted: service && service.volume <= 0.001

  function contextAnchor() {
    return currentTrackMoreButton.visible ? currentTrackMoreButton : null
  }

  Row {
    id: playerRow
    anchors.fill: parent
    anchors.topMargin: Style.space(2)
    anchors.bottomMargin: Style.space(2)
    spacing: Style.space(part.narrow ? 6 : 14)

    Item {
      id: nowPlaying
      width: part.expanded
        ? (nowPlayingActions.visible ? nowPlayingActions.width : 0)
        : part.narrow
        ? Math.max(Style.space(80), playerRow.width - transport.width - playerRow.spacing)
        : Math.max(Style.space(190), Math.min(Style.space(360), playerRow.width * 0.32))
      height: parent.height
      readonly property bool artworkVisible: !part.expanded
        && (!part.service || part.service.artworkEnabled)

      BorderSurface {
        id: nowPlayingArtwork
        width: nowPlaying.artworkVisible ? Math.min(parent.height,
          Style.space(part.narrow ? 52 : 64)) : 0
        height: width
        visible: nowPlaying.artworkVisible
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        radius: Style.cornerRadius
        color: Style.normalFillFor(part.panel.foreground, part.panel.accent)
        borderSpec: Border.none()
        clip: true

        RetryImage {
          id: playerArtworkImage
          anchors.fill: parent
          requestedSource: part.service && part.service.artworkEnabled
            ? Api.idleMediaText(part.service.artUrl,
              part.service.lastPlayedItem, "imageUrl", "")
            : ""
          sourceSize.width: 128
          sourceSize.height: 128
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          visible: status === Image.Ready
          opacity: part.service && part.service.title ? 1 : 0.55
        }

        Text {
          anchors.centerIn: parent
          visible: playerArtworkImage.status !== Image.Ready
          text: "󰎈"
          color: part.panel.muted
          font.family: part.panel.fontFamily
          font.pixelSize: Style.font.iconLarge
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: part.panel.toggleNowPlayingExpanded()
        }
      }

      Column {
        anchors.left: nowPlayingArtwork.right
        anchors.leftMargin: nowPlayingArtwork.visible ? Style.space(10) : 0
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Row {
          width: parent.width
          spacing: Style.space(2)

          Text {
            id: playerTitle
            visible: !part.expanded
            width: Math.max(20, parent.width
              - (nowPlayingActions.visible ? nowPlayingActions.width + parent.spacing : 0))
            anchors.verticalCenter: parent.verticalCenter
            text: Api.idleMediaText(part.service ? part.service.title : "",
              part.service ? part.service.lastPlayedItem : null, "name", "Nothing playing")
            textFormat: Text.PlainText
            color: part.service && part.service.title
              ? part.panel.foreground : part.panel.muted
            font.family: part.panel.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight

            HoverHandler { id: playerTitleHover }
            PanelToolTip {
              visible: playerTitleHover.hovered && playerTitle.truncated
              text: playerTitle.text
            }
          }

          Row {
            id: nowPlayingActions
            visible: (!part.narrow || part.expanded)
              && part.service && !!part.service.currentTrackItem
            spacing: Style.space(1)
            anchors.verticalCenter: parent.verticalCenter

            Button {
              id: currentTrackLikeButton
              objectName: "current-track-like"
              iconText: part.service && part.service.currentTrackSaved ? "󰋑" : "󰋕"
              iconSize: Style.font.body
              foreground: part.service && part.service.currentTrackSaved
                ? part.panel.accent : part.panel.foreground
              accent: part.panel.accent
              enabled: part.service && part.service.currentTrackSaveAvailable
              horizontalPadding: Style.space(4)
              verticalPadding: Style.space(2)
              tooltipText: part.service && part.service.currentTrackSaveChecking
                ? "Checking liked status…"
                : (part.service && part.service.currentTrackSaveBusy
                  ? "Updating liked status…"
                  : (part.service && part.service.currentTrackSaved
                    ? "Remove like" : "Like this song"))
              hasCursor: part.panel.cursorShown("footer", "like")
              onClicked: if (part.service) part.service.toggleCurrentTrackSaved()
              onHovered: function(on) { if (on) part.panel.setPanelCursor("footer", "like") }
              PanelKeyHint { panel: part.panel; region: "footer"; action: "like" }
            }

            Button {
              id: currentTrackMoreButton
              objectName: "current-track-more"
              iconText: "󰇙"
              iconSize: Style.font.body
              foreground: part.panel.foreground
              horizontalPadding: Style.space(4)
              verticalPadding: Style.space(2)
              tooltipText: part.panel.shortcutHint("Song actions", "C")
              hasCursor: part.panel.cursorShown("footer", "context")
              onClicked: part.panel.openNowPlayingContext()
              onHovered: function(on) { if (on) part.panel.setPanelCursor("footer", "context") }
              PanelKeyHint { panel: part.panel; region: "footer"; action: "context"; sequences: ["C"] }
            }
          }
        }

        CursorSurface {
          id: currentArtistCursor
          z: 2
          clip: false
          visible: !part.expanded
          width: parent.width
          height: currentArtistLinks.implicitHeight
          hasCursor: part.panel.cursorShown("footer", "artist")
          foreground: part.panel.foreground
          HoverHandler {
            id: currentArtistHover
            onHoveredChanged: if (hovered) part.panel.setPanelCursor("footer", "artist")
          }
          PanelToolTip {
            visible: currentArtistHover.hovered
            text: part.panel.shortcutHint("Open artist", "Ctrl+Shift+A")
          }

          ArtistLinks {
            id: currentArtistLinks
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: currentArtistHint.reservedRight
            anchors.verticalCenter: parent.verticalCenter
            artists: part.service ? part.service.currentArtists : []
            fallbackText: Api.idleMediaText(part.service ? part.service.artist : "",
              part.service ? part.service.lastPlayedItem : null,
              "subtitle", "Choose something to play")
            fallbackClickable: part.service && part.service.artist !== ""
              && part.service.currentArtistContextAvailable
              && artists.length === 0
            color: part.panel.muted
            accent: part.panel.accent
            font.family: part.panel.fontFamily
            font.pixelSize: Style.font.bodySmall
            onArtistRequested: function(item) { part.panel.openItem(item) }
            onFallbackRequested: part.panel.openCurrentArtist()
          }

          PanelKeyHint {
            id: currentArtistHint
            panel: part.panel
            region: "footer"
            action: "artist"
            sequences: ["Ctrl+Shift+A"]
          }
        }

        CursorSurface {
          id: currentAlbumCursor
          z: 1
          clip: false
          width: parent.width
          height: currentAlbumLinks.implicitHeight
          visible: !part.expanded && part.service && part.service.currentAlbumContextAvailable
          hasCursor: part.panel.cursorShown("footer", "album")
          foreground: part.panel.foreground
          HoverHandler {
            id: currentAlbumHover
            onHoveredChanged: if (hovered) part.panel.setPanelCursor("footer", "album")
          }
          PanelToolTip {
            visible: currentAlbumHover.hovered
            text: part.panel.shortcutHint("Open album", "Ctrl+Shift+B")
          }

          ArtistLinks {
            id: currentAlbumLinks
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: currentAlbumHint.reservedRight
            anchors.verticalCenter: parent.verticalCenter
            artists: []
            fallbackText: part.service ? part.service.album : ""
            fallbackClickable: visible
            color: part.panel.muted
            accent: part.panel.accent
            font.family: part.panel.fontFamily
            font.pixelSize: Style.font.caption
            onFallbackRequested: part.panel.openCurrentAlbum()
          }

          PanelKeyHint {
            id: currentAlbumHint
            panel: part.panel
            region: "footer"
            action: "album"
            sequences: ["Ctrl+Shift+B"]
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        z: 20
        enabled: part.service && !!part.service.currentTrackItem
        onClicked: part.panel.openNowPlayingContext()
      }
    }

    Column {
      id: transport
      width: part.narrow
        ? Math.max(transportButtons.implicitWidth, Style.space(108))
        : Math.max(Style.space(120), parent.width - nowPlaying.width
          - outputControls.width - parent.spacing * 2)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Row {
        id: transportButtons
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(4)

        TransportButton {
          visible: !part.narrow
          glyphText: "󰒟"
          foreground: part.panel.foreground
          indicator: part.service && part.service.shuffle
          hasCursor: part.panel.cursorShown("footer", "shuffle")
          tooltipText: part.panel.shortcutHint(
            part.service && part.service.shuffle ? "Shuffle is on" : "Shuffle is off", "Ctrl+S")
          enabled: part.service && part.service.playbackControllable
          onClicked: if (part.service) part.service.setShuffle(!part.service.shuffle)
          onHovered: function(on) { if (on) part.panel.setPanelCursor("footer", "shuffle") }
          PanelKeyHint { panel: part.panel; region: "footer"; action: "shuffle"; sequences: ["Ctrl+S"] }
        }
        TransportButton {
          glyphText: "󰒮"
          visible: !part.panel.spokenWordPlaying
          foreground: part.panel.foreground
          hasCursor: part.panel.cursorShown("footer", "previous")
          tooltipText: part.panel.shortcutHint("Previous", "Ctrl+Left")
          enabled: part.service && part.service.playbackControllable
          onClicked: if (part.service) part.service.previous()
          onHovered: function(on) { if (on) part.panel.setPanelCursor("footer", "previous") }
          PanelKeyHint { panel: part.panel; region: "footer"; action: "previous"; sequences: ["Ctrl+Left"] }
        }
        TransportButton {
          glyphText: "󰵛"
          visible: part.panel.spokenWordPlaying
          foreground: part.panel.foreground
          hasCursor: part.panel.cursorShown("footer", "back15")
          tooltipText: "Back 15 seconds"
          enabled: part.service && part.service.playbackControllable
          onClicked: if (part.service) part.service.skipBySeconds(-15)
          onHovered: function(on) { if (on) part.panel.setPanelCursor("footer", "back15") }
          PanelKeyHint { panel: part.panel; region: "footer"; action: "back15" }
        }
        TransportButton {
          anchors.verticalCenter: parent.verticalCenter
          controlSize: Style.space(36)
          glyphText: part.service && part.service.playing ? "󰏤" : "󰐊"
          glyphSize: Style.font.iconLarge
          foreground: part.panel.foreground
          bordered: true
          hasCursor: part.panel.cursorShown("footer", "play")
          tooltipText: part.panel.shortcutHint(
            part.service && part.service.playing ? "Pause"
              : (part.service && part.service.canResumeLastPlayed
                ? "Resume last played" : "Play"), "Space")
          enabled: part.service && part.service.playbackStartable
          onClicked: if (part.service) part.service.togglePlayback()
          onHovered: function(on) { if (on) part.panel.setPanelCursor("footer", "play") }
          PanelKeyHint { panel: part.panel; region: "footer"; action: "play"; sequences: ["Space"] }
        }
        TransportButton {
          glyphText: "󰵙"
          visible: part.panel.spokenWordPlaying
          foreground: part.panel.foreground
          hasCursor: part.panel.cursorShown("footer", "forward30")
          tooltipText: "Forward 30 seconds"
          enabled: part.service && part.service.playbackControllable
          onClicked: if (part.service) part.service.skipBySeconds(30)
          onHovered: function(on) { if (on) part.panel.setPanelCursor("footer", "forward30") }
          PanelKeyHint { panel: part.panel; region: "footer"; action: "forward30" }
        }
        TransportButton {
          glyphText: "󰒭"
          visible: !part.panel.spokenWordPlaying
          foreground: part.panel.foreground
          hasCursor: part.panel.cursorShown("footer", "next")
          tooltipText: part.panel.shortcutHint("Next", "Ctrl+Right")
          enabled: part.service && part.service.playbackControllable
          onClicked: if (part.service) part.service.next()
          onHovered: function(on) { if (on) part.panel.setPanelCursor("footer", "next") }
          PanelKeyHint { panel: part.panel; region: "footer"; action: "next"; sequences: ["Ctrl+Right"] }
        }
        TransportButton {
          visible: !part.narrow
          glyphText: part.service && part.service.repeatMode === "track" ? "󰑘" : "󰑖"
          foreground: part.panel.foreground
          indicator: part.service && part.service.repeatMode !== "off"
          hasCursor: part.panel.cursorShown("footer", "repeat")
          tooltipText: part.panel.shortcutHint("Repeat: "
            + Api.repeatModeLabel(part.service ? part.service.repeatMode : "off"), "Ctrl+R")
          enabled: part.service && part.service.playbackControllable
          onClicked: if (part.service) part.service.cycleRepeat()
          onHovered: function(on) { if (on) part.panel.setPanelCursor("footer", "repeat") }
          PanelKeyHint { panel: part.panel; region: "footer"; action: "repeat"; sequences: ["Ctrl+R"] }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        Text {
          id: positionFooterTime
          anchors.verticalCenter: parent.verticalCenter
          text: Api.millisecondsToClock((part.service ? part.service.positionSeconds : 0) * 1000)
          textFormat: Text.PlainText
          color: part.panel.muted
          font.family: part.panel.fontFamily
          font.pixelSize: Style.font.caption
        }

        CursorSurface {
          id: seekCursor
          width: Math.max(30, parent.width - positionFooterTime.implicitWidth
            - durationFooterTime.implicitWidth - Style.space(12))
          height: positionSlider.implicitHeight
          anchors.verticalCenter: parent.verticalCenter
          hasCursor: part.panel.cursorShown("footer", "seek")
          foreground: part.panel.foreground

          HoverHandler {
            id: seekHover
            onHoveredChanged: if (hovered) part.panel.setPanelCursor("footer", "seek")
          }

          PlaybackSlider {
            id: positionSlider
            anchors.fill: parent
            bar: part.panel.panelBar
            minimum: 0
            maximum: Math.max(1, part.service ? part.service.lengthSeconds : 1)
            step: 5
            sourceValue: part.service ? part.service.positionSeconds : 0
            sourcePending: part.service && part.service.pendingRemoteSeek !== null
            acknowledgeTolerance: 2
            contextKey: part.service
              ? part.service.currentUri + "|" + part.service.playbackDeviceName : ""
            onCommitted: function(value) {
              if (part.service) part.service.seekSeconds(value)
            }

            PanelKeyHint {
              panel: part.panel
              region: "footer"
              action: "seek"
              sequences: ["Shift+Left", "Shift+Right"]
              active: part.panel.shortcutHintsActive && part.service
                && part.service.playbackControllable
            }
          }

          // Shows where a click would land, in place of a static tooltip.
          Loader {
            active: seekHover.hovered && part.service && part.service.lengthSeconds > 0
            z: 30
            x: Math.max(0, Math.min(seekCursor.width - width,
              seekHover.point.position.x - width / 2))
            y: -height - Style.space(4)
            sourceComponent: BorderSurface {
              implicitWidth: seekPreview.implicitWidth + Style.space(10)
              implicitHeight: seekPreview.implicitHeight + Style.space(4)
              radius: Style.cornerRadius
              color: Commons.Color.tooltip.background
              borderSpec: Border.flat(Commons.Color.tooltip.border, Math.max(1, Style.normalBorderWidth))

              Text {
                id: seekPreview
                anchors.centerIn: parent
                text: Api.millisecondsToClock(Math.max(0, Math.min(1,
                  seekHover.point.position.x / Math.max(1, seekCursor.width)))
                  * part.service.lengthSeconds * 1000)
                textFormat: Text.PlainText
                color: Commons.Color.tooltip.text
                font.family: part.panel.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Text {
          id: durationFooterTime
          anchors.verticalCenter: parent.verticalCenter
          text: Api.millisecondsToClock((part.service ? part.service.lengthSeconds : 0) * 1000)
          textFormat: Text.PlainText
          color: part.panel.muted
          font.family: part.panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Column {
      id: outputControls
      visible: !part.narrow
      width: visible ? Math.max(Style.space(150), Math.min(Style.space(220),
        playerRow.width * 0.23)) : 0
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(3)

        Button {
          id: muteButton
          anchors.verticalCenter: parent.verticalCenter
          iconText: part.muted ? "󰝟" : "󰕾"
          foreground: part.muted ? part.panel.muted : part.panel.foreground
          enabled: part.service && part.service.volumeSupported
          horizontalPadding: Style.space(5)
          verticalPadding: Style.space(3)
          focusable: false
          tooltipText: part.panel.shortcutHint(part.muted ? "Unmute" : "Mute", "M")
          onClicked: part.panel.toggleMute()
        }

        CursorSurface {
          width: Math.max(35, parent.width - muteButton.width - parent.spacing)
          height: volumeSlider.implicitHeight
          anchors.verticalCenter: parent.verticalCenter
          hasCursor: part.panel.cursorShown("footer", "volume")
          foreground: part.panel.foreground

          HoverHandler {
            id: volumeSliderHover
            onHoveredChanged: if (hovered) part.panel.setPanelCursor("footer", "volume")
          }

          PlaybackSlider {
            id: volumeSlider
            anchors.fill: parent
            enabled: part.service && part.service.volumeSupported
            bar: part.panel.panelBar
            minimum: 0
            maximum: 1
            step: 0.05
            sourceValue: part.service ? part.service.volume : 0
            sourcePending: part.service && part.service.volumePending
            contextKey: part.service ? part.service.playbackDeviceName : ""
            liveCommit: true
            onCommitted: function(value, live) { part.panel.setPanelVolume(value, live) }
            onRightClicked: part.panel.toggleMute()

            PanelToolTip {
              visible: volumeSliderHover.hovered
              text: "Volume · Ctrl+Up / Ctrl+Down · M to mute"
            }
            PanelKeyHint {
              panel: part.panel
              region: "footer"
              action: "volume"
              sequences: ["M", "Ctrl+Up", "Ctrl+Down"]
              active: part.panel.shortcutHintsActive && part.service
                && part.service.volumeSupported
            }
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(1)

        Button {
          id: devicesButton
          width: Math.max(Style.space(40), parent.width - sleepButton.width - lyricsButton.width
            - expandButton.width - parent.spacing * 3)
          anchors.verticalCenter: parent.verticalCenter
          clip: true
          leftAlign: true
          text: part.service ? part.service.playbackDeviceName : ""
          iconText: part.remote ? "󰦧" : "󰋋"
          fontSize: Style.font.caption
          iconSize: Style.font.bodySmall
          foreground: part.remote ? part.panel.accent : part.panel.muted
          horizontalPadding: Style.space(5)
          verticalPadding: Style.space(3)
          focusable: false
          hasCursor: part.panel.cursorShown("footer", "devices")
          tooltipText: part.panel.shortcutHint(part.service && part.service.playbackDeviceName
            ? "Playing on " + part.service.playbackDeviceName : "Choose a device", "Alt+Shift+D")
          onClicked: part.panel.chooseTab("devices")
          onHovered: function(on) { if (on) part.panel.setPanelCursor("footer", "devices") }
          PanelKeyHint { panel: part.panel; region: "footer"; action: "devices"; sequences: ["Alt+Shift+D"] }
        }

        Button {
          id: sleepButton
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰔛"
          iconSize: Style.font.bodySmall
          foreground: part.service && part.service.sleepActive ? part.panel.accent : part.panel.foreground
          selected: part.service && part.service.sleepActive
          horizontalPadding: Style.space(5)
          verticalPadding: Style.space(3)
          focusable: false
          hasCursor: part.panel.cursorShown("footer", "sleep")
          tooltipText: part.service ? part.service.sleepStatusText() : "Sleep timer"
          onClicked: part.panel.openSleepPopup()
          onHovered: function(on) { if (on) part.panel.setPanelCursor("footer", "sleep") }
          PanelKeyHint { panel: part.panel; region: "footer"; action: "sleep" }
        }

        Button {
          id: lyricsButton
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰎈"
          iconSize: Style.font.bodySmall
          foreground: part.panel.foreground
          horizontalPadding: Style.space(5)
          verticalPadding: Style.space(3)
          focusable: false
          enabled: part.service && part.service.lyricsAvailable
          hasCursor: part.panel.cursorShown("footer", "lyrics")
          tooltipText: part.panel.shortcutHint("Open lyrics in Omasing", "Ctrl+Shift+L")
          onClicked: part.panel.openLyrics()
          onHovered: function(on) { if (on) part.panel.setPanelCursor("footer", "lyrics") }
          PanelKeyHint { panel: part.panel; region: "footer"; action: "lyrics"; sequences: ["Ctrl+Shift+L"] }
        }

        Button {
          id: expandButton
          anchors.verticalCenter: parent.verticalCenter
          iconText: part.expanded ? "󰊔" : "󰊓"
          iconSize: Style.font.bodySmall
          foreground: part.panel.foreground
          selected: part.expanded
          horizontalPadding: Style.space(5)
          verticalPadding: Style.space(3)
          focusable: false
          hasCursor: part.panel.cursorShown("footer", "expand")
          tooltipText: part.panel.shortcutHint(part.expanded
            ? "Back to browsing" : "Now playing view", "E")
          onClicked: part.panel.toggleNowPlayingExpanded()
          onHovered: function(on) { if (on) part.panel.setPanelCursor("footer", "expand") }
          PanelKeyHint { panel: part.panel; region: "footer"; action: "expand"; sequences: ["E"] }
        }
      }
    }
  }
}
