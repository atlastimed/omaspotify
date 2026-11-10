pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import qs.Ui

import "Api.js" as Api

// What the bar widget's popup shows: the mini-player, its menu and its shortcut
// list. The widget owns the state; this is built the first time it is opened.
Item {
  id: mini

  property var widget: null
  readonly property bool usesContextMenu: mini.widget.contextMenuVisible
    && !mini.widget.miniShortcutHelpVisible

  component KeyHint: ShortcutHint {
    ctrlHeld: mini.widget.hintCtrlHeld
    shiftHeld: mini.widget.hintShiftHeld
    altHeld: mini.widget.hintAltHeld
    active: mini.widget.shortcutHintsActive
    foreground: mini.widget.foreground
    accent: Commons.Color.accent
  }

  ShortcutModifiers {
    id: shortcutModifiers
  }

  implicitHeight: usesContextMenu ? barContextMenu.implicitHeight
    : (mini.widget.miniShortcutHelpVisible ? miniShortcutHelp.implicitHeight
      : contentColumn.implicitHeight)
  focus: true
  Keys.priority: Keys.BeforeItem
  onActiveFocusChanged: if (!activeFocus) mini.widget.heldModifierFlags = 0
  Keys.onShortcutOverride: function(event) {
    mini.widget.noteHeldModifiers(event, true)
    if (shortcutModifiers.isHintModifierKey(event.key)) event.accepted = true
  }
  Keys.onPressed: function(event) { mini.widget.handleMiniKey(event) }
  Keys.onReleased: function(event) {
    mini.widget.noteHeldModifiers(event, false)
    if (shortcutModifiers.isHintModifierKey(event.key)) event.accepted = true
  }

  Shortcut {
    sequence: "Ctrl+/"
    enabled: mini.widget.popupOpen && !mini.widget.lyricsInstallPromptVisible
    onActivated: mini.widget.toggleMiniShortcutHelp()
  }

  Column {
    id: barContextMenu
    width: parent.width
    visible: mini.usesContextMenu
    spacing: Style.space(2)
    Button {
      width: parent.width
      leftAlign: true
      text: "Stop playback on this computer"
      iconText: "󰓛"
      foreground: mini.widget.foreground
      visible: mini.widget.spotify && mini.widget.spotify.daemon.running
      enabled: mini.widget.spotify && !mini.widget.spotify.daemon.busy
      hasCursor: mini.widget.miniCursorOn("stop")
      onClicked: mini.widget.activateMiniAction("stop")
      onHovered: function(on) { if (on) mini.widget.setMiniCursor("stop") }
    }
    Button {
      width: parent.width
      leftAlign: true
      text: "Open full player"
      iconText: "󰏋"
      foreground: mini.widget.foreground
      hasCursor: mini.widget.miniCursorOn("open")
      onClicked: mini.widget.openFullPanel()
      onHovered: function(on) { if (on) mini.widget.setMiniCursor("open") }
    }
  }

  Column {
    id: contentColumn
    width: parent.width
    visible: !mini.widget.miniShortcutHelpVisible && !mini.widget.contextMenuVisible
    spacing: Style.space(10)

  Column {
    width: parent.width
    spacing: Style.space(8)
    visible: !mini.widget.lyricsInstallPromptVisible
      && mini.widget.spotify && !mini.widget.spotify.accountConnected

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: mini.widget.spotify ? mini.widget.spotify.loginProgress : "Spotify is unavailable"
      color: mini.widget.foreground
      font.family: mini.widget.bar ? mini.widget.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
      wrapMode: Text.WordWrap
    }

    Text {
      width: parent.width
      text: "Connect your Spotify account from here. Playback on this computer can finish in the background."
      color: mini.widget.muted
      font.family: mini.widget.bar ? mini.widget.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      width: parent.width
      visible: mini.widget.spotify && (mini.widget.spotify.lastError !== ""
        || mini.widget.spotify.auth.lastError !== ""
        || mini.widget.spotify.daemon.lastError !== "")
      textFormat: Text.PlainText
      text: mini.widget.spotify ? (mini.widget.spotify.lastError
        || mini.widget.spotify.auth.lastError
        || mini.widget.spotify.daemon.lastError) : ""
      color: Commons.Color.urgent
      font.family: mini.widget.bar ? mini.widget.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Row {
      width: parent.width
      spacing: Style.space(6)

      Button {
        text: mini.widget.spotify && mini.widget.spotify.loginBusy
          ? "Working…" : "Set up and continue"
        iconText: "󰍂"
        foreground: mini.widget.foreground
        hasCursor: mini.widget.miniCursorOn("setup")
        enabled: mini.widget.spotify && !mini.widget.spotify.loginBusy
        onClicked: if (mini.widget.spotify) mini.widget.spotify.login()
        onHovered: function(on) { if (on) mini.widget.setMiniCursor("setup") }
      }

      Button {
        text: "Cancel"
        foreground: mini.widget.foreground
        visible: mini.widget.spotify && mini.widget.spotify.loginBusy
        hasCursor: mini.widget.miniCursorOn("setup-cancel")
        onClicked: if (mini.widget.spotify) mini.widget.spotify.cancelLogin()
        onHovered: function(on) { if (on) mini.widget.setMiniCursor("setup-cancel") }
      }
    }
  }

  Item {
    id: miniNowPlaying
    width: parent.width
    implicitHeight: Math.max(miniArtworkSurface.height,
      miniNowPlayingMetadata.implicitHeight)
    height: implicitHeight
    readonly property real metadataSpacing: Style.space(12)
    readonly property bool artworkVisible: !mini.widget.spotify
      || mini.widget.spotify.artworkEnabled
    visible: !mini.widget.lyricsInstallPromptVisible
      && (!mini.widget.spotify || mini.widget.spotify.accountConnected)

    Item {
      id: miniArtworkSurface
      width: miniNowPlaying.artworkVisible ? Style.space(78) : 0
      height: width
      visible: miniNowPlaying.artworkVisible
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter

      BorderSurface {
        id: rectangleArtworkSurface
        anchors.fill: parent
        visible: !mini.widget.vinylRecordEnabled
        radius: Style.cornerRadius
        color: Style.normalFillFor(mini.widget.foreground, Commons.Color.accent)
        borderSpec: Border.controlSpec("normal", mini.widget.foreground, Commons.Color.accent)

        RetryImage {
          id: popupArtwork
          anchors.fill: parent
          anchors.margins: Style.space(3)
          requestedSource: !mini.widget.vinylRecordEnabled && mini.widget.popupOpen && mini.widget.spotify && mini.widget.spotify.artworkEnabled
            ? Api.idleMediaText(mini.widget.spotify.artUrl, mini.widget.spotify.lastPlayedItem, "imageUrl", "") : ""
          sourceSize.width: 156
          sourceSize.height: 156
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          cache: true
          visible: status === Image.Ready
        }

        Text {
          anchors.centerIn: parent
          visible: popupArtwork.status !== Image.Ready
          text: ""
          color: mini.widget.foreground
          font.family: mini.widget.bar ? mini.widget.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.displayLarge
        }
      }

      Loader {
        anchors.fill: parent
        active: mini.widget.vinylRecordEnabled
        sourceComponent: Component {
            Rectangle {
              id: recordArtworkSurface
              anchors.fill: parent
              radius: width / 2
              color: Style.normalFillFor(mini.widget.foreground, Commons.Color.accent)
              border.width: 1
              border.color: mini.widget.foreground
  
              Rectangle {
                id: popupRecordMask
                anchors.fill: parent
                anchors.margins: Style.space(3)
                radius: width / 2
                color: "white"
                visible: false
                layer.enabled: true
              }

              Rectangle {
                id: popupRecord
                anchors.fill: parent
                anchors.margins: Style.space(3)
                radius: width / 2
                color: Style.normalFillFor(mini.widget.foreground, Commons.Color.accent)
    
                RotationAnimation on rotation {
                  from: 0
                  to: 360
                  duration: 7000
                  loops: Animation.Infinite
                  running: mini.widget.vinylRecordEnabled && mini.widget.popupOpen
                    && mini.widget.spotify && mini.widget.spotify.artworkEnabled && mini.widget.spotify.playing
                }

                RetryImage {
                  id: popupRecordArtwork
                  anchors.fill: parent
                  requestedSource: mini.widget.vinylRecordEnabled && mini.widget.popupOpen && mini.widget.spotify && mini.widget.spotify.artworkEnabled
                    ? Api.idleMediaText(mini.widget.spotify.artUrl, mini.widget.spotify.lastPlayedItem, "imageUrl", "") : ""
                  sourceSize.width: 156
                  sourceSize.height: 156
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                  visible: false
                }

                MultiEffect {
                  anchors.fill: parent
                  source: popupRecordArtwork
                  maskEnabled: true
                  maskSource: popupRecordMask
                  maskThresholdMin: 0.5
                  maskSpreadAtMin: 1
                  visible: popupRecordArtwork.status === Image.Ready
                }

                Rectangle {
                  anchors.centerIn: parent
                  width: Math.max(Style.space(8), parent.width * 0.16)
                  height: width
                  radius: width / 2
                  color: Commons.Color.background
                  border.width: 1
                  border.color: Qt.rgba(0, 0, 0, 0.35)
                  visible: popupRecordArtwork.status === Image.Ready
                }
              }

              Text {
                anchors.centerIn: parent
                visible: popupRecordArtwork.status !== Image.Ready
                text: ""
                color: mini.widget.foreground
                font.family: mini.widget.bar ? mini.widget.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.displayLarge
              }
            }
        }
      }
    }

    Column {
      id: miniNowPlayingMetadata
      anchors.left: miniArtworkSurface.right
      anchors.leftMargin: miniArtworkSurface.visible
        ? miniNowPlaying.metadataSpacing : 0
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Row {
        width: parent.width
        spacing: Style.space(3)

        Text {
          width: Math.max(20, parent.width
            - (barCurrentTrackLikeButton.visible
              ? barCurrentTrackLikeButton.width + parent.spacing : 0))
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Api.idleMediaText(mini.widget.spotify ? mini.widget.spotify.title : "",
            mini.widget.spotify ? mini.widget.spotify.lastPlayedItem : null, "name",
            "Nothing playing")
          color: mini.widget.spotify && mini.widget.spotify.title
            ? mini.widget.foreground : mini.widget.muted
          font.family: mini.widget.bar ? mini.widget.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }

        Button {
          id: barCurrentTrackLikeButton
          objectName: "bar-current-track-like"
          visible: mini.widget.spotify && !!mini.widget.spotify.currentTrackItem
          anchors.verticalCenter: parent.verticalCenter
          iconText: mini.widget.spotify && mini.widget.spotify.currentTrackSaved
            ? "󰋑" : "󰋕"
          iconSize: Style.font.body
          foreground: mini.widget.spotify && mini.widget.spotify.currentTrackSaved
            ? Commons.Color.accent : mini.widget.foreground
          hasCursor: mini.widget.miniCursorOn("like")
          enabled: mini.widget.spotify && mini.widget.spotify.currentTrackSaveAvailable
          horizontalPadding: Style.space(4)
          verticalPadding: Style.space(2)
          tooltipText: mini.widget.spotify && mini.widget.spotify.currentTrackSaveChecking
            ? "Checking liked status…"
            : (mini.widget.spotify && mini.widget.spotify.currentTrackSaveBusy
              ? "Updating liked status…"
              : (mini.widget.spotify && mini.widget.spotify.currentTrackSaved
                ? "Remove like" : "Like this song"))
          onClicked: if (mini.widget.spotify)
            mini.widget.spotify.toggleCurrentTrackSaved()
          onHovered: function(on) {
            if (on) mini.widget.setMiniCursor("like")
          }
        }
      }

      CursorSurface {
        id: miniArtistCursor
        z: 2
        clip: false
        width: parent.width
        height: miniArtistLinks.implicitHeight + Style.space(4)
        visible: miniArtistLinks.fallbackText !== ""
          || miniArtistLinks.artists.length > 0
        enabled: mini.widget.spotify && mini.widget.spotify.currentArtistContextAvailable
        hasCursor: mini.widget.miniCursorOn("artist") || miniArtistHover.hovered
        foreground: mini.widget.foreground

        ArtistLinks {
          id: miniArtistLinks
          anchors.fill: parent
          anchors.leftMargin: Style.space(3)
          anchors.rightMargin: Style.space(3) + miniArtistHint.reservedRight
          artists: mini.widget.spotify ? mini.widget.spotify.currentArtists : []
          fallbackText: Api.idleMediaText(
            mini.widget.spotify ? mini.widget.spotify.artist : "",
            mini.widget.spotify ? mini.widget.spotify.lastPlayedItem : null, "subtitle", "")
          fallbackClickable: fallbackText !== "" && artists.length === 0
            && mini.widget.spotify && mini.widget.spotify.currentArtistContextAvailable
          color: mini.widget.spotify && mini.widget.spotify.artist !== ""
            && mini.widget.spotify.currentArtistContextAvailable
            ? mini.widget.foreground : mini.widget.muted
          accent: Commons.Color.accent
          font.family: mini.widget.bar ? mini.widget.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          onArtistRequested: function(item) { mini.widget.openArtist(item) }
          onFallbackRequested: mini.widget.openCurrentArtist()
        }

        HoverHandler {
          id: miniArtistHover
          onHoveredChanged: if (hovered) mini.widget.setMiniCursor("artist")
        }
        PanelToolTip {
          visible: miniArtistHover.hovered
          text: "Open artist · Ctrl+Shift+A"
        }
        KeyHint {
          id: miniArtistHint
          placement: "inset"
          sequences: ["Ctrl+Shift+A"]
        }
      }

      CursorSurface {
        id: miniAlbumCursor
        z: 1
        clip: false
        width: parent.width
        height: miniAlbumLinks.implicitHeight
        visible: miniAlbumLinks.fallbackText !== ""
        enabled: mini.widget.spotify && mini.widget.spotify.currentAlbumContextAvailable
        hasCursor: mini.widget.miniCursorOn("album") || miniAlbumHover.hovered
        foreground: mini.widget.foreground

        ArtistLinks {
          id: miniAlbumLinks
          anchors.fill: parent
          anchors.leftMargin: Style.space(3)
          anchors.rightMargin: Style.space(3) + miniAlbumHint.reservedRight
          artists: []
          fallbackText: Api.idleMediaText(
            mini.widget.spotify ? mini.widget.spotify.album : "",
            mini.widget.spotify ? mini.widget.spotify.lastPlayedItem : null, "album", "")
          fallbackClickable: mini.widget.spotify
            && mini.widget.spotify.currentAlbumContextAvailable
          color: mini.widget.spotify && mini.widget.spotify.currentAlbumContextAvailable
            ? mini.widget.muted : mini.widget.muted
          accent: Commons.Color.accent
          font.family: mini.widget.bar ? mini.widget.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          onFallbackRequested: mini.widget.openCurrentAlbum()
        }

        HoverHandler {
          id: miniAlbumHover
          onHoveredChanged: if (hovered) mini.widget.setMiniCursor("album")
        }
        PanelToolTip {
          visible: miniAlbumHover.hovered
          text: "Open album · Ctrl+Shift+B"
        }
        KeyHint {
          id: miniAlbumHint
          placement: "inset"
          sequences: ["Ctrl+Shift+B"]
        }
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(3)
    visible: !mini.widget.lyricsInstallPromptVisible
      && (!mini.widget.spotify || mini.widget.spotify.accountConnected)
      && mini.widget.spotify && mini.widget.spotify.lengthSeconds > 0

    CursorSurface {
      id: miniSeekCursor
      width: parent.width
      height: miniSeekSlider.implicitHeight + Style.space(2)
      hasCursor: mini.widget.miniCursorOn("seek")
      foreground: mini.widget.foreground

      PlaybackSlider {
        id: miniSeekSlider
        anchors.fill: parent
        anchors.leftMargin: Style.space(3)
        anchors.rightMargin: Style.space(3)
        bar: mini.widget.bar
        minimum: 0
        maximum: Math.max(1, mini.widget.spotify ? mini.widget.spotify.lengthSeconds : 1)
        sourceValue: mini.widget.spotify ? mini.widget.spotify.positionSeconds : 0
        sourcePending: mini.widget.spotify && mini.widget.spotify.pendingRemoteSeek !== null
        acknowledgeTolerance: 2
        contextKey: mini.widget.spotify
          ? mini.widget.spotify.currentUri + "|" + mini.widget.spotify.playbackDeviceName : ""
        step: 5
        onCommitted: function(value) {
          if (mini.widget.spotify) mini.widget.spotify.seekSeconds(value)
        }
      }

      HoverHandler {
        onHoveredChanged: if (hovered) mini.widget.setMiniCursor("seek")
      }
      KeyHint {
        placement: "above"
        sequences: ["Shift+Left", "Shift+Right"]
        active: mini.widget.shortcutHintsActive && mini.widget.spotify
          && mini.widget.spotify.playbackControllable
      }
    }

    Row {
      width: parent.width

      Text {
        id: positionTime
        textFormat: Text.PlainText
        text: Api.millisecondsToClock((mini.widget.spotify ? mini.widget.spotify.positionSeconds : 0) * 1000)
        color: mini.widget.muted
        font.family: mini.widget.bar ? mini.widget.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }

      Item { width: Math.max(0, parent.width - positionTime.implicitWidth - endTime.implicitWidth); height: 1 }

      Text {
        id: endTime
        textFormat: Text.PlainText
        text: Api.millisecondsToClock((mini.widget.spotify ? mini.widget.spotify.lengthSeconds : 0) * 1000)
        color: mini.widget.muted
        font.family: mini.widget.bar ? mini.widget.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(5)
    visible: !mini.widget.lyricsInstallPromptVisible
      && (!mini.widget.spotify || mini.widget.spotify.accountConnected)

    TransportButton {
      glyphText: "󰒟"
      foreground: mini.widget.foreground
      indicator: mini.widget.spotify && mini.widget.spotify.shuffle
      hasCursor: mini.widget.miniCursorOn("shuffle")
      tooltipText: "Shuffle · Ctrl+S"
      enabled: mini.widget.spotify && mini.widget.spotify.playbackControllable
      onClicked: if (mini.widget.spotify) mini.widget.spotify.setShuffle(!mini.widget.spotify.shuffle)
      onHovered: function(on) { if (on) mini.widget.setMiniCursor("shuffle") }
      KeyHint { sequences: ["Ctrl+S"] }
    }

    TransportButton {
      glyphText: "󰒮"
      foreground: mini.widget.foreground
      hasCursor: mini.widget.miniCursorOn("previous")
      tooltipText: "Previous · Ctrl+Left"
      enabled: mini.widget.spotify && mini.widget.spotify.playbackControllable
      onClicked: if (mini.widget.spotify) mini.widget.spotify.previous()
      onHovered: function(on) { if (on) mini.widget.setMiniCursor("previous") }
      KeyHint { sequences: ["Ctrl+Left"] }
    }

    TransportButton {
      glyphText: mini.widget.spotify && mini.widget.spotify.playing ? "󰏤" : "󰐊"
      glyphSize: Style.font.iconLarge
      controlSize: Style.space(36)
      anchors.verticalCenter: parent.verticalCenter
      foreground: mini.widget.foreground
      bordered: true
      hasCursor: mini.widget.miniCursorOn("play")
      tooltipText: (mini.widget.spotify && mini.widget.spotify.playing ? "Pause"
        : (mini.widget.spotify && mini.widget.spotify.canResumeLastPlayed
          ? "Resume last played" : "Play")) + " · Space"
      enabled: mini.widget.spotify && mini.widget.spotify.playbackStartable
      onClicked: if (mini.widget.spotify) mini.widget.spotify.togglePlayback()
      onHovered: function(on) { if (on) mini.widget.setMiniCursor("play") }
      KeyHint { sequences: ["Space"] }
    }

    TransportButton {
      glyphText: "󰒭"
      foreground: mini.widget.foreground
      hasCursor: mini.widget.miniCursorOn("next")
      tooltipText: "Next · Ctrl+Right"
      enabled: mini.widget.spotify && mini.widget.spotify.playbackControllable
      onClicked: if (mini.widget.spotify) mini.widget.spotify.next()
      onHovered: function(on) { if (on) mini.widget.setMiniCursor("next") }
      KeyHint { sequences: ["Ctrl+Right"] }
    }

    TransportButton {
      glyphText: mini.widget.spotify && mini.widget.spotify.repeatMode === "track" ? "󰑘" : "󰑖"
      foreground: mini.widget.foreground
      indicator: mini.widget.spotify && mini.widget.spotify.repeatMode !== "off"
      hasCursor: mini.widget.miniCursorOn("repeat")
      tooltipText: "Repeat: " + Api.repeatModeLabel(mini.widget.spotify
        ? mini.widget.spotify.repeatMode : "off") + " · Ctrl+R"
      enabled: mini.widget.spotify && mini.widget.spotify.playbackControllable
      onClicked: if (mini.widget.spotify) mini.widget.spotify.cycleRepeat()
      onHovered: function(on) { if (on) mini.widget.setMiniCursor("repeat") }
      KeyHint { sequences: ["Ctrl+R"] }
    }

    TransportButton {
      glyphText: "󰎈"
      foreground: mini.widget.foreground
      hasCursor: mini.widget.miniCursorOn("lyrics")
      tooltipText: "Open lyrics in Omasing · Ctrl+Shift+L"
      enabled: mini.widget.spotify && mini.widget.spotify.lyricsAvailable
      onClicked: mini.widget.openLyrics()
      onHovered: function(on) { if (on) mini.widget.setMiniCursor("lyrics") }
      KeyHint { sequences: ["Ctrl+Shift+L"] }
    }
  }

  CursorSurface {
    id: miniVolumeCursor
    width: parent.width
    height: miniVolumeRow.implicitHeight + Style.space(2)
    visible: !mini.widget.lyricsInstallPromptVisible
      && (!mini.widget.spotify || mini.widget.spotify.accountConnected)
      && mini.widget.spotify && mini.widget.spotify.hasPlayer
    hasCursor: mini.widget.miniCursorOn("volume")
    foreground: mini.widget.foreground

    Row {
      id: miniVolumeRow
      anchors.fill: parent
      anchors.leftMargin: Style.space(3)
      anchors.rightMargin: Style.space(3)
      spacing: Style.space(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: mini.widget.spotify && mini.widget.spotify.volume <= 0.001 ? "󰝟" : "󰕾"
        color: mini.widget.spotify && mini.widget.spotify.volume <= 0.001
          ? mini.widget.muted : mini.widget.foreground
        font.family: mini.widget.bar ? mini.widget.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.icon
      }

      PlaybackSlider {
        width: parent.width - Style.space(34)
        anchors.verticalCenter: parent.verticalCenter
        bar: mini.widget.bar
        minimum: 0
        maximum: 1
        step: 0.05
        sourceValue: mini.widget.spotify ? mini.widget.spotify.volume : 0
        sourcePending: mini.widget.spotify && mini.widget.spotify.volumePending
        contextKey: mini.widget.spotify ? mini.widget.spotify.playbackDeviceName : ""
        enabled: mini.widget.spotify && mini.widget.spotify.volumeSupported
        liveCommit: true
        onCommitted: function(value, live) {
          mini.widget.setVolumeValue(value, live)
        }
      }
    }

    HoverHandler {
      onHoveredChanged: if (hovered) mini.widget.setMiniCursor("volume")
    }
    KeyHint {
      placement: "above"
      sequences: ["M", "Ctrl+Up", "Ctrl+Down"]
      active: mini.widget.shortcutHintsActive && mini.widget.spotify
        && mini.widget.spotify.volumeSupported
    }
  }

  PanelSeparator {
    foreground: mini.widget.foreground
    visible: !mini.widget.lyricsInstallPromptVisible
  }

  Row {
    width: parent.width
    spacing: Style.space(6)
    visible: !mini.widget.lyricsInstallPromptVisible

    Text {
      width: parent.width - openButton.width - Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: !mini.widget.spotify ? "Spotify is unavailable"
        : (mini.widget.spotify.lastError !== "" ? mini.widget.spotify.lastError
        : (mini.widget.spotify.statusMessage !== "" ? mini.widget.spotify.statusMessage
        : (!mini.widget.spotify.accountConnected ? "Connect Spotify to start"
        : (!mini.widget.spotify.fullyConnected
          ? (mini.widget.spotify.loginBusy ? mini.widget.spotify.loginProgress
            : "Account connected · finish playback in Settings")
        : (mini.widget.spotify.useRemotePlayback
          ? (mini.widget.spotify.playing ? "Playing on " : "Connected to ")
            + mini.widget.spotify.playbackDeviceName
          : (mini.widget.spotify.daemon.running ? "Playing on this computer"
            : "Ready when you press play"))))))
      textFormat: Text.PlainText
      color: mini.widget.spotify && mini.widget.spotify.lastError !== ""
        ? Commons.Color.urgent : mini.widget.muted
      font.family: mini.widget.bar ? mini.widget.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }

    Button {
      id: openButton
      text: "Open"
      iconText: "󰏋"
      foreground: mini.widget.foreground
      hasCursor: mini.widget.miniCursorOn("open")
      tooltipText: "Open full player · O"
      onClicked: mini.widget.openFullPanel()
      onHovered: function(on) { if (on) mini.widget.setMiniCursor("open") }
      KeyHint { sequences: ["O"] }
    }
  }

    LyricsInstallPrompt {
      width: parent.width
      visible: mini.widget.lyricsInstallPromptVisible
      service: mini.widget.spotify
      foreground: mini.widget.foreground
      muted: mini.widget.muted
      surfaceKey: mini.widget.lyricsRequestKey
      cancelHasCursor: mini.widget.miniCursorOn("prompt-cancel")
      confirmHasCursor: mini.widget.miniCursorOn("prompt-confirm")
      onCanceled: mini.widget.dismissLyricsInstallPrompt()
    }
  }

  Column {
    id: miniShortcutHelp
    width: parent.width
    visible: mini.widget.miniShortcutHelpVisible
    spacing: Style.space(7)

    Row {
      width: parent.width
      spacing: Style.space(6)

      Text {
        width: parent.width - miniShortcutHelpClose.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        text: "Keyboard shortcuts"
        color: mini.widget.foreground
        font.family: mini.widget.bar ? mini.widget.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Button {
        id: miniShortcutHelpClose
        iconText: "󰅖"
        foreground: mini.widget.foreground
        focusable: true
        hasCursor: mini.widget.miniCursorOn("help-close")
        tooltipText: "Close shortcut reference · Ctrl+/ or Esc"
        onClicked: mini.widget.toggleMiniShortcutHelp()
        onHovered: function(on) { if (on) mini.widget.setMiniCursor("help-close") }
        KeyHint {
          sequences: ["Esc", "Ctrl+/"]
          active: mini.widget.shortcutHintsInPopup
        }
      }
    }

    PanelSeparator { foreground: mini.widget.foreground }

    Repeater {
      model: mini.widget.miniShortcutRows

      delegate: Row {
        id: shortcutRow
        required property var modelData
        width: miniShortcutHelp.width
        spacing: Style.space(8)

        Text {
          width: Style.space(128)
          textFormat: Text.PlainText
          text: shortcutRow.modelData.keys
          color: mini.widget.foreground
          font.family: mini.widget.bar ? mini.widget.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width - Style.space(128) - parent.spacing
          textFormat: Text.PlainText
          text: shortcutRow.modelData.action
          color: mini.widget.muted
          font.family: mini.widget.bar ? mini.widget.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
