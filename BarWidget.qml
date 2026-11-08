pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import qs.Ui

import "Api.js" as Api

BarWidget {
  id: root

  moduleName: "io.github.atlastimed.omaspotify"

  readonly property var spotify: bar && bar.shell
    ? bar.shell.serviceFor("io.github.atlastimed.omaspotify") : null
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color muted: Api.secondaryTextColor(Commons.Color.foreground,
    Commons.Color.background)
  readonly property string surfaceKey: "spotify-popup-" + String(root)
  readonly property string lyricsRequestKey: surfaceKey + "-lyrics"
  readonly property string barText: spotify
    ? Api.barTrackText(spotify.title, spotify.artist,
      spotify.showTrackTitle, spotify.showArtistName, spotify.playing,
      spotify.showPausedTrack) : ""
  readonly property bool miniPlayerEnabled:
    String(root.setting("showMiniPlayer", "On")) !== "Off"
  readonly property bool vinylRecordEnabled:
    String(root.setting("showVinylRecord", "Off")) === "On"
  readonly property bool iconOnly: !spotify || vertical || !spotify.hasMedia
    || barText === ""
  property bool popupOpen: false
  property bool contextMenuVisible: false
  property bool lyricsInstallPromptVisible: false
  property bool miniShortcutHelpVisible: false
  property bool popoutSwitchClosing: false
  property bool miniCursorActive: false
  // Hover moves the cursor without drawing it, so a highlight never lingers.
  property bool miniCursorFromPointer: false
  property string miniCursor: "play"
  property real volumeBeforeMute: 0.5
  property bool shortcutModeLatched: false
  property int heldModifierFlags: 0
  property bool pendingShortcutLatch: false
  readonly property bool shortcutHintsEnabled: spotify
    ? spotify.shortcutHintsEnabled
    : String(root.setting("shortcutHints", "On")) !== "Off"
  readonly property bool shortcutHintsActive: shortcutHintsEnabled
    && shortcutModeLatched && !miniShortcutHelpVisible
    && !lyricsInstallPromptVisible
  readonly property bool shortcutHintsInPopup: shortcutHintsEnabled
    && shortcutModeLatched
  readonly property bool hintCtrlHeld: (heldModifierFlags & Qt.ControlModifier) !== 0
  readonly property bool hintShiftHeld: (heldModifierFlags & Qt.ShiftModifier) !== 0
  readonly property bool hintAltHeld: (heldModifierFlags & Qt.AltModifier) !== 0

  readonly property bool opened: popupOpen
  readonly property var miniShortcutRows: spotify && spotify.showLyrics
    ? allMiniShortcutRows
    : allMiniShortcutRows.filter(function(row) { return row.keys !== "Ctrl+Shift+L" })
  readonly property var allMiniShortcutRows: [
    { keys: "Tab / arrows / HJKL", action: "Select a control" },
    { keys: "Enter", action: "Activate selected button" },
    { keys: "Left / Right", action: "Adjust selected slider" },
    { keys: "Space", action: "Play or pause" },
    { keys: "Ctrl+Left / Right", action: "Previous or next track" },
    { keys: "Shift+Left / Right", action: "Seek 10 seconds" },
    { keys: "Ctrl+Up / Down", action: "Change volume" },
    { keys: "M", action: "Mute or restore volume" },
    { keys: "Ctrl+S / Ctrl+R", action: "Shuffle / repeat" },
    { keys: "Ctrl+Shift+L", action: "Open lyrics" },
    { keys: "Ctrl+Shift+A", action: "Open the current artist" },
    { keys: "Ctrl+Shift+B", action: "Open the current album" },
    { keys: "O", action: "Open full player" },
    { keys: "Ctrl+H", action: "Hide visible shortcut hints" },
    { keys: "Ctrl+/", action: "Toggle this reference" },
    { keys: "Scroll the bar icon", action: "Previous or next track" },
    { keys: "Middle-click the bar icon", action: "Play or pause" },
    { keys: "Esc", action: "Close" }
  ]
  readonly property var miniKeyboardActions: {
    if (contextMenuVisible) return spotify && spotify.daemon.running ? ["stop", "open"] : ["open"]
    if (lyricsInstallPromptVisible) return ["prompt-cancel", "prompt-confirm"]
    if (miniShortcutHelpVisible) return ["help-close"]
    if (spotify && !spotify.accountConnected) {
      const setupActions = ["setup"]
      if (spotify.loginBusy) setupActions.push("setup-cancel")
      setupActions.push("open")
      return setupActions
    }
    var actions = []
    if (spotify && spotify.currentArtistContextAvailable) actions.push("artist")
    if (spotify && spotify.currentAlbumContextAvailable) actions.push("album")
    if (spotify && spotify.currentTrackSaveAvailable) actions.push("like")
    if (spotify && spotify.lengthSeconds > 0
        && spotify.playbackControllable) actions.push("seek")
    if (spotify && spotify.playbackControllable) {
      actions.push("shuffle", "previous", "play", "next", "repeat")
    } else if (spotify && spotify.playbackStartable) {
      actions.push("play")
    }
    if (spotify && spotify.lyricsAvailable) actions.push("lyrics")
    if (spotify && spotify.hasPlayer && spotify.volumeSupported)
      actions.push("volume")
    actions.push("open")
    return actions
  }

  function open() {
    popupOpen = true
  }
  function close() {
    miniShortcutHelpVisible = false
    contextMenuVisible = false
    clearShortcutMode()
    popupOpen = false
  }

  function applySequenceModifiers(sequence) {
    heldModifierFlags = shortcutModifiers.flagsForSequence(sequence)
  }

  function latchShortcutMode(sequence) {
    if (!shortcutHintsEnabled) return
    shortcutModeLatched = true
    if (sequence) applySequenceModifiers(sequence)
  }

  function clearShortcutMode() {
    shortcutModeLatched = false
    heldModifierFlags = 0
  }

  function disableShortcutHints() {
    clearShortcutMode()
    if (spotify) spotify.persistSettings({ shortcutHints: "Off" })
  }

  function noteHeldModifiers(event, pressed) {
    if (!event) return
    heldModifierFlags = shortcutModifiers.flagsAfterEvent(event.modifiers,
      pressed, heldModifierFlags, event.key)
  }





  function acceptMiniKey(event) {
    latchShortcutMode()
    if (event) heldModifierFlags = event.modifiers
    event.accepted = true
  }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }
  function toggle() {
    if (miniPlayerEnabled) popupOpen ? close() : open()
    else openFullPanel()
  }

  function shortcutPlayer() {
    return Api.normalizedShortcutPlayer(root.setting("shortcutPlayer",
      "Omarchy Music app"))
  }

  function toggleMiniPlayerShortcut() {
    if (!bar || typeof bar.isBarWidgetOpen !== "function"
        || typeof bar.hideBarWidget !== "function"
        || typeof bar.summonBarWidget !== "function") return "unavailable"
    if (bar.isBarWidgetOpen(moduleName))
      return bar.hideBarWidget(moduleName) ? "closed" : "unavailable"
    pendingShortcutLatch = true
    var host = bar.shell
    if (host && typeof host.isPluginOpen === "function"
        && host.isPluginOpen(moduleName) && typeof host.hide === "function") {
      host.hide(moduleName)
      Qt.callLater(function() {
        if (root.bar) root.bar.summonBarWidget(root.moduleName)
      })
      return "opened"
    }
    var opened = bar.summonBarWidget(moduleName)
    if (!opened) pendingShortcutLatch = false
    return opened ? "opened" : "unavailable"
  }

  function toggleFullPlayerShortcut() {
    var host = bar ? bar.shell : null
    if (!host || typeof host.isPluginOpen !== "function"
        || typeof host.hide !== "function"
        || typeof host.summon !== "function") return "unavailable"
    if (host.isPluginOpen(moduleName)) {
      host.hide(moduleName)
      return "closed"
    }
    if (bar && typeof bar.isBarWidgetOpen === "function"
        && bar.isBarWidgetOpen(moduleName)
        && typeof bar.hideBarWidget === "function") {
      bar.hideBarWidget(moduleName)
      Qt.callLater(function() {
        if (root.bar && root.bar.shell)
          root.bar.shell.summon(root.moduleName,
            JSON.stringify({ shortcutLatch: true }))
      })
      return "opened"
    }
    return host.summon(moduleName, JSON.stringify({ shortcutLatch: true }))
      ? "opened" : "unavailable"
  }

  function toggleConfiguredPlayerShortcut() {
    var target = shortcutPlayer()
    if (target === "Full player") return toggleFullPlayerShortcut()
    if (target === "Mini player") return toggleMiniPlayerShortcut()
    if (!bar || typeof bar.run !== "function") return "unavailable"
    bar.run("omarchy launch spotify")
    return "launched"
  }

  function openFullPanel(payload) {
    var next = payload && typeof payload === "object" ? Api.shallowCopy(payload) : ({})
    if (shortcutModeLatched) next.shortcutLatch = true
    close()
    if (!bar || !bar.shell) return
    var encoded = JSON.stringify(next)
    if (typeof bar.shell.hide === "function"
        && typeof bar.shell.summon === "function") {
      // Remap an existing full player onto the workspace containing this bar.
      // Splitting hide and summon across event-loop turns lets Wayland finish
      // unmapping the old surface before the shell opens it here.
      bar.shell.hide("io.github.atlastimed.omaspotify")
      Qt.callLater(function() {
        if (root.bar && root.bar.shell)
          root.bar.shell.summon("io.github.atlastimed.omaspotify", encoded)
      })
    } else if (payload && typeof bar.shell.summon === "function")
      bar.shell.summon("io.github.atlastimed.omaspotify", encoded)
    else bar.shell.toggle("io.github.atlastimed.omaspotify", encoded)
  }

  ShortcutModifiers {
    id: shortcutModifiers
  }

  function openCurrentArtist() {
    if (!spotify || !bar || !bar.shell
        || !spotify.currentArtistContextAvailable) return
    spotify.currentContext("artist", function(item) {
      root.openArtist(item)
    })
  }

  function openCurrentAlbum() {
    if (!spotify || !bar || !bar.shell
        || !spotify.currentAlbumContextAvailable) return
    spotify.currentContext("album", function(item) {
      if (item) root.openFullPanel({ tab: "detail", detailItem: item })
    })
  }

  function openArtist(item) {
    if (!item || !spotify) return
    if (item.id) {
      openFullPanel({ tab: "detail", detailItem: item })
      return
    }
    spotify.resolveArtist(item.name, function(resolved) {
      if (resolved) root.openFullPanel({ tab: "detail", detailItem: resolved })
    })
  }

  function openLyrics() {
    if (!spotify || !spotify.lyricsAvailable) return
    var result = spotify.requestLyrics(lyricsRequestKey)
    if (result !== "opening") {
      lyricsInstallPromptVisible = true
      popupOpen = true
    }
  }

  function dismissLyricsInstallPrompt() {
    if (spotify) spotify.cancelLyricsPlugin(lyricsRequestKey)
    lyricsInstallPromptVisible = false
  }

  function toggleMiniShortcutHelp() {
    if (lyricsInstallPromptVisible) return
    miniShortcutHelpVisible = !miniShortcutHelpVisible
    if (miniShortcutHelpVisible) setMiniCursor("help-close", true)
    else ensureMiniCursor()
  }

  function ensureMiniCursor() {
    var actions = miniKeyboardActions
    if (!actions.length) {
      miniCursorActive = false
      return
    }
    if (actions.indexOf(miniCursor) >= 0) return
    miniCursor = actions.indexOf("play") >= 0 ? "play" : actions[0]
  }

  function setMiniCursor(action, fromKeyboard) {
    if (miniKeyboardActions.indexOf(action) < 0) return
    miniCursor = action
    miniCursorActive = true
    miniCursorFromPointer = fromKeyboard !== true
  }

  function miniCursorOn(action) {
    return miniCursorActive && !miniCursorFromPointer && miniCursor === action
  }

  function moveMiniCursor(delta) {
    var actions = miniKeyboardActions
    if (!actions.length) return
    var index = actions.indexOf(miniCursor)
    if (index < 0) index = actions.indexOf("play")
    if (index < 0) index = 0
    index = (index + (delta < 0 ? -1 : 1) + actions.length) % actions.length
    miniCursor = actions[index]
    miniCursorActive = true
    miniCursorFromPointer = false
  }

  function seekBy(seconds) {
    if (!spotify || !spotify.playbackControllable) return
    spotify.seekSeconds(Api.seekPosition(spotify.positionSeconds, seconds,
      spotify.lengthSeconds))
  }

  function setVolumeValue(value, live) {
    if (!spotify || !spotify.volumeSupported) return false
    var next = Api.nextVolume(value, 0)
    if (Api.shouldRememberVolume(next)) volumeBeforeMute = next
    spotify.setVolume(next, live === true)
    return true
  }

  function adjustVolume(delta) {
    if (!spotify || !spotify.volumeSupported) return false
    return setVolumeValue(Api.nextVolume(spotify.volume, delta), false)
  }

  function toggleMute() {
    if (!spotify || !spotify.volumeSupported) return
    var current = Api.nextVolume(spotify.volume, 0)
    if (Api.shouldRememberVolume(current)) {
      volumeBeforeMute = current
      spotify.setVolume(0)
    } else spotify.setVolume(Api.unmuteVolume(volumeBeforeMute))
  }

  function activateMiniAction(action) {
    if (action === "help-close") toggleMiniShortcutHelp()
    else if (action === "prompt-cancel") dismissLyricsInstallPrompt()
    else if (action === "prompt-confirm") {
      if (spotify && !spotify.lyricsPluginBusy)
        spotify.confirmLyricsPlugin(lyricsRequestKey)
    } else if (action === "artist") openCurrentArtist()
    else if (action === "album") openCurrentAlbum()
    else if (action === "like") {
      if (spotify) spotify.toggleCurrentTrackSaved()
    } else if (action === "shuffle") {
      if (spotify) spotify.setShuffle(!spotify.shuffle)
    } else if (action === "previous") {
      if (spotify) spotify.previous()
    } else if (action === "play") {
      if (spotify) spotify.togglePlayback()
    } else if (action === "next") {
      if (spotify) spotify.next()
    } else if (action === "repeat") {
      if (spotify) spotify.cycleRepeat()
    } else if (action === "lyrics") openLyrics()
    else if (action === "stop") {
      if (spotify) spotify.stopEngine()
      close()
    }
    else if (action === "volume") toggleMute()
    else if (action === "setup") {
      if (spotify && !spotify.loginBusy) spotify.login()
    } else if (action === "setup-cancel") {
      if (spotify) spotify.cancelLogin()
    } else if (action === "open") openFullPanel()
  }

  function handleMiniKey(event) {
    root.noteHeldModifiers(event, true)
    if (shortcutModifiers.isModifierKey(event.key)) {
      if (shortcutModifiers.isHintModifierKey(event.key)) root.latchShortcutMode()
      event.accepted = true
      return
    }
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0
    var plain = !ctrl && !shift && !alt
    var text = String(event.text || "").toLowerCase()

    if (lyricsInstallPromptVisible) {
      if (event.key === Qt.Key_Escape) {
        dismissLyricsInstallPrompt()
      } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
        moveMiniCursor(shift || event.key === Qt.Key_Backtab ? -1 : 1)
      } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up
          || text === "h" || text === "k") {
        moveMiniCursor(-1)
      } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down
          || text === "l" || text === "j") {
        moveMiniCursor(1)
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
          || event.key === Qt.Key_Space) {
        if (!event.isAutoRepeat) activateMiniAction(miniCursor)
      } else return
      root.acceptMiniKey(event)
      return
    }

    if (miniShortcutHelpVisible) {
      if (event.key === Qt.Key_Escape
          || event.key === Qt.Key_Return || event.key === Qt.Key_Enter
          || event.key === Qt.Key_Space) {
        if (!event.isAutoRepeat) toggleMiniShortcutHelp()
        root.acceptMiniKey(event)
      }
      return
    }

    if (event.key === Qt.Key_Escape) {
      close()
    } else if (ctrl && event.key === Qt.Key_Left) {
      if (spotify) spotify.previous()
    } else if (ctrl && event.key === Qt.Key_Right) {
      if (spotify) spotify.next()
    } else if (shift && !ctrl && event.key === Qt.Key_Left) {
      seekBy(-10)
    } else if (shift && !ctrl && event.key === Qt.Key_Right) {
      seekBy(10)
    } else if (ctrl && event.key === Qt.Key_Up) {
      adjustVolume(0.05)
    } else if (ctrl && event.key === Qt.Key_Down) {
      adjustVolume(-0.05)
    } else if (ctrl && !shift && event.key === Qt.Key_S) {
      if (spotify && !event.isAutoRepeat) spotify.setShuffle(!spotify.shuffle)
    } else if (ctrl && !shift && event.key === Qt.Key_R) {
      if (spotify && !event.isAutoRepeat) spotify.cycleRepeat()
    } else if (ctrl && shift && event.key === Qt.Key_L) {
      if (!event.isAutoRepeat) openLyrics()
    } else if (ctrl && shift && !alt && event.key === Qt.Key_A) {
      if (!event.isAutoRepeat) openCurrentArtist()
    } else if (ctrl && shift && !alt && event.key === Qt.Key_B) {
      if (!event.isAutoRepeat) openCurrentAlbum()
    } else if (plain && event.key === Qt.Key_Space) {
      if (spotify && !event.isAutoRepeat) spotify.togglePlayback()
    } else if (plain && event.key === Qt.Key_M) {
      if (!event.isAutoRepeat) toggleMute()
    } else if (plain && event.key === Qt.Key_O) {
      if (!event.isAutoRepeat) openFullPanel()
    } else if (miniCursorFromPointer
        && Api.isCursorNavigationKey(event.key, plain, text)) {
      // The first key only shows a cursor the pointer left behind.
      miniCursorFromPointer = false
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      moveMiniCursor(shift || event.key === Qt.Key_Backtab ? -1 : 1)
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (!event.isAutoRepeat) activateMiniAction(miniCursor)
    } else if (plain && (event.key === Qt.Key_Left || text === "h")) {
      if (miniCursor === "seek") seekBy(-5)
      else if (miniCursor === "volume") adjustVolume(-0.05)
      else moveMiniCursor(-1)
    } else if (plain && (event.key === Qt.Key_Right || text === "l")) {
      if (miniCursor === "seek") seekBy(5)
      else if (miniCursor === "volume") adjustVolume(0.05)
      else moveMiniCursor(1)
    } else if (plain && (event.key === Qt.Key_Up || text === "k")) {
      moveMiniCursor(-1)
    } else if (plain && (event.key === Qt.Key_Down || text === "j")) {
      moveMiniCursor(1)
    } else if (plain && event.key === Qt.Key_Home) {
      setMiniCursor(miniKeyboardActions[0], true)
    } else if (plain && event.key === Qt.Key_End) {
      setMiniCursor(miniKeyboardActions[miniKeyboardActions.length - 1], true)
    } else return
    root.acceptMiniKey(event)
  }

  function syncSettings() {
    if (spotify) spotify.applySettings(settings)
  }

  visible: root.setting("showBarWidget", true) !== false
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  onSettingsChanged: syncSettings()
  onSpotifyChanged: {
    syncSettings()
    if (spotify) spotify.registerPlayerSurface(root)
  }
  onMiniPlayerEnabledChanged: if (!miniPlayerEnabled) close()
  onShortcutHintsEnabledChanged: if (!shortcutHintsEnabled) clearShortcutMode()
  onMiniKeyboardActionsChanged: ensureMiniCursor()
  onLyricsInstallPromptVisibleChanged: {
    if (lyricsInstallPromptVisible) {
      miniCursor = "prompt-cancel"
      miniCursorActive = true
      miniCursorFromPointer = false
    } else ensureMiniCursor()
  }
  onPopupOpenChanged: {
    if (popupOpen) {
      miniCursor = miniKeyboardActions.indexOf("play") >= 0
        ? "play" : miniKeyboardActions[0]
      miniCursorActive = miniKeyboardActions.length > 0
      miniCursorFromPointer = !pendingShortcutLatch
      if (pendingShortcutLatch) latchShortcutMode()
      pendingShortcutLatch = false
    } else {
      miniCursorActive = false
      clearShortcutMode()
      pendingShortcutLatch = false
    }
    if (spotify) spotify.setUiVisible(surfaceKey, popupOpen)
    if (!popupOpen && lyricsInstallPromptVisible
        && (!spotify || !spotify.lyricsPluginBusy)) {
      if (spotify) spotify.cancelLyricsPlugin(lyricsRequestKey)
      lyricsInstallPromptVisible = false
    }
  }
  Component.onCompleted: {
    syncSettings()
    if (spotify) spotify.registerPlayerSurface(root)
  }
  Component.onDestruction: if (spotify) {
    spotify.setUiVisible(surfaceKey, false)
    spotify.unregisterPlayerSurface(root)
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconOnly ? "" : ""
    hasVisualContent: true
    slotSize: Style.bar.iconSlot
    opticalSize: Style.bar.iconCanvas
    fontSize: root.iconOnly ? Math.round(Style.bar.iconFont * 0.9) : Style.font.body
    active: root.spotify && root.spotify.playing
    // Follow the bar's contrast-aware color when transparency changes.
    // Keep root.foreground theme-based for the popup/player surfaces.
    foreground: root.bar ? root.bar.barForeground : root.foreground
    activeColor: foreground
    tooltipText: root.spotify && root.spotify.hasMedia
      ? root.spotify.title + (root.spotify.artist ? " — " + root.spotify.artist : "")
      : (root.spotify && !root.spotify.accountConnected
        ? "Set up OmaSpotify" : "OmaSpotify")
    // Size from the painted glyph and label plus the real inner chrome.
    readonly property real fittedWidth: Math.ceil(barGlyph.width
      + barContent.spacing + barLabel.implicitWidth + scaledHorizontalMargin * 2)
    readonly property real barTextCap: root.spotify ? root.spotify.maxBarTextWidth : 240

    fixedWidth: root.vertical ? root.barSize
      : (root.iconOnly ? Style.bar.iconSlot
        : Api.barSlotWidth(root.spotify && root.spotify.fixedBarWidth,
          barTextCap > 0 ? Style.space(barTextCap) : 0, fittedWidth,
          root.barSize))
    fixedHeight: root.vertical && root.iconOnly ? Style.bar.iconSlot : -1
    clip: true

    Row {
      id: barContent
      anchors.centerIn: parent
      spacing: Style.space(6)
      visible: !root.iconOnly
      enabled: false

      OpticalGlyph {
        id: barGlyph
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(16)
        height: Style.space(16)
        text: ""
        color: button.foreground
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        fontSize: Style.font.body
      }

      Item {
        id: scrollClip
        width: Math.max(0, button.width - barGlyph.width
          - barContent.spacing - button.scaledHorizontalMargin * 2)
        height: barGlyph.height
        anchors.verticalCenter: parent.verticalCenter
        clip: barLabel.needsScroll

        readonly property bool scrolling: root.spotify && root.spotify.scrollBarText
          && barLabel.needsScroll && !root.popupOpen && !root.vertical
          && root.visible && root.spotify.playing && !Style.reduceMotion
        // Use a wide enough ramp to read as a deliberate fade at bar scale.
        readonly property real fadeStop: width > 0
          ? Math.min(0.2, Style.space(28) / width) : 0

        Item {
          id: labelLayer
          anchors.fill: parent
          layer.enabled: scrollClip.scrolling
          layer.smooth: true
          layer.effect: MultiEffect {
            autoPaddingEnabled: false
            maskEnabled: true
            maskSource: scrollFadeMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
          }

          Text {
            id: barLabel
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.barText
            color: button.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            renderType: Text.NativeRendering

            readonly property bool needsScroll: implicitWidth > scrollClip.width
            onTextChanged: if (barScrollAnimation.running) barScrollAnimation.restart()

            // Keep the marquee on the render thread so it remains smooth
            // without dispatching JavaScript timer callbacks through the
            // shared shell's main thread.
            XAnimator on x {
              id: barScrollAnimation
              running: scrollClip.scrolling
              loops: Animation.Infinite
              duration: Math.round(Math.max(6000, barLabel.implicitWidth * 25)
                / Math.max(0.25, root.spotify ? root.spotify.scrollSpeed : 1))
              from: scrollClip.width
              to: -barLabel.implicitWidth
              easing.type: Easing.Linear
              onStopped: barLabel.x = 0
            }
          }
        }

        Rectangle {
          id: scrollFadeMask
          anchors.fill: parent
          visible: false
          layer.enabled: scrollClip.scrolling
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
              position: 0
              color: "transparent"
            }
            GradientStop {
              position: scrollClip.fadeStop
              color: "white"
            }
            GradientStop {
              position: 1 - scrollClip.fadeStop
              color: "white"
            }
            GradientStop {
              position: 1
              color: "transparent"
            }
          }
        }
      }
    }

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        root.contextMenuVisible = true
        root.popupOpen = true
      } else if (mouseButton === Qt.MiddleButton) {
        if (root.spotify) root.spotify.togglePlayback()
      } else {
        root.contextMenuVisible = false
        root.toggle()
      }
    }
    onWheelMoved: function(delta) {
      if (!root.spotify) return
      if (delta > 0) root.spotify.previous()
      else if (delta < 0) root.spotify.next()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: popup.loadedContent
    contentWidth: fittedContentWidth(Style.space(340))
    contentHeight: fittedContentHeight(popup.loadedContentHeight)
    // Built the first time it opens, so a closed player costs no objects on any
    // monitor's bar.
    content: Component {
      MiniPlayerContent { widget: root }
    }
  }

  Connections {
    target: root.spotify
    ignoreUnknownSignals: true
    function onLyricsPluginPromptRequested(surface, availability) {
      if (String(surface) !== root.lyricsRequestKey) return
      root.lyricsInstallPromptVisible = true
      root.popupOpen = true
    }
    function onLyricsPluginOpened(surface) {
      if (String(surface) !== root.lyricsRequestKey) return
      root.lyricsInstallPromptVisible = false
      root.close()
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.popupOpen && root.spotify && root.spotify.playing
    onTriggered: root.spotify.refreshPosition()
  }
}
