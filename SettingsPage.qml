pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui

import "Api.js" as Api

Item {
  id: page

  property var panel: null

  readonly property var service: panel ? panel.service : null
  readonly property int toggleColumns: width >= Style.space(640) ? 2 : 1
  readonly property real toggleWidth: Math.floor((settingsContent.width
    - Style.space(6) * (toggleColumns - 1)) / toggleColumns)
  readonly property bool barTextCanScroll:
    Api.canScrollBarText(panel.draftShowTitle, panel.draftShowArtist)

  function cursorTargets(item, found) {
    var targets = found || []
    if (!item || item.visible === false) return targets
    if (item.cursorId) {
      if (item.enabled !== false) targets.push(item)
      return targets
    }
    var kids = item.children
    if (!kids) return targets
    for (var i = 0; i < kids.length; i++) cursorTargets(kids[i], targets)
    return targets
  }

  function cursorActions() {
    return cursorTargets(settingsContent).map(function(item) { return item.cursorId })
  }

  function targetFor(action) {
    var targets = cursorTargets(settingsContent)
    for (var i = 0; i < targets.length; i++)
      if (targets[i].cursorId === action) return targets[i]
    return null
  }

  function activateCursorAction(action) {
    var target = targetFor(action)
    if (!target) return false
    if (target.activate) target.activate()
    return true
  }

  function adjustCursorAction(action, delta) {
    var target = targetFor(action)
    if (!target || !target.adjust) return false
    target.adjust(delta)
    return true
  }

  function saveToggle(name) {
    panel[name] = !panel[name]
    panel.enforceScrollAvailability()
    panel.persistDraftSettings()
  }

  Connections {
    target: page.panel
    function onPanelCursorActionChanged() {
      if (!page.panel.keyboardCursorShown || page.panel.panelCursorRegion !== "page") return
      var target = page.targetFor(page.panel.panelCursorAction)
      var flick = setupScroll.contentItem
      if (!target || !flick) return
      var top = target.mapToItem(settingsContent, 0, 0).y
      if (top < flick.contentY) flick.contentY = Math.max(0, top - Style.space(24))
      else if (top + target.height > flick.contentY + flick.height)
        flick.contentY = top + target.height - flick.height + Style.space(8)
    }
  }

  component SettingNote: Text {
    width: parent ? parent.width : implicitWidth
    color: page.panel.muted
    font.family: page.panel.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  component SectionTitle: PanelSectionHeader {
    color: page.panel.muted
    fontFamily: page.panel.fontFamily
    fontSize: Style.font.bodySmall
  }

  component Section: Column {
    width: parent ? parent.width : implicitWidth
    spacing: Style.space(7)
  }

  ScrollView {
    id: setupScroll
    anchors.fill: parent
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    Column {
      id: settingsContent
      width: setupScroll.availableWidth - Style.space(12)
      spacing: Style.space(16)

      Section {
        SectionTitle { text: "Spotify account" }

        BorderSurface {
          width: parent.width
          implicitHeight: accountStatus.implicitHeight + Style.space(14)
          color: Style.normalFillFor(page.panel.foreground, page.panel.accent)
          borderSpec: Border.controlSpec("normal", page.panel.foreground, page.panel.accent)
          radius: Style.cornerRadius

          Row {
            id: accountStatus
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(9)
            anchors.rightMargin: Style.space(9)
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: page.panel.fullyConnected ? "󰄬" : "󰋼"
              color: page.panel.fullyConnected ? page.panel.accent : page.panel.foreground
              font.family: page.panel.fontFamily
              font.pixelSize: Style.font.icon
            }

            Text {
              width: Math.max(40, parent.width - Style.space(24))
              anchors.verticalCenter: parent.verticalCenter
              text: !page.service ? "Spotify is unavailable"
                : (page.service.loginBusy ? page.service.loginProgress + "…"
                : (page.panel.fullyConnected ? "Connected and ready to play"
                : (page.service.auth.loggedIn
                  ? "Spotify is connected · playback needs approval"
                  : (page.service.daemon.credentialsAvailable
                    ? "Playback is ready · Spotify needs approval"
                    : "Not connected"))))
              textFormat: Text.PlainText
              color: page.panel.foreground
              font.family: page.panel.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          SettingButton {
            panel: page.panel
            cursorId: "set-login"
            text: page.panel.connectionButtonText()
            iconText: "󰍂"
            visible: !page.panel.fullyConnected
            enabled: page.service && !page.service.loginBusy
            onClicked: if (page.service) page.service.login()
          }
          SettingButton {
            panel: page.panel
            cursorId: "set-cancel-login"
            text: "Cancel"
            visible: page.service && page.service.loginBusy
            onClicked: if (page.service) page.service.cancelLogin()
          }
          SettingButton {
            panel: page.panel
            cursorId: "set-reconnect"
            text: "Reconnect Spotify"
            iconText: "󰑐"
            visible: page.service && page.service.auth.loggedIn
            enabled: page.service && !page.service.loginBusy
            tooltipText: "Reconnect if library or playlist features are not working"
            onClicked: page.service.reconnectAccount()
          }
          SettingButton {
            panel: page.panel
            cursorId: "set-logout"
            text: "Log out"
            iconText: "󰍃"
            visible: page.service && (page.service.auth.loggedIn
              || page.service.daemon.credentialsAvailable)
            enabled: page.service && !page.service.loginBusy
              && !page.service.daemon.busy
            onClicked: page.panel.askToConfirm(
              "Log out of Spotify on this computer? You will need to sign in again to listen here.",
              "Log out", function() { page.service.logout() })
          }
        }

        SettingNote {
          text: page.panel.connectionErrorText()
          textFormat: Text.PlainText
          color: Commons.Color.urgent
          visible: text !== ""
        }
      }

      Section {
        visible: page.service && !page.service.usesSoloist && !page.service.daemon.playbackReady

        SectionTitle { text: "Playback on this computer" }

        SettingNote {
          text: "A lightweight background player starts only when you need it, works with Omarchy's media controls, and appears in Spotify Connect as this computer. " + page.panel.playbackStatusText()
        }

        SettingButton {
          panel: page.panel
          cursorId: "set-playback-setup"
          text: page.service && page.service.daemon.setupBusy
            ? "Setting up playback…" : "Set up playback"
          iconText: "󰓃"
          enabled: page.service && !page.service.loginBusy
          onClicked: page.service.login()
        }
      }

      SoloistSetup {
        width: parent.width
        panel: page.panel
        visible: page.service && page.service.usesSoloist
      }

      Section {
        SectionTitle { text: "Spotify Connect" }

        Row {
          width: parent.width
          spacing: Style.space(8)

          SettingField {
            panel: page.panel
            cursorId: "set-device-name"
            width: Math.round(parent.width * 0.66)
            label: "This computer appears as"
            placeholderText: "OmaSpotify"
            text: page.panel.draftDeviceName
            onTextEdited: page.panel.draftDeviceName = text
            onEditingFinished: page.panel.persistDraftSettings()
          }

          SettingField {
            panel: page.panel
            cursorId: "set-idle"
            width: Math.max(Style.space(120), parent.width - Math.round(parent.width * 0.66)
              - parent.spacing)
            label: "Stop when idle, in minutes"
            placeholderText: "15"
            text: page.panel.draftIdleMinutes
            validator: IntValidator { bottom: 0; top: 1440 }
            onTextEdited: page.panel.draftIdleMinutes = text
            onEditingFinished: page.panel.persistDraftSettings()
          }
        }

        SettingNote {
          text: page.service && page.service.usesSoloist
            ? "The device name updates the next time local playback starts. This computer stays visible while the player is open, then sleeps at the idle timeout. Use 0 to keep it available."
            : "The device name and audio quality update the next time local playback starts. This computer stays visible while the player is open, then sleeps at the idle timeout. Use 0 to keep it available."
        }

        SettingField {
          id: clientIdField
          panel: page.panel
          cursorId: "set-client-id"
          width: parent.width
          label: "Spotify developer app"
          placeholderText: "Your app's 32-character client ID"
          text: page.panel.draftClientId
          onTextEdited: page.panel.draftClientId = text
        }

        SettingNote {
          text: page.panel.draftClientId.trim()
                && !/^[0-9a-f]{32}$/i.test(page.panel.draftClientId.trim())
            ? "A client ID has exactly 32 hexadecimal characters."
            : "Register http://127.0.0.1:8989/login in your app's Redirect URIs. Changing the client ID requires signing in again. No client secret is needed."
        }

        SettingButton {
          panel: page.panel
          cursorId: "set-apply-client"
          text: "Apply app"
          enabled: page.service
            && /^[0-9a-f]{32}$/i.test(page.panel.draftClientId.trim())
            && page.panel.draftClientId.trim().toLowerCase()
              !== String(page.service.settings.clientId || "")
          onClicked: page.service.persistSettings({
            clientId: page.panel.draftClientId.trim()
          })
        }
      }

      Section {
        SectionTitle { text: "Player and artwork" }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          SettingToggle {
            panel: page.panel
            cursorId: "set-mini-player"
            width: page.toggleWidth
            label: "Mini-player first"
            description: "The bar icon opens the mini-player, not the full player."
            checked: page.panel.draftShowMiniPlayer
            onClicked: page.saveToggle("draftShowMiniPlayer")
          }
          SettingToggle {
            panel: page.panel
            cursorId: "set-artwork"
            width: page.toggleWidth
            label: "Artwork"
            description: "Turn off to stop downloading covers and go text-only."
            checked: page.panel.draftShowArtwork
            onClicked: page.saveToggle("draftShowArtwork")
          }
          SettingToggle {
            panel: page.panel
            cursorId: "set-vinyl"
            width: page.toggleWidth
            label: "Spinning vinyl"
            description: "Mini-player artwork spins like a record while music plays."
            checked: page.panel.draftShowVinylRecord
            onClicked: page.saveToggle("draftShowVinylRecord")
          }
          SettingToggle {
            panel: page.panel
            cursorId: "set-lyrics"
            width: page.toggleWidth
            label: "Lyrics button"
            description: "Opens the Omasing lyrics window. Hide it if you do not use Omasing."
            checked: page.panel.draftShowLyrics
            onClicked: page.saveToggle("draftShowLyrics")
          }
        }
      }

      Section {
        SectionTitle { text: "Keyboard" }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          SettingButton {
            panel: page.panel
            cursorId: "set-shortcut-player"
            width: page.toggleWidth
            leftAlign: true
            text: "Super+Shift+M opens: " + page.panel.draftShortcutPlayer
            iconText: "󰌌"
            tooltipText: "Cycle between Omarchy's Music app, the full player, and the mini-player"
            onClicked: page.panel.cycleShortcutPlayer()
          }
          SettingToggle {
            panel: page.panel
            cursorId: "set-hints"
            width: page.toggleWidth
            label: "Shortcut hints"
            description: "After a shortcut or Tab, controls show the next key. Ctrl+H turns this off."
            checked: page.panel.draftShortcutHints
            onClicked: page.saveToggle("draftShortcutHints")
          }
        }
      }

      Section {
        SectionTitle { text: "Bar text" }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          SettingToggle {
            panel: page.panel
            cursorId: "set-bar-title"
            width: page.toggleWidth
            label: "Song title"
            description: "Show the title in the top bar."
            checked: page.panel.draftShowTitle
            onClicked: page.saveToggle("draftShowTitle")
          }
          SettingToggle {
            panel: page.panel
            cursorId: "set-bar-artist"
            width: page.toggleWidth
            label: "Artist name"
            description: "Show the artist in the top bar."
            checked: page.panel.draftShowArtist
            onClicked: page.saveToggle("draftShowArtist")
          }
          SettingToggle {
            panel: page.panel
            cursorId: "set-bar-paused"
            width: page.toggleWidth
            label: "While paused"
            description: "Keep the text visible while paused, rather than just the icon."
            checked: page.panel.draftShowPausedTrack
            onClicked: page.saveToggle("draftShowPausedTrack")
          }
          SettingToggle {
            panel: page.panel
            cursorId: "set-bar-scroll"
            width: page.toggleWidth
            label: "Scroll long text"
            description: page.panel.barTextWidthUnlimited
              ? "Unavailable while the width is unlimited, because the label always fits."
              : "Long labels scroll and fade at the edges only when they do not fit."
            checked: page.panel.draftScrollBarText
            enabled: page.barTextCanScroll && !page.panel.barTextWidthUnlimited
            opacity: enabled ? 1 : 0.5
            onClicked: if (enabled) page.saveToggle("draftScrollBarText")
          }
          SettingToggle {
            panel: page.panel
            cursorId: "set-bar-fixed"
            width: page.toggleWidth
            label: "Fixed width"
            description: page.panel.barTextWidthUnlimited
              ? "Unavailable while the width is unlimited."
              : "Keep the same width between songs, so the bar does not shift."
            checked: page.panel.draftFixedBarWidth
            enabled: page.barTextCanScroll && !page.panel.barTextWidthUnlimited
            opacity: enabled ? 1 : 0.5
            onClicked: if (enabled) page.saveToggle("draftFixedBarWidth")
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: page.barTextCanScroll && page.panel.draftScrollBarText

          Row {
            width: parent.width

            Text {
              id: scrollSpeedTitle
              text: "Scroll speed"
              color: page.panel.muted
              font.family: page.panel.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Item {
              width: Math.max(0, parent.width - scrollSpeedTitle.implicitWidth
                - scrollSpeedValue.implicitWidth)
              height: 1
            }
            Text {
              id: scrollSpeedValue
              text: page.panel.scrollSpeedLabel()
              color: page.panel.foreground
              font.family: page.panel.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }

          CursorSurface {
            id: scrollSpeedCursor
            readonly property string cursorId: "set-scroll-speed"
            function adjust(delta) {
              page.panel.draftScrollSpeed = Api.normalizedScrollSpeed(
                page.panel.draftScrollSpeed + delta * 0.25)
              page.panel.persistDraftSettings()
            }
            width: parent.width
            height: scrollSpeedSlider.implicitHeight
            hasCursor: page.panel.cursorShown("page", cursorId)
            foreground: page.panel.foreground

            HoverHandler {
              onHoveredChanged: if (hovered)
                page.panel.setPanelCursor("page", scrollSpeedCursor.cursorId)
            }

            PanelSlider {
              id: scrollSpeedSlider
              anchors.fill: parent
              bar: page.panel.panelBar
              minimum: 0.25
              maximum: 3
              step: 0.25
              tickCount: 12
              value: page.panel.draftScrollSpeed
              onMoved: function(value) {
                page.panel.draftScrollSpeed = Api.normalizedScrollSpeed(value)
              }
              onReleased: function(value) {
                page.panel.draftScrollSpeed = Api.normalizedScrollSpeed(value)
                page.panel.persistDraftSettings()
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: page.barTextCanScroll

          Row {
            width: parent.width

            Text {
              id: maxBarWidthTitle
              text: "Maximum width"
              color: page.panel.muted
              font.family: page.panel.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Item {
              width: Math.max(0, parent.width - maxBarWidthTitle.implicitWidth
                - maxBarWidthValue.implicitWidth)
              height: 1
            }
            Text {
              id: maxBarWidthValue
              text: page.panel.maxBarTextWidthLabel()
              color: page.panel.foreground
              font.family: page.panel.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }

          CursorSurface {
            id: maxWidthCursor
            readonly property string cursorId: "set-bar-width"
            function adjust(delta) {
              page.panel.setMaxBarTextWidthFromSlider(page.panel.maxBarTextWidthSliderValue()
                + delta * page.panel.barTextWidthSlider.step)
              page.panel.persistDraftSettings()
            }
            width: parent.width
            height: maxWidthSlider.implicitHeight
            hasCursor: page.panel.cursorShown("page", cursorId)
            foreground: page.panel.foreground

            HoverHandler {
              onHoveredChanged: if (hovered)
                page.panel.setPanelCursor("page", maxWidthCursor.cursorId)
            }

            PanelSlider {
              id: maxWidthSlider
              anchors.fill: parent
              bar: page.panel.panelBar
              minimum: page.panel.barTextWidthSlider.min
              maximum: page.panel.barTextWidthSlider.unlimited
              step: page.panel.barTextWidthSlider.step
              tickCount: page.panel.barTextWidthSlider.ticks
              value: page.panel.maxBarTextWidthSliderValue()
              onMoved: function(value) { page.panel.setMaxBarTextWidthFromSlider(value) }
              onReleased: function(value) {
                page.panel.setMaxBarTextWidthFromSlider(value)
                page.panel.persistDraftSettings()
              }
            }
          }

          SettingNote {
            visible: page.panel.barTextWidthUnlimited
            text: "Very long titles will take space from other bar widgets."
          }
        }
      }

      Section {
        SectionTitle { text: "Playback" }

        SettingNote {
          visible: page.service && page.service.usesSoloist
          text: "Spotify Soloist manages streaming quality and audio normalization."
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)
          visible: page.service && !page.service.usesSoloist

          SettingButton {
            panel: page.panel
            cursorId: "set-audio-quality"
            width: page.toggleWidth
            leftAlign: true
            text: "Audio quality: " + page.panel.audioQualityLabel()
            iconText: "󰎈"
            tooltipText: "Change streaming quality"
            onClicked: page.panel.cycleAudioQuality()
          }
          SettingToggle {
            panel: page.panel
            cursorId: "set-normalize"
            width: page.toggleWidth
            label: "Normalize volume"
            description: "Play quiet and loud tracks at a similar level."
            checked: page.panel.draftNormalizeVolume
            onClicked: page.panel.toggleNormalizeVolume()
          }
          SettingButton {
            panel: page.panel
            cursorId: "set-volume-level"
            width: page.toggleWidth
            leftAlign: true
            text: "Volume level: " + page.panel.volumeLevelLabel()
            iconText: "󰝝"
            enabled: page.panel.draftNormalizeVolume
            tooltipText: "How loud normalized playback aims to be"
            onClicked: page.panel.cycleVolumeLevel()
          }
        }
      }

      Item { width: 1; height: Style.space(4) }
    }
  }

  FastScrollHandler {
    parent: setupScroll.contentItem
    flickable: setupScroll.contentItem
  }
}
