import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

import "Api.js" as Api

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false
  property bool closingFromHost: false
  property bool escapeCloseArmed: false
  property real volumeBeforeMute: 0.5
  property double lastVolumeAdjustAt: 0
  property string currentTab: "home"
  property bool openedForLogin: false
  property bool nowPlayingExpanded: false
  property string equalizerMode: "bars"
  readonly property var equalizerModes: ["bars", "pixels", "scope", "matrix"]

  property double searchClock: Date.now()
  readonly property int searchCooldownSeconds: service
    ? Math.max(0, Math.ceil((service.searchCooldownUntil - searchClock) / 1000)) : 0
  Timer {
    interval: 1000
    repeat: true
    running: root.opened && root.showingUniversalSearch && root.service
      && (root.service.searchLoading || root.searchCooldownSeconds > 0)
    onTriggered: root.searchClock = Date.now()
  }
  property string searchText: ""
  property string searchType: "track"
  property string libraryType: "tracks"
  property string homeType: "recent"
  property string libraryFilter: ""
  property string librarySort: "default"
  property string playlistFilter: ""
  property string playlistSort: "default"
  property string detailFilter: ""
  property string detailSort: "default"
  property string homeFilter: ""
  property string discoverFilter: ""
  property string queueFilter: ""
  property string artistSearchText: ""
  property bool searchInContext: true
  property bool universalSearchActive: false
  property var scrollPositions: ({})
  property var scrollPositionOrder: []
  readonly property int scrollPositionLimit: 128
  property var navigationStack: []
  property string lastContentTab: "home"
  property string restoredPlaylistId: ""
  property var restoredPlaylist: null
  property int restoredPlaylistItemCount: 0
  property int restoredDetailItemCount: 0

  property string draftClientId: ""
  property string draftDeviceName: "OmaSpotify"
  property string draftIdleMinutes: "15"
  property bool draftShowMiniPlayer: true
  property bool draftShowArtwork: true
  property bool draftShowVinylRecord: false
  property string draftShortcutPlayer: "Omarchy Music app"
  property bool draftShortcutHints: true
  property bool draftShowLyrics: true
  property bool shortcutModeLatched: false
  property int heldModifierFlags: 0
  property bool panelCursorActive: false
  // Hover moves the cursor without drawing it, so a highlight never lingers.
  property bool panelCursorFromPointer: false
  property string panelCursorRegion: "footer"
  property string panelCursorAction: "play"
  property string popupReturnRegion: "page"
  property string popupReturnAction: "list"
  property bool draftShowTitle: true
  property bool draftShowArtist: false
  property bool draftShowPausedTrack: true
  property bool draftScrollBarText: false
  property bool draftFixedBarWidth: false
  property real draftScrollSpeed: 1
  // 0 means no cap — the slot grows with the track text.
  property real draftMaxBarTextWidth: 240
  // Disclosure state for the width slider; deliberately not persisted.
  property bool barTextWidthExpanded: false
  property string draftAudioQuality: "320 kbps"
  property bool draftNormalizeVolume: true
  property string draftVolumeLevel: "Normal"
  property var contextItem: null
  property var contextSourceItems: []
  property string contextSourceUri: ""
  property string contextPlaybackUri: ""
  property int contextSourceIndex: -1
  property var contextPlaylist: null
  property bool contextFromSidebar: false
  property var pendingPlaylistItem: null
  property string newPlaylistName: ""
  property string createPlaylistName: ""

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "io.github.atlastimed.omaspotify"
  readonly property string appName: manifest && manifest.name
    ? String(manifest.name) : "OmaSpotify"
  readonly property string lyricsRequestKey: "spotify-panel-lyrics"
  readonly property color foreground: Commons.Color.foreground
  readonly property color background: Commons.Color.background
  readonly property color accent: Commons.Color.accent
  // Readable secondary text. The theme's own muted colour is decorative.
  readonly property color muted: Api.secondaryTextColor(Commons.Color.foreground,
    Commons.Color.background)
  readonly property int pageGap: Style.space(8)
  // In-panel popups have no blur behind them, so a translucent theme popup
  // colour is floored to stay readable over the list beneath.
  readonly property color popupBackground: Api.opaqueSurface(
    Commons.Color.popups.background, 0.96)
  readonly property var popupBorderSpec: Border.flat(Commons.Color.popups.border,
    Math.max(1, Style.normalBorderWidth))
  readonly property int popupScrollbarGutter: Style.space(14)
  readonly property string fontFamily: Style.font.family
  readonly property bool fullyConnected: service && service.fullyConnected
  readonly property bool accountConnected: service && service.accountConnected
  readonly property bool sessionPending: service && service.sessionPending
  readonly property bool compactHeight: window.height < Style.space(620)
  readonly property bool compactWidth: window.width < Style.space(760)
  readonly property bool extraNarrowWidth: window.width < Style.space(440)
  readonly property var activeSearchScope: Api.searchScope(currentTab,
    service ? service.detailItem : null,
    service ? service.selectedPlaylist : null, homeType, libraryType)
  readonly property bool showingUniversalSearch: Api.universalSearchVisible(
    currentTab, universalSearchActive)
  readonly property bool artistScopedSearchActive: currentTab === "detail"
    && service && service.detailItem && service.detailItem.type === "artist"
    && artistSearchText.trim() !== ""
  readonly property bool shortcutsBlocked: mediaContextMenu.opened
    || playlistPicker.opened || createPlaylistPopup.opened || sleepPopup.opened
    || shortcutHelpPopup.opened || lyricsInstallPopup.opened || confirmPopup.opened
  readonly property bool shortcutHintsEnabled: service
    ? service.shortcutHintsEnabled : true
  readonly property bool typingInField: {
    var item = window.activeFocusItem
    return !!item && ("acceptableInput" in item || "echoMode" in item)
  }
  readonly property bool shortcutHintsActive: shortcutHintsEnabled
    && shortcutModeLatched && !typingInField && !shortcutsBlocked
  readonly property bool shortcutHintsInPopup: shortcutHintsEnabled
    && shortcutModeLatched && !typingInField
  readonly property var windowContentItem: window.contentItem
  readonly property real windowWidth: window.width
  readonly property real windowHeight: window.height
  // The library is a list or a grid, never both. Everything the keyboard does
  // has to follow whichever one is on screen.
  readonly property var sidebarListView: sidebar.libraryView
  readonly property int playlistShortcutIndex: sidebarListView.currentIndex
  readonly property bool searchFieldFocused: unifiedSearchField.activeFocus
  readonly property bool searchBarVisible: unifiedSearchBar.visible
  readonly property bool searchInline: contentPane.width >= Style.space(560)
  readonly property bool shortcutHelpOpen: shortcutHelpPopup.opened
  // The keyboard is showing the cursor. Hover moves it without drawing it.
  readonly property bool keyboardCursorShown: panelCursorVisible && !panelCursorFromPointer
  readonly property bool pageRefreshing: service && (service.homeLoading
    || service.devicesLoading || service.queueLoading || service.detailLoading)
  // Worked out once per cursor change, so the hints on screen share one answer.
  property var cursorNav: ({ tab: {}, back: {}, regionActions: [], sidebarIndex: -1,
    sidebarCount: 0, pageIndex: -1, pageCount: 0 })
  readonly property bool hintCtrlHeld: (heldModifierFlags & Qt.ControlModifier) !== 0
  readonly property bool hintShiftHeld: (heldModifierFlags & Qt.ShiftModifier) !== 0
  readonly property bool hintAltHeld: (heldModifierFlags & Qt.AltModifier) !== 0
  readonly property bool popupCursorOpen: sleepPopup.opened || mediaContextMenu.opened
  readonly property bool panelCursorVisible: panelCursorActive && !typingInField
    && (!shortcutsBlocked || popupCursorOpen)

  component KeyHint: PanelKeyHint {
    panel: root
  }
  readonly property var panelBar: QtObject {
    readonly property color foreground: root.foreground
    readonly property color background: root.background
    readonly property color urgent: Commons.Color.urgent
    readonly property string fontFamily: root.fontFamily
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: 28
  }

  function syncDraftSettings() {
    if (!service) return
    draftClientId = String(service.settings.clientId || "")
    draftDeviceName = service.deviceName
    draftIdleMinutes = String(service.idleShutdownMinutes)
    draftShowMiniPlayer = service.showMiniPlayer
    draftShowArtwork = service.artworkEnabled
    draftShowVinylRecord = service.showVinylRecord
    draftShortcutPlayer = service.shortcutPlayer
    draftShortcutHints = service.shortcutHintsEnabled
    draftShowLyrics = service.showLyrics
    draftShowTitle = service.showTrackTitle
    draftShowArtist = service.showArtistName
    draftShowPausedTrack = service.showPausedTrack
    draftScrollBarText = service.scrollBarText
    draftScrollSpeed = service.scrollSpeed
    draftMaxBarTextWidth = service.maxBarTextWidth
    draftFixedBarWidth = service.fixedBarWidth
    draftAudioQuality = service.audioQuality
    draftNormalizeVolume = service.normalizeVolume
    draftVolumeLevel = service.volumeLevel
  }

  function saveSettings(showStatus) {
    if (!service) return
    var values = {
      deviceName: String(draftDeviceName || "").trim() || "OmaSpotify",
      idleShutdownMinutes: Math.max(0, Math.min(1440,
        Math.floor(Number(draftIdleMinutes) || 0))),
      showMiniPlayer: draftShowMiniPlayer ? "On" : "Off",
      showArtwork: draftShowArtwork ? "On" : "Off",
      showVinylRecord: draftShowVinylRecord ? "On" : "Off",
      shortcutPlayer: draftShortcutPlayer,
      shortcutHints: draftShortcutHints ? "On" : "Off",
      showLyrics: draftShowLyrics ? "On" : "Off",
      showTrackTitle: draftShowTitle ? "On" : "Off",
      showArtistName: draftShowArtist ? "On" : "Off",
      showPausedTrack: draftShowPausedTrack ? "On" : "Off",
      scrollBarText: draftScrollBarText ? "On" : "Off",
      scrollSpeed: Api.normalizedScrollSpeed(draftScrollSpeed),
      maxBarTextWidth: Api.normalizedMaxBarTextWidth(draftMaxBarTextWidth),
      fixedBarWidth: draftFixedBarWidth ? "On" : "Off",
      audioQuality: draftAudioQuality,
      normalizeVolume: draftNormalizeVolume ? "On" : "Off",
      volumeLevel: draftVolumeLevel
    }
    service.persistSettings(values)
    syncDraftSettings()
    if (showStatus !== false) service.succeed("Settings saved")
  }

  function persistDraftSettings() {
    saveSettings(false)
  }

  function cycleAudioQuality() {
    draftAudioQuality = draftAudioQuality === "96 kbps" ? "160 kbps"
      : (draftAudioQuality === "160 kbps" ? "320 kbps" : "96 kbps")
    persistDraftSettings()
  }

  function toggleNormalizeVolume() {
    draftNormalizeVolume = !draftNormalizeVolume
    persistDraftSettings()
  }

  function cycleVolumeLevel() {
    draftVolumeLevel = draftVolumeLevel === "Quiet" ? "Normal"
      : (draftVolumeLevel === "Normal" ? "Loud" : "Quiet")
    persistDraftSettings()
  }

  function volumeLevelLabel() {
    return Api.normalizedVolumeLevel(draftVolumeLevel)
  }

  function cycleShortcutPlayer() {
    draftShortcutPlayer = draftShortcutPlayer === "Omarchy Music app"
      ? "Full player"
      : (draftShortcutPlayer === "Full player"
        ? "Mini player" : "Omarchy Music app")
    persistDraftSettings()
  }

  function audioQualityLabel() {
    if (draftAudioQuality === "96 kbps") return "Standard · 96 kbps"
    if (draftAudioQuality === "320 kbps") return "Very high · 320 kbps"
    return "High · 160 kbps"
  }

  function scrollSpeedLabel() {
    var value = Api.normalizedScrollSpeed(draftScrollSpeed)
    return value.toFixed(2).replace(/\.00$/, "").replace(/0$/, "") + "×"
  }

  readonly property var barTextWidthSlider: Api.barTextWidthSlider()
  readonly property bool barTextWidthUnlimited:
    Api.normalizedMaxBarTextWidth(draftMaxBarTextWidth) === 0

  function maxBarTextWidthLabel() {
    var value = Api.normalizedMaxBarTextWidth(draftMaxBarTextWidth)
    return value === 0 ? "Unlimited" : Math.round(value) + " px"
  }
  function maxBarTextWidthSliderValue() {
    var value = Api.normalizedMaxBarTextWidth(draftMaxBarTextWidth)
    return value === 0 ? barTextWidthSlider.unlimited : value
  }
  function setMaxBarTextWidthFromSlider(value) {
    draftMaxBarTextWidth = value >= barTextWidthSlider.unlimited
      ? 0 : Api.normalizedMaxBarTextWidth(value)
    enforceScrollAvailability()
  }

  function enforceScrollAvailability() {
    if (barTextWidthUnlimited) {
      draftScrollBarText = false
      draftFixedBarWidth = false
    }
    if (!Api.canScrollBarText(draftShowTitle, draftShowArtist))
      draftScrollBarText = false
  }

  function connectionButtonText() {
    if (!service) return "Spotify unavailable"
    if (service.loginBusy) return service.loginProgress + "…"
    if (fullyConnected) return "Connected"
    if (accountConnected && !service.daemon.playbackReady)
      return "Set up playback"
    if (accountConnected) return "Finish playback setup"
    if (!service.daemon.playbackReady) return "Set up and continue"
    return "Continue with Spotify"
  }

  function connectionHeadline() {
    if (!service) return "Spotify is unavailable"
    if (service.daemon.setupBusy) return "Setting up playback"
    if (fullyConnected) return "You're connected"
    if (accountConnected) return "Account connected"
    if (!service.daemon.playbackReady) return "One quick setup, then Spotify"
    return "Continue with Spotify"
  }

  function connectionErrorText() {
    if (!service) return "OmaSpotify is unavailable"
    return service.lastError || service.auth.lastError || service.daemon.lastError
  }

  function playbackStatusText() {
    if (!service) return "Playback is unavailable"
    if (!service.daemon.requirementsChecked) return "Checking playback support…"
    if (service.daemon.setupBusy) return "Preparing playback on this computer…"
    if (!service.daemon.playbackReady) return "A quick one-time setup is needed"
    if (!service.daemon.credentialsChecked) return "Checking your Spotify connection…"
    if (!service.daemon.credentialsAvailable) return "Ready for Spotify sign-in"
    if (service.daemon.running) return "Active on this computer"
    return "Ready — starts automatically when you play music"
  }

  function openMediaContext(item, sceneX, sceneY, sourceItems, contextUri, index,
      playbackContextUri) {
    if (!item) return
    contextFromSidebar = false
    contextItem = item
    contextSourceItems = Array.isArray(sourceItems) ? sourceItems : []
    contextSourceUri = String(contextUri || "")
    contextPlaybackUri = playbackContextUri === undefined
      ? contextSourceUri : String(playbackContextUri || "")
    contextSourceIndex = index === undefined ? -1 : Math.floor(Number(index))
    contextPlaylist = playlistForContext(contextSourceUri)
    mediaContextMenu.requestedX = Number(sceneX) || 0
    mediaContextMenu.requestedY = Number(sceneY) || 0
    mediaContextMenu.open()
  }

  function dismissTransientPopup() {
    if (lyricsInstallPopup.opened && (!service || !service.lyricsPluginBusy)) {
      lyricsInstallPopup.close()
      return true
    }
    if (shortcutHelpPopup.opened) {
      shortcutHelpPopup.close()
      return true
    }
    if (mediaContextMenu.opened) {
      mediaContextMenu.close()
      return true
    }
    if (playlistPicker.opened) {
      playlistPicker.close()
      return true
    }
    if (createPlaylistPopup.opened) {
      createPlaylistPopup.close()
      return true
    }
    if (sleepPopup.opened) {
      sleepPopup.close()
      return true
    }
    if (confirmPopup.opened) {
      confirmPopup.close()
      return true
    }
    return false
  }

  function askToConfirm(message, confirmText, action) {
    confirmPopup.message = String(message || "")
    confirmPopup.confirmText = String(confirmText || "Confirm")
    confirmPopup.action = action
    confirmPopup.open()
  }

  function dismissFailure() {
    if (!service || !service.lastError || currentTab === "login") return false
    service.lastError = ""
    return true
  }

  function retryAfterFailure() {
    dismissFailure()
    refreshCurrentView()
  }

  // Refresh the current surface. Invalidating the entire sidebar here used to
  // spend dozens of unrelated requests.
  function refreshCurrentView() {
    if (!service) return
    service.retryApiRequests()
    if (currentTab === "home" && homeType === "releases") service.releaseFeed.load()
    else if (showingUniversalSearch) runUnifiedSearch(true)
    else if (currentTab === "detail" && service.detailItem)
      service.openDetail(service.detailItem,
        service.detailItem.type === "artist" ? artistSearchText : "")
    else if (currentTab === "library") service.loadLibrary(libraryType, false, true)
    else service.refreshView(currentTab)
  }

  function disarmEscapeClose() {
    escapeCloseTimer.stop()
    escapeCloseArmed = false
  }

  function armEscapeClose() {
    escapeCloseArmed = true
    escapeCloseTimer.restart()
  }

  function releaseSearchFocus() {
    if (unifiedSearchField.activeFocus) unifiedSearchField.focus = false
    focusScope.forceActiveFocus()
  }

  function dismissSearch() {
    var action = Api.searchEscapeAction(unifiedSearchBar.visible,
      unifiedSearchField.activeFocus, unifiedSearchText(),
      showingUniversalSearch && currentTab !== "search")
    if (action === "dismiss") {
      clearUnifiedSearch()
      releaseSearchFocus()
      disarmEscapeClose()
      return true
    }
    if (action === "blur") {
      releaseSearchFocus()
      return false
    }
    return false
  }

  function turnPlaylistIntoOwn(playlist) {
    if (!service || !playlist) return
    askToConfirm("Copy every available song from “" + String(playlist.name || "this playlist")
      + "” into a new private playlist, then stop following the original?", "Make my copy",
      function() {
        root.service.makePlaylistYourOwn(playlist, function(copy) {
          if (!copy) return
          root.chooseTab("playlists")
          root.service.openPlaylist(copy)
        })
      })
  }

  function playlistForContext(uri) {
    var value = String(uri || "")
    if (!service || !value) return null
    if (service.selectedPlaylist && service.selectedPlaylist.uri === value)
      return service.selectedPlaylist
    if (service.detailItem && service.detailItem.type === "playlist"
        && service.detailItem.uri === value) return service.detailItem
    return null
  }

  function rememberScroll(key, value) {
    var name = String(key || currentTab)
    var position = Math.max(0, Number(value) || 0)
    if (!scrollPositions || typeof scrollPositions !== "object")
      scrollPositions = ({})
    if (!Array.isArray(scrollPositionOrder)) scrollPositionOrder = []
    scrollPositions[name] = position
    var evicted = Api.touchBoundedOrder(scrollPositionOrder, name,
      scrollPositionLimit)
    if (evicted) delete scrollPositions[evicted]
  }

  function scrollFor(key) {
    return Math.max(0, Number(scrollPositions[String(key || currentTab)]) || 0)
  }

  function restoreScrollPositions(values) {
    var source = values && typeof values === "object" ? values : ({})
    var keys = Object.keys(source)
    var start = Math.max(0, keys.length - scrollPositionLimit)
    var next = ({})
    var order = []
    for (var i = start; i < keys.length; i++) {
      var name = keys[i]
      next[name] = Math.max(0, Number(source[name]) || 0)
      order.push(name)
    }
    scrollPositions = next
    scrollPositionOrder = order
  }

  function restoreUiState(restoreDetail) {
    if (!service) return
    var state = service.sessionState || ({})
    service.restoreLastRadioPlaylist(state.lastRadioPlaylist)
    searchText = String(state.searchText || service.searchQuery || "")
    searchType = Api.SEARCH_TYPES.indexOf(String(state.searchType || "")) >= 0
      ? String(state.searchType) : "track"
    libraryType = ["tracks", "albums", "artists", "shows", "episodes", "audiobooks"]
      .indexOf(String(state.libraryType || "")) >= 0 ? String(state.libraryType) : "tracks"
    homeType = ["recent", "tracks", "artists", "releases"]
      .indexOf(String(state.homeType || "")) >= 0
      ? String(state.homeType) : "recent"
    libraryFilter = String(state.libraryFilter || "")
    librarySort = String(state.librarySort || "default")
    playlistFilter = String(state.playlistFilter || "")
    playlistSort = String(state.playlistSort || "default")
    detailFilter = String(state.detailFilter || "")
    detailSort = String(state.detailSort || "default")
    homeFilter = String(state.homeFilter || "")
    discoverFilter = String(state.discoverFilter || "")
    queueFilter = String(state.queueFilter || "")
    artistSearchText = String(state.artistSearchText || "")
    searchInContext = true
    universalSearchActive = false
    restoreScrollPositions(state.scrollPositions)
    restoredPlaylist = state.selectedPlaylist && state.selectedPlaylist.id
      && state.selectedPlaylist.type === "playlist" ? state.selectedPlaylist : null
    restoredPlaylistId = String(state.selectedPlaylistId
      || (restoredPlaylist ? restoredPlaylist.id : ""))
    restoredPlaylistItemCount = Api.normalizedPlaylistRestoreCount(
      state.selectedPlaylistItemCount)
    restoredDetailItemCount = Api.normalizedPlaylistRestoreCount(
      state.detailItemCount)
    equalizerMode = equalizerModes.indexOf(String(state.equalizerMode || "")) >= 0
      ? String(state.equalizerMode) : "bars"
    var restoredTab = String(state.tab || "home")
    if (["home", "discover", "search", "library", "playlists", "detail", "queue",
      "stats", "devices", "setup"]
        .indexOf(restoredTab) >= 0) currentTab = restoredTab
    if (restoreDetail !== false && currentTab === "detail" && state.detailItem) {
      var sameDetail = service.detailItem
        && String(service.detailItem.id) === String(state.detailItem.id)
        && String(service.detailItem.type) === String(state.detailItem.type)
      if (sameDetail) service.ensureDetailItemCount(restoredDetailItemCount)
      else service.openDetail(state.detailItem, artistSearchText,
        restoredDetailItemCount)
    }
    syncUnifiedSearchField()
  }

  function persistUiState() {
    if (!service) return
    var selected = service.selectedPlaylist || restoredPlaylist
    var selectedItemCount = service.selectedPlaylist
      ? service.playlistRememberedItemCount : restoredPlaylistItemCount
    service.persistSession({
      tab: currentTab === "login" ? "home" : currentTab,
      searchText: searchText,
      searchType: searchType,
      libraryType: libraryType,
      homeType: homeType,
      libraryFilter: libraryFilter,
      librarySort: librarySort,
      playlistFilter: playlistFilter,
      playlistSort: playlistSort,
      detailFilter: detailFilter,
      detailSort: detailSort,
      homeFilter: homeFilter,
      discoverFilter: discoverFilter,
      queueFilter: queueFilter,
      artistSearchText: currentTab === "detail" && service.detailItem
        && service.detailItem.type === "artist" ? artistSearchText : "",
      scrollPositions: scrollPositions,
      detailItem: currentTab === "detail" && service.detailItem ? service.detailItem : null,
      detailItemCount: currentTab === "detail" && service.detailItem
        && service.detailItem.type === "playlist"
        ? service.detailRememberedItemCount : 0,
      selectedPlaylist: selected,
      selectedPlaylistId: selected ? selected.id : restoredPlaylistId,
      selectedPlaylistItemCount: selectedItemCount,
      lastRadioPlaylist: service.lastRadioPlaylist,
      equalizerMode: equalizerMode
    })
  }

  function restorePlaylistSelection() {
    if (!service || !restoredPlaylistId || currentTab !== "playlists") return
    if (service.selectedPlaylist) {
      if (String(service.selectedPlaylist.id) === restoredPlaylistId)
        service.ensurePlaylistItemCount(restoredPlaylistItemCount)
      return
    }
    var playlist = service.playlistById(restoredPlaylistId)
    if (!playlist && restoredPlaylist
        && String(restoredPlaylist.id) === restoredPlaylistId)
      playlist = restoredPlaylist
    if (playlist) service.openPlaylist(playlist, restoredPlaylistItemCount)
  }

  function openItem(item) {
    nowPlayingExpanded = false
    if (!item) return
    if (item.type === "artist" && !item.id) {
      if (service) service.resolveArtist(item.name, function(resolved) {
        root.openItem(resolved)
      })
      return
    }
    if (item.kind !== "context") {
      activateMedia(item, [item], "")
      return
    }
    var stack = navigationStack.slice()
    stack.push({
      tab: currentTab,
      item: currentTab === "detail" && service ? service.detailItem : null,
      universalSearchActive: universalSearchActive,
      searchInContext: searchInContext,
      artistSearchText: currentTab === "detail" && service && service.detailItem
        && service.detailItem.type === "artist" ? artistSearchText : "",
      detailFilter: currentTab === "detail" && service && service.detailItem
        && service.detailItem.type !== "artist" ? detailFilter : ""
    })
    navigationStack = stack
    unifiedSearchDelay.stop()
    searchInContext = true
    universalSearchActive = false
    if (service) service.cancelSearch(false)
    currentTab = "detail"
    if (item.type === "artist") artistSearchText = ""
    else detailFilter = ""
    if (service) service.openDetail(item)
    syncUnifiedSearchField()
  }

  function openCurrentArtist() {
    if (!service || !service.currentArtistContextAvailable) return
    service.currentContext("artist", function(item) { openItem(item) })
  }

  function openCurrentAlbum() {
    if (!service || !service.currentAlbumContextAvailable) return
    service.currentContext("album", function(item) { openItem(item) })
  }

  function toggleNowPlayingExpanded() {
    if (currentTab === "login") return
    nowPlayingExpanded = !nowPlayingExpanded
    if (nowPlayingExpanded) setPanelCursor("footer", "play")
  }

  function cycleEqualizerMode() {
    var index = equalizerModes.indexOf(equalizerMode)
    equalizerMode = equalizerModes[(index + 1) % equalizerModes.length]
    persistUiState()
  }

  function collapseNowPlaying() {
    if (!nowPlayingExpanded) return false
    nowPlayingExpanded = false
    return true
  }

  function goBack() {
    nowPlayingExpanded = false
    if (!navigationStack.length) {
      chooseTab("home")
      return
    }
    var stack = navigationStack.slice()
    var destination = stack.pop()
    navigationStack = stack
    unifiedSearchDelay.stop()
    if (service) service.cancelSearch(false)
    currentTab = destination.tab || "search"
    universalSearchActive = destination.universalSearchActive === true
    searchInContext = destination.searchInContext === undefined
      ? !universalSearchActive : destination.searchInContext === true
    if (currentTab === "detail" && destination.item && service) {
      artistSearchText = destination.item.type === "artist"
        ? String(destination.artistSearchText || "") : ""
      detailFilter = destination.item.type === "artist"
        ? "" : String(destination.detailFilter || "")
      service.openDetail(destination.item, artistSearchText)
    }
    if (service && (currentTab === "search" || universalSearchActive)) {
      if (searchText.trim() === "") service.clearSearch()
      else service.search(searchText, searchType)
    }
    else if (service && currentTab !== "detail") service.openView(currentTab, false)
    syncUnifiedSearchField()
  }

  function activateMedia(item, sourceItems, contextUri, successMessage) {
    if (!item || !service) return
    if (unifiedSearchField.activeFocus) focusScope.forceActiveFocus()
    service.playItem(item, sourceItems, contextUri, successMessage)
  }

  function playSelectedPlaylist() {
    if (!service || !service.selectedPlaylist) return
    var collection = pageCollection()
    if (collection && collection.playbackUsesVisibleOrder) {
      var items = Api.arrayValues(collection.visibleItems)
      if (!items.length) {
        service.fail("No visible playlist items to play")
        return
      }
      activateMedia(items[0], items, "",
        Api.visibleOrderPlaybackMessage(items.length))
      return
    }
    activateMedia(service.selectedPlaylist)
  }

  function textInputFocused() {
    var item = window.activeFocusItem
    return !!item && ("acceptableInput" in item || "echoMode" in item)
  }

  function shortcutHint(label, keys) {
    var text = String(label || "")
    var shortcut = String(keys || "")
    return shortcut ? text + " · " + shortcut : text
  }

  function applySequenceModifiers(sequence) {
    heldModifierFlags = shortcutModifiers.flagsForSequence(sequence)
  }

  function latchShortcutMode(sequence) {
    if (!shortcutHintsEnabled) return
    shortcutModeLatched = true
    if (sequence) applySequenceModifiers(sequence)
    scheduleCursorRefresh()
  }

  function clearShortcutMode() {
    shortcutModeLatched = false
    heldModifierFlags = 0
    panelCursorActive = false
  }

  function disableShortcutHints() {
    draftShortcutHints = false
    if (service) service.persistSettings({ shortcutHints: "Off" })
    else clearShortcutMode()
  }





  function noteHeldModifiers(event, pressed) {
    if (!event) return
    heldModifierFlags = shortcutModifiers.flagsAfterEvent(event.modifiers,
      pressed, heldModifierFlags, event.key)
  }

  function considerShortcutModeKey(event, pressed) {
    noteHeldModifiers(event, pressed)
    if (!pressed || typingInField) return
    if (shortcutModifiers.isHintModifierKey(event.key) || event.key === Qt.Key_Tab
        || event.key === Qt.Key_Backtab || event.key === Qt.Key_F6
        || (event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier
          | Qt.AltModifier)) !== 0)
      latchShortcutMode()
  }

  function cursorOn(region, action) {
    return panelCursorVisible && panelCursorRegion === region
      && panelCursorAction === action
  }

  function cursorShown(region, action) {
    return !panelCursorFromPointer && cursorOn(region, action)
  }

  function showKeyboardCursor() {
    panelCursorActive = true
    panelCursorFromPointer = false
  }

  function cursorActionsByRegion() {
    return {
      sidebar: sidebarCursorActions(),
      header: headerCursorActions(),
      page: pageCursorActions(),
      footer: footerCursorActions(),
      popup: sleepCursorActions()
    }
  }

  function pageListCount() {
    var collection = pageCollection()
    return collection ? collection.listCount : 0
  }

  function firstVisibleIndexOf(list) {
    if (!list || list.count <= 0) return 0
    var y = list.contentY + 1
    if (list.originY !== undefined && y < list.originY) y = list.originY + 1
    var index = list.indexAt(Math.max(1, list.width / 2), y)
    return Api.listHintRowIndex(list.count, index)
  }

  function tabDestination(back) {
    if (unifiedSearchField.activeFocus) {
      return Api.tabCursorDestination({
        regions: panelCursorRegions(),
        currentRegion: "header",
        currentAction: "search",
        pageActions: pageCursorActions(),
        actionsByRegion: cursorActionsByRegion(),
        listCount: pageListCount(),
        pageLanding: searchPageLanding(),
        cursorActive: true,
        back: !!back
      })
    }
    if (sleepPopup.opened) {
      return Api.tabCursorDestination({
        regions: ["popup"],
        currentRegion: "popup",
        currentAction: panelCursorAction,
        actionsByRegion: cursorActionsByRegion(),
        cursorActive: true,
        back: !!back
      })
    }
    return Api.tabCursorDestination({
      regions: panelCursorRegions(),
      currentRegion: panelCursorRegion,
      currentAction: panelCursorAction,
      pageActions: pageCursorActions(),
      actionsByRegion: cursorActionsByRegion(),
      listCount: pageListCount(),
      pageLanding: searchPageLanding(),
      cursorActive: panelCursorActive,
      back: !!back
    })
  }

  function jumpToListTabRow() {
    var collection = collectionForListAction(panelCursorAction)
    if (collection && collection.jumpToFirstVisible) {
      collection.jumpToFirstVisible()
    }
  }

  function searchPageLanding() {
    if (!showingUniversalSearch) return ""
    var type = String(searchType || "track")
    return "search-" + type
  }

  function applyCursorDestination(dest) {
    if (!dest || !dest.region) return
    latchShortcutMode()
    showKeyboardCursor()
    var fromRegion = panelCursorRegion
    var fromAction = panelCursorAction
    panelCursorRegion = dest.region
    panelCursorAction = dest.action
    ensurePanelCursor(dest.region)
    if (dest.action && regionCursorActions(panelCursorRegion).indexOf(dest.action) >= 0)
      panelCursorAction = dest.action
    if (Api.isCursorListAction(panelCursorAction)
        && (fromRegion !== "page" || fromAction !== panelCursorAction))
      jumpToListTabRow()
    syncCursorFocus()
  }

  function applyTabDestination(back) {
    applyCursorDestination(tabDestination(back))
  }

  function navHintFor(region, action) {
    if (!shortcutHintsEnabled || !shortcutModeLatched) return ""
    var nav = cursorNav
    var listAction = ""
    var listIndex = -1
    var listCount = 0
    if (region === "sidebar") {
      listAction = "sidebar-playlists"
      listIndex = nav.sidebarIndex
      listCount = nav.sidebarCount
    } else if (region === "page") {
      listAction = Api.isCursorListAction(panelCursorAction) ? panelCursorAction : ""
      listIndex = nav.pageIndex
      listCount = nav.pageCount
    }
    return Api.cursorNavHint({
      region: region,
      action: action,
      currentRegion: panelCursorRegion,
      currentAction: panelCursorAction,
      regionActions: nav.regionActions,
      tabRegion: nav.tab.region,
      tabAction: nav.tab.action,
      backtabRegion: nav.back.region,
      backtabAction: nav.back.action,
      listAction: listAction,
      listIndex: listIndex,
      listCount: listCount,
      cursorActive: panelCursorVisible,
      modifiersHeld: hintCtrlHeld || hintShiftHeld || hintAltHeld
    })
  }

  function sidebarPlaylistNavHint(index) {
    if (!panelCursorVisible || !shortcutHintsActive) return ""
    var actions = sidebarCursorActions()
    var prev = Api.moveCursorAction(actions, "sidebar-playlists", -1)
    var next = Api.moveCursorAction(actions, "sidebar-playlists", 1)
    var tab = tabDestination(false)
    var back = tabDestination(true)
    return Api.cursorListRowHint({
      rowIndex: index,
      currentIndex: sidebarListView.currentIndex,
      count: sidebarListView.count,
      tabRowIndex: firstVisibleIndexOf(sidebarListView),
      atList: panelCursorRegion === "sidebar"
        && panelCursorAction === "sidebar-playlists",
      previousIsCurrent: panelCursorRegion === "sidebar"
        && panelCursorAction === prev && prev !== "sidebar-playlists",
      nextIsCurrent: panelCursorRegion === "sidebar"
        && panelCursorAction === next && next !== "sidebar-playlists",
      tabIsList: tab.region === "sidebar" && tab.action === "sidebar-playlists",
      backtabIsList: back.region === "sidebar"
        && back.action === "sidebar-playlists",
      modifiersHeld: hintCtrlHeld || hintShiftHeld || hintAltHeld
    })
  }

  // Runs on every cursor move, so it never walks into the rows of a list.
  function findNamedItems(item, name, found) {
    var results = found || []
    if (!item || item.visible === false) return results
    if (item.objectName === name) {
      results.push(item)
      return results
    }
    if (item.objectName === "media-collection") return results
    var kids = item.children
    if (!kids) return results
    for (var i = 0; i < kids.length; i++)
      findNamedItems(kids[i], name, results)
    return results
  }

  function findNamedItem(item, name) {
    return findNamedItems(item, name)[0] || null
  }

  function pageCollection() {
    return findNamedItem(pageLoader.item, "media-collection")
  }

  function pageCollections() {
    return findNamedItems(pageLoader.item, "media-collection")
  }

  function collectionForListAction(action) {
    var id = String(action || "list")
    var collections = pageCollections()
    for (var i = 0; i < collections.length; i++) {
      var collection = collections[i]
      var listId = collection.keyboardListId || "list"
      if (listId === id) return collection
    }
    if (id === "list" && collections.length) return collections[0]
    return null
  }

  function sidebarCursorActions() {
    if (currentTab === "login") return []
    var actions = []
    if (extraNarrowWidth) {
      var narrow = extraNarrowNavigationItems()
      for (var n = 0; n < narrow.length; n++) actions.push("nav-" + narrow[n].id)
      return actions
    }
    var items = primaryNavigationItems()
    for (var i = 0; i < items.length; i++)
      actions.push("nav-" + items[i].id)
    actions.push("nav-library")
    if (accountConnected && service && !service.playlistActionBusy)
      actions.push("nav-create")
    if (!compactWidth) {
      actions.push("lib-filter", "lib-sort", "lib-view")
      if (service && service.sidebarItems.length) actions.push("sidebar-playlists")
    }
    actions.push("nav-setup")
    return actions
  }

  function headerCursorActions() {
    var actions = []
    if (backButton.visible) actions.push("back")
    if (unifiedSearchBar.visible) {
      actions.push("search")
      if (searchScopeButton.visible) actions.push("scope")
    }
    actions.push("help")
    if (refreshButton.visible) actions.push("refresh")
    actions.push("close")
    return actions
  }

  function footerCursorActions() {
    if (currentTab === "login") return []
    var actions = []
    if (service && service.currentTrackSaveAvailable) actions.push("like")
    if (service && service.currentTrackItem) actions.push("context")
    if (!nowPlayingExpanded) {
      if (service && service.currentArtistContextAvailable) actions.push("artist")
      if (service && service.currentAlbumContextAvailable) actions.push("album")
    }
    if (service && service.playbackControllable) {
      if (!extraNarrowWidth) actions.push("shuffle")
      actions.push(spokenWordPlaying ? "back15" : "previous", "play",
        spokenWordPlaying ? "forward30" : "next")
      if (!extraNarrowWidth) actions.push("repeat")
    } else if (service && service.playbackStartable) actions.push("play")
    if (service && service.lengthSeconds > 0 && service.playbackControllable)
      actions.push("seek")
    if (!extraNarrowWidth) {
      if (service && service.volumeSupported) actions.push("volume")
      actions.push("devices", "sleep")
      if (service && service.lyricsAvailable) actions.push("lyrics")
      actions.push("expand")
    }
    return actions
  }

  function pageCursorActions() {
    var actions = []
    if (currentTab === "home")
      actions.push("home-recent", "home-tracks", "home-artists", "home-releases")
    if (currentTab === "home" && homeType === "releases" && service
        && service.releaseFeed.hasMore && !service.releaseFeed.loading)
      actions.push("releases-more")
    if (currentTab === "library")
      actions.push("library-tracks", "library-albums", "library-artists",
        "library-shows", "library-episodes", "library-audiobooks")
    if (currentTab === "playlists" && service && service.selectedPlaylist)
      actions.push("playlist-play", "playlist-more")
    if (currentTab === "queue") actions.push("queue-refresh")
    if (currentTab === "stats")
      actions.push("stats-short_term", "stats-medium_term", "stats-long_term")
    if (showingUniversalSearch) {
      if (service && service.searchError) actions.push("retry-search")
      for (var s = 0; s < Api.SEARCH_TYPES.length; s++)
        actions.push("search-" + Api.SEARCH_TYPES[s])
    }
    if (currentTab === "detail" && service && service.detailItem
        && !showingUniversalSearch) {
      var kind = service.detailItem.type
      if (["show", "audiobook"].indexOf(kind) < 0
          || (service.detailItems && service.detailItems.length > 0))
        actions.push("detail-play")
      actions.push("detail-save", "detail-more")
    }
    // Some pages list their own controls: Settings, Devices, search history.
    var page = pageLoader.item
    if (page && page.cursorActions) actions = actions.concat(page.cursorActions())
    var collections = pageCollections()
    for (var c = 0; c < collections.length; c++) {
      var collection = collections[c]
      if (collections.length === 1 && collection.showSort) actions.push("sort")
      actions.push(collection.keyboardListId || "list")
      if (collections.length === 1) {
        if (collection.hasMore) actions.push("more")
        if (collection.filterScanAvailable) actions.push("filter-scan")
      }
    }
    if (currentTab === "detail" && service && service.artistThisIsPlaylist
        && !artistScopedSearchActive && !showingUniversalSearch
        && service.detailItem && service.detailItem.type === "artist")
      actions.push("detail-thisis")
    return actions
  }

  function sleepCursorActions() {
    var actions = ["sleep-15", "sleep-30", "sleep-60", "sleep-120",
      "sleep-track", "sleep-context"]
    if (service && service.sleepActive) actions.push("sleep-cancel")
    return actions
  }

  function panelCursorRegions() {
    // Only the player is on screen while Now playing fills the window.
    if (nowPlayingExpanded) return ["footer"]
    var regions = []
    if (sidebarCursorActions().length) regions.push("sidebar")
    regions.push("header")
    if (pageCursorActions().length) regions.push("page")
    if (footerCursorActions().length) regions.push("footer")
    return regions
  }

  function regionCursorActions(region) {
    if (region === "sidebar") return sidebarCursorActions()
    if (region === "header") return headerCursorActions()
    if (region === "page") return pageCursorActions()
    if (region === "footer") return footerCursorActions()
    if (region === "popup") {
      if (mediaContextMenu.opened) return contextMenuCursorActions()
      return sleepCursorActions()
    }
    return []
  }

  function ensurePanelCursor(preferredRegion) {
    var region = preferredRegion || panelCursorRegion
    if (popupCursorOpen) region = "popup"
    var regions = panelCursorRegions()
    if (popupCursorOpen) regions = ["popup"]
    region = Api.ensureCursorAction(regions, region,
      preferredRegion || "footer")
    panelCursorRegion = region
    var fallback = region === "footer" ? "play" : ""
    panelCursorAction = Api.ensureCursorAction(regionCursorActions(region),
      panelCursorAction, fallback)
    scheduleCursorRefresh()
  }

  function setPanelCursor(region, action) {
    if (panelCursorActive && panelCursorFromPointer && panelCursorRegion === region
        && panelCursorAction === action) return
    panelCursorActive = true
    panelCursorFromPointer = true
    panelCursorRegion = region
    panelCursorAction = action
    ensurePanelCursor(region)
    syncCursorFocus()
  }

  function movePanelCursorRegion(delta) {
    latchShortcutMode()
    showKeyboardCursor()
    var regions = panelCursorRegions()
    panelCursorRegion = Api.moveCursorAction(regions, panelCursorRegion, delta)
    ensurePanelCursor(panelCursorRegion)
    syncCursorFocus()
  }

  function moveSidebarPlaylists(delta) {
    var list = sidebarListView
    var next = Api.listIndexAfterMove(list.count, list.currentIndex, delta)
    if (next < 0) return false
    list.currentIndex = next
    list.positionViewAtIndex(next, list.Contain === undefined ? 2 : list.Contain)
    return true
  }

  function movePageList(delta) {
    var collection = collectionForListAction(panelCursorAction)
    return collection && collection.moveCurrent ? collection.moveCurrent(delta) : false
  }

  function enterListAction(action, delta) {
    if (action === "sidebar-playlists" && sidebarListView.count > 0) {
      sidebarListView.currentIndex = delta < 0
        ? sidebarListView.count - 1 : 0
      return
    }
    if (!Api.isCursorListAction(action)) return
    var collection = collectionForListAction(action)
    if (collection && collection.jumpToEdge) collection.jumpToEdge(delta < 0)
  }

  function movePanelCursor(delta) {
    latchShortcutMode()
    showKeyboardCursor()
    ensurePanelCursor()
    var from = panelCursorAction
    var to = Api.moveCursorAction(
      regionCursorActions(panelCursorRegion), panelCursorAction, delta)
    if (from !== to) enterListAction(to, delta)
    panelCursorAction = to
    ensurePanelCursor()
    syncCursorFocus()
  }

  function blurPageLists() {
    var collections = pageCollections()
    for (var i = 0; i < collections.length; i++) {
      if (collections[i] && collections[i].blurList) collections[i].blurList()
    }
  }

  function syncCursorFocus() {
    if (!panelCursorActive || typingInField) return
    if (panelCursorAction === "sidebar-playlists") {
      if (sidebarListView.currentIndex < 0 && sidebarListView.count > 0)
        sidebarListView.currentIndex = 0
      blurPageLists()
      focusScope.forceActiveFocus()
      return
    }
    if (Api.isCursorListAction(panelCursorAction)) {
      var collection = collectionForListAction(panelCursorAction)
      if (collection && collection.focusList) collection.focusList()
      return
    }
    blurPageLists()
    focusScope.forceActiveFocus()
  }

  function scheduleCursorRefresh() {
    Qt.callLater(refreshCursorState)
  }

  function refreshCursorState() {
    var latched = shortcutHintsEnabled && shortcutModeLatched
    var hintsOn = shortcutHintsActive
    var collections = pageCollections()
    var tab = latched ? tabDestination(false) : ({})
    var back = latched ? tabDestination(true) : ({})
    var current = latched ? collectionForListAction(
      Api.isCursorListAction(panelCursorAction) ? panelCursorAction : "list") : null
    if (latched) cursorNav = {
      tab: tab,
      back: back,
      regionActions: regionCursorActions(panelCursorRegion),
      sidebarIndex: sidebarListView.currentIndex,
      sidebarCount: sidebarListView.count,
      pageIndex: current ? current.listCurrentIndex : -1,
      pageCount: current ? current.listCount : 0
    }
    var actions = hintsOn ? pageCursorActions() : []
    var shown = keyboardCursorShown
    for (var i = 0; i < collections.length; i++) {
      var collection = collections[i]
      var id = collection.keyboardListId || "list"
      var prev = hintsOn ? Api.moveCursorAction(actions, id, -1) : ""
      var next = hintsOn ? Api.moveCursorAction(actions, id, 1) : ""
      collection.cursorHost = root
      collection.keyboardCursorShown = shown
      collection.keyboardHintsActive = hintsOn
      collection.keyboardSortSelected = cursorShown("page", "sort")
      collection.keyboardMoreSelected = cursorShown("page", "more")
      collection.keyboardFilterScanSelected = cursorShown("page", "filter-scan")
      collection.keyboardFilterScanHint = hintsOn ? navHintFor("page", "filter-scan") : ""
      collection.keyboardSortHint = hintsOn ? navHintFor("page", "sort") : ""
      collection.keyboardMoreHint = hintsOn ? navHintFor("page", "more") : ""
      collection.keyboardAtList = cursorOn("page", id)
      collection.keyboardAtListPrev = hintsOn && cursorOn("page", prev)
        && !Api.isCursorListAction(prev)
      collection.keyboardAtListNext = hintsOn && cursorOn("page", next)
        && !Api.isCursorListAction(next)
      collection.keyboardListIsTab = hintsOn && tab.region === "page"
        && tab.action === id
      collection.keyboardListIsBacktab = hintsOn && back.region === "page"
        && back.action === id
      collection.keyboardNavModifiers = hintCtrlHeld || hintShiftHeld
        || hintAltHeld
      collection.keyboardCtrlHeld = hintCtrlHeld
      collection.keyboardShiftHeld = hintShiftHeld
      collection.keyboardAltHeld = hintAltHeld
    }
  }

  function activatePanelCursor() {
    latchShortcutMode()
    showKeyboardCursor()
    ensurePanelCursor()
    var action = panelCursorAction
    if (action === "nav-home") chooseTab("home")
    else if (action === "nav-search") { chooseTab("search"); focusSearch() }
    else if (action === "nav-discover") chooseTab("discover")
    else if (action === "nav-radio") openLastRadio()
    else if (action === "nav-queue") chooseTab("queue")
    else if (action === "nav-nowplaying") toggleNowPlayingExpanded()
    else if (action === "nav-stats") chooseTab("stats")
    else if (action === "nav-create") openCreatePlaylistPopup()
    else if (action === "lib-filter") cycleLibraryFilter()
    else if (action === "lib-sort") cycleLibrarySort()
    else if (action === "lib-view") cycleLibraryView()
    else if (action === "sidebar-playlists") {
      var rows = service ? service.sidebarItems : []
      openSidebarItem(rows[sidebarListView.currentIndex])
    } else if (action.indexOf("nav-") === 0) chooseTab(action.substring(4))
    else if (action === "back") goBack()
    else if (action === "search") focusSearch()
    else if (action === "scope") toggleSearchScope()
    else if (action === "help") toggleShortcutHelp()
    else if (action === "filter-scan") {
      var scanning = pageCollection()
      if (scanning) {
        if (scanning.filterScanPaused) scanning.continueFilterScan()
        else scanning.cancelFilterScan()
      }
    }
    else if (action === "retry-search" && service) service.retrySearch(searchType)
    else if (action === "refresh") refreshCurrentView()
    else if (action === "queue-refresh" && service) service.loadQueue()
    else if (action.indexOf("stats-") === 0 && service)
      service.setStatsRange(action.substring(6))
    else if (pageLoader.item && pageLoader.item.activateCursorAction
        && pageLoader.item.activateCursorAction(action)) return
    else if (action === "close") requestClose()
    else if (action === "like" && service) service.toggleCurrentTrackSaved()
    else if (action === "context") openNowPlayingContext()
    else if (action === "artist") openCurrentArtist()
    else if (action === "album") openCurrentAlbum()
    else if (action === "shuffle" && service)
      service.setShuffle(!service.shuffle)
    else if (action === "previous" && service) service.previous()
    else if (action === "back15" && service) service.skipBySeconds(-15)
    else if (action === "forward30" && service) service.skipBySeconds(30)
    else if (action === "play" && service) service.togglePlayback()
    else if (action === "next" && service) service.next()
    else if (action === "repeat" && service) service.cycleRepeat()
    else if (action === "lyrics") openLyrics()
    else if (action === "expand") toggleNowPlayingExpanded()
    else if (action === "devices") chooseTab("devices")
    else if (action === "sleep") openSleepPopup()
    else if (action === "volume") toggleMute()
    else if (action === "releases-more" && service) {
      if (service.releaseFeed.error) service.retryReleaseFeed()
      else service.releaseFeed.load()
    }
    else if (action.indexOf("home-") === 0) homeType = action.substring(5)
    else if (action.indexOf("library-") === 0) {
      libraryType = action.substring(8)
      if (service) service.loadLibrary(libraryType, false)
    } else if (action.indexOf("search-") === 0) {
      selectSearchType(action.substring(7))
    } else if (action === "playlist-play" && service && service.selectedPlaylist)
      playSelectedPlaylist()
    else if (action === "playlist-more" && service && service.selectedPlaylist)
      openMediaContext(service.selectedPlaylist, Style.space(80),
        Style.space(120), [], service.selectedPlaylist.uri, -1)
    else if (action === "sort") {
      var sortCollection = pageCollection()
      if (sortCollection) sortCollection.cycleSort()
    } else if (action === "detail-play" && service && service.detailItem) {
      if (["show", "audiobook"].indexOf(service.detailItem.type) >= 0
          && service.detailItems && service.detailItems.length)
        activateMedia(service.detailItems[0], service.detailItems, "")
      else activateMedia(service.detailItem)
    } else if (action === "detail-save" && service && service.detailItem) {
      if (!service.isSaved(service.detailItem))
        service.toggleSaved(service.detailItem)
    } else if (action === "detail-more" && service && service.detailItem) {
      openMediaContext(service.detailItem, Style.space(80), Style.space(120),
        service.detailItems || [], service.detailItem.uri, -1)
    } else if (action === "detail-thisis") {
      var thisIs = findNamedItem(pageLoader.item, "artist-thisis")
      if (thisIs && thisIs.triggerPrimary) thisIs.triggerPrimary()
    } else if (String(action).indexOf("ctx-") === 0) {
      activateContextMenuAction(action)
    } else if (Api.isCursorListAction(action)) {
      var current = collectionForListAction(action)
      if (current && current.activateCurrent) current.activateCurrent()
    } else if (action === "more") {
      var more = pageCollection()
      if (more && more.requestMore) more.requestMore()
    } else if (action === "sleep-15" && service) {
      service.setSleepMinutes(15)
      sleepPopup.close()
    } else if (action === "sleep-30" && service) {
      service.setSleepMinutes(30)
      sleepPopup.close()
    } else if (action === "sleep-60" && service) {
      service.setSleepMinutes(60)
      sleepPopup.close()
    } else if (action === "sleep-120" && service) {
      service.setSleepMinutes(120)
      sleepPopup.close()
    } else if (action === "sleep-track" && service) {
      service.sleepAfterTrack()
      sleepPopup.close()
    } else if (action === "sleep-context" && service) {
      service.sleepAfterContext()
      sleepPopup.close()
    } else if (action === "sleep-cancel" && service) {
      service.cancelSleepTimer(true)
      sleepPopup.close()
    }
  }

  function openPanelListContext() {
    var action = Api.isCursorListAction(panelCursorAction)
      ? panelCursorAction : "list"
    var collection = collectionForListAction(action)
    if (collection && collection.currentContextAnchor) {
      if (collection.listCurrentIndex < 0 && collection.focusList)
        collection.focusList()
      var anchor = collection.currentContextAnchor()
      if (anchor && anchor.item) {
        openMediaContext(anchor.item, anchor.x, anchor.y, anchor.items,
          anchor.uri, anchor.index, anchor.playbackUri)
        return true
      }
    }
    return false
  }

  function openSidebarContext(item, sceneX, sceneY) {
    if (!item) return false
    openMediaContext(item, sceneX, sceneY, [], item.uri, -1)
    contextFromSidebar = true
    return true
  }

  function togglePinnedContextItem() {
    if (service && contextItem) service.togglePinnedItem(contextItem)
  }

  function nowPlayingContextItem() {
    if (!service || !service.currentTrackItem) return null
    var item = Api.shallowCopy(service.currentTrackItem)
    if (service.currentArtists.length) item.artists = service.currentArtists
    if (service.currentAlbumItem) item.albumItem = service.currentAlbumItem
    return item
  }

  function openNowPlayingContext() {
    var item = nowPlayingContextItem()
    if (!item) return false
    var x = Style.space(80)
    var y = Math.max(Style.space(8), window.height - Style.space(160))
    var anchor = playerFooter.contextAnchor()
    if (anchor) {
      var point = anchor.mapToItem(window.contentItem, anchor.width, 0)
      x = point.x
      y = point.y
    }
    openMediaContext(item, x, y, [item], item.uri, 0)
    return true
  }

  function openCurrentContextMenu() {
    if (panelCursorAction === "playlist-more"
        || panelCursorAction === "detail-more") {
      activatePanelCursor()
      return mediaContextMenu.opened
    }
    if (panelCursorAction === "sidebar-playlists" && service) {
      var entry = service.sidebarItems[sidebarListView.currentIndex]
      var row = sidebarListView.currentItem
      var point = row ? row.mapToItem(null, row.width / 2, row.height / 2)
        : ({ x: Style.space(80), y: Style.space(120) })
      return openSidebarContext(entry, point.x, point.y)
    }
    if (panelCursorRegion === "page"
        || Api.isCursorListAction(panelCursorAction)) {
      if (openPanelListContext()) return true
    }
    return openNowPlayingContext()
  }

  function contextMenuButtons() {
    var result = []
    var kids = mediaContextMenu.actionButtons()
    for (var i = 0; i < kids.length; i++) {
      var child = kids[i]
      var action = child && child.contextAction ? String(child.contextAction) : ""
      if (!action || child.visible === false || child.enabled === false) continue
      result.push(child)
    }
    return result
  }

  function contextMenuCursorActions() {
    var buttons = contextMenuButtons()
    var actions = []
    for (var i = 0; i < buttons.length; i++)
      actions.push(buttons[i].contextAction)
    return actions
  }

  function activateContextMenuAction(action) {
    var buttons = contextMenuButtons()
    for (var i = 0; i < buttons.length; i++) {
      if (buttons[i].contextAction === action) {
        buttons[i].clicked()
        return true
      }
    }
    return false
  }

  function contextMenuMoveDelta(event) {
    if (!event) return 0
    var key = event.key
    var text = String(event.text || "").toLowerCase()
    if (key === Qt.Key_Up || key === Qt.Key_K || key === Qt.Key_Left
        || key === Qt.Key_H || text === "k" || text === "h")
      return -1
    if (key === Qt.Key_Down || key === Qt.Key_J || key === Qt.Key_Right
        || key === Qt.Key_L || text === "j" || text === "l")
      return 1
    return 0
  }

  function moveContextMenuCursor(delta) {
    if (!mediaContextMenu.opened || !delta) return false
    latchShortcutMode()
    showKeyboardCursor()
    panelCursorRegion = "popup"
    panelCursorAction = Api.moveCursorAction(contextMenuCursorActions(),
      panelCursorAction, delta)
    ensurePanelCursor("popup")
    return true
  }

  function handleContextMenuKey(event) {
    if (!mediaContextMenu.opened || !event) return false
    var key = event.key
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var tabbing = key === Qt.Key_Tab || key === Qt.Key_Backtab
      || key === Qt.Key_F6
    var move = contextMenuMoveDelta(event)
    if (tabbing) {
      latchShortcutMode()
      showKeyboardCursor()
      panelCursorRegion = "popup"
      panelCursorAction = Api.moveCursorAction(contextMenuCursorActions(),
        panelCursorAction, (shift || key === Qt.Key_Backtab) ? -1 : 1)
      ensurePanelCursor("popup")
      return true
    }
    if (move) return moveContextMenuCursor(move)
    if (key === Qt.Key_Return || key === Qt.Key_Enter) {
      latchShortcutMode()
      activatePanelCursor()
      return true
    }
    if (key === Qt.Key_Home || key === Qt.Key_End) {
      latchShortcutMode()
      showKeyboardCursor()
      panelCursorRegion = "popup"
      var actions = contextMenuCursorActions()
      if (actions.length) {
        panelCursorAction = key === Qt.Key_Home
          ? actions[0] : actions[actions.length - 1]
        ensurePanelCursor("popup")
      }
      return true
    }
    return false
  }

  function handlePanelCursorKey(event) {
    if (!event) return false
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0
    var key = event.key
    var text = String(event.text || "").toLowerCase()
    var tabbing = key === Qt.Key_Tab || key === Qt.Key_Backtab
      || key === Qt.Key_F6
    var menuKey = key === Qt.Key_Menu || (shift && key === Qt.Key_F10)
      || (!ctrl && !shift && !alt && (key === Qt.Key_C || text === "c"))

    if (mediaContextMenu.opened)
      return handleContextMenuKey(event)

    if (createPlaylistPopup.opened || playlistPicker.opened
        || shortcutHelpPopup.opened || lyricsInstallPopup.opened || confirmPopup.opened)
      return false

    if (unifiedSearchField.activeFocus && tabbing) {
      var searchDest = tabDestination(shift || key === Qt.Key_Backtab)
      releaseSearchFocus()
      applyCursorDestination(searchDest)
      return true
    }

    if (typingInField) return false

    if (ctrl && !shift && !alt && (key === Qt.Key_Up || key === Qt.Key_Down)
        && service && service.volumeSupported) {
      latchShortcutMode(key === Qt.Key_Up ? "Ctrl+Up" : "Ctrl+Down")
      adjustVolume(key === Qt.Key_Up ? 0.05 : -0.05)
      return true
    }

    if (sleepPopup.opened) {
      if (tabbing) {
        applyTabDestination(shift || key === Qt.Key_Backtab)
        return true
      }
      if (key === Qt.Key_Down || key === Qt.Key_Up
          || text === "j" || text === "k" || key === Qt.Key_Left
          || key === Qt.Key_Right || text === "h" || text === "l") {
        latchShortcutMode()
        showKeyboardCursor()
        panelCursorRegion = "popup"
        var sleepDelta = (key === Qt.Key_Up
          || text === "k" || key === Qt.Key_Left || text === "h") ? -1 : 1
        panelCursorAction = Api.moveCursorAction(sleepCursorActions(),
          panelCursorAction, sleepDelta)
        ensurePanelCursor("popup")
        return true
      }
      if (key === Qt.Key_Return || key === Qt.Key_Enter) {
        activatePanelCursor()
        return true
      }
      return false
    }

    if (tabbing) {
      latchShortcutMode()
      if (!panelCursorActive) {
        showKeyboardCursor()
        ensurePanelCursor("footer")
        syncCursorFocus()
        return true
      }
      applyTabDestination(shift || key === Qt.Key_Backtab)
      return true
    }

    var vertical = key === Qt.Key_Up || key === Qt.Key_Down || text === "k"
      || text === "j"
    var horizontal = key === Qt.Key_Left || key === Qt.Key_Right
      || text === "h" || text === "l"
    var delta = (key === Qt.Key_Up || text === "k" || key === Qt.Key_Left
      || text === "h") ? -1 : 1

    if (!ctrl && !alt && !(shift && (key === Qt.Key_Left || key === Qt.Key_Right
          || key === Qt.Key_Up || key === Qt.Key_Down))
        && (vertical || horizontal) && (panelCursorActive
        || key === Qt.Key_Up || key === Qt.Key_Down || key === Qt.Key_Left
        || key === Qt.Key_Right)) {
      latchShortcutMode()
      var leftByPointer = panelCursorActive && panelCursorFromPointer
      showKeyboardCursor()
      ensurePanelCursor()
      // The first key only shows a cursor the pointer left behind.
      if (leftByPointer) return true
      if (horizontal && !ctrl && !alt && pageLoader.item && pageLoader.item.adjustCursorAction
          && pageLoader.item.adjustCursorAction(panelCursorAction, delta)) return true
      if (!ctrl && !alt && (panelCursorAction === "seek"
          || panelCursorAction === "volume") && horizontal) {
        if (panelCursorAction === "seek") seekBy(delta * 5)
        else adjustVolume(delta * 0.05)
        return true
      }
      if (panelCursorAction === "sidebar-playlists" && libraryViewIsGrid
          && (vertical || horizontal)
          && moveSidebarPlaylists(vertical ? delta * sidebarListView.columns : delta))
        return true
      if (vertical && panelCursorAction === "sidebar-playlists"
          && moveSidebarPlaylists(delta))
        return true
      if (vertical && Api.isCursorListAction(panelCursorAction)
          && movePageList(delta)) return true
      movePanelCursor(delta)
      return true
    }

    if (panelCursorActive && (key === Qt.Key_Return || key === Qt.Key_Enter)) {
      if (panelCursorFromPointer) showKeyboardCursor()
      else activatePanelCursor()
      return true
    }
    if (menuKey && openCurrentContextMenu()) {
      latchShortcutMode()
      return true
    }
    if (panelCursorActive && !ctrl && !alt && !shift
        && (key === Qt.Key_Home || key === Qt.Key_End)) {
      showKeyboardCursor()
      var actions = regionCursorActions(panelCursorRegion)
      if (actions.length) {
        panelCursorAction = key === Qt.Key_Home
          ? actions[0] : actions[actions.length - 1]
        syncCursorFocus()
      }
      return true
    }
    return false
  }

  function primaryNavigationShortcut(id) {
    if (id === "home") return "Alt+Shift+H"
    if (id === "queue") return "Alt+Shift+Q"
    if (id === "nowplaying") return "Alt+Shift+N"
    if (id === "stats") return "Alt+Shift+I"
    return ""
  }

  function shortcutRows() {
    var rows = [
      { section: "SEARCH", action: "Search all of Spotify", keys: "Ctrl+F or /" },
      { action: "Toggle current area / all of Spotify", keys: "Ctrl+F or / again" },
      { action: "Leave search", keys: "Esc" },
      { section: "NAVIGATION", action: "Go back", keys: "Alt+Left" },
      { action: "Leave Settings or Devices", keys: "Esc" },
      { action: "Open Settings", keys: "Ctrl+," },
      { action: "Open For You", keys: "Alt+Shift+H" },
      { action: "Open Queue", keys: "Alt+Shift+Q" },
      { action: "Open or close Now playing", keys: "E or Alt+Shift+N" },
      { action: "Change the equalizer style in Now playing", keys: "V" },
      { action: "Open Your listening", keys: "Alt+Shift+I" },
      { action: "Open Devices", keys: "Alt+Shift+D" },
      { action: "Open the current artist", keys: "Ctrl+Shift+A" },
      { action: "Open the current album", keys: "Ctrl+Shift+B" },
      { action: "Move between sidebar, search, the song list, and the player", keys: "Tab / F6" },
      { action: "Move to a control", keys: "Arrow keys" },
      { action: "Activate the highlighted control", keys: "Enter" },
      { action: "Row actions", keys: "C" },
      { action: "Choose a row action", keys: "Arrow keys or Enter" },
      { action: "Move through lists", keys: "Arrow keys" },
      { action: "Open the selected item", keys: "Enter" },
      { section: "PLAYBACK", action: "Play or pause", keys: "Space" },
      { action: "Previous track", keys: "Ctrl+Left" },
      { action: "Next track", keys: "Ctrl+Right" },
      { action: "Open lyrics in Omasing", keys: "Ctrl+Shift+L" },
      { action: "Mute or restore volume", keys: "M" },
      { action: "Toggle shuffle", keys: "Ctrl+S" },
      { action: "Cycle repeat", keys: "Ctrl+R" },
      { action: "Seek back 10 seconds", keys: "Shift+Left" },
      { action: "Seek forward 10 seconds", keys: "Shift+Right" },
      { action: "Raise volume 5%", keys: "Ctrl+Up" },
      { action: "Lower volume 5%", keys: "Ctrl+Down" },
      { section: "WINDOW", action: "Arm close / close", keys: "Esc, Esc" },
      { action: "Hide visible shortcut hints", keys: "Ctrl+H" },
      { action: "Show this reference", keys: "Ctrl+/" }
    ]
    if (!service || !service.showLyrics)
      rows = rows.filter(function(row) { return row.keys !== "Ctrl+Shift+L" })
    return rows
  }

  function scopedSearchText() {
    if (currentTab === "home") return homeFilter
    if (currentTab === "discover") return discoverFilter
    if (currentTab === "library") return libraryFilter
    if (currentTab === "playlists") return playlistFilter
    if (currentTab === "queue") return queueFilter
    if (currentTab === "detail") return activeSearchScope.mode === "artist"
      ? artistSearchText : detailFilter
    return ""
  }

  function setScopedSearchText(value) {
    var text = String(value || "")
    if (currentTab === "home") homeFilter = text
    else if (currentTab === "discover") discoverFilter = text
    else if (currentTab === "library") libraryFilter = text
    else if (currentTab === "playlists") playlistFilter = text
    else if (currentTab === "queue") queueFilter = text
    else if (currentTab === "detail") {
      if (activeSearchScope.mode === "artist") artistSearchText = text
      else detailFilter = text
    }
  }

  function unifiedSearchText() {
    return activeSearchScope.available && searchInContext
      ? scopedSearchText() : searchText
  }

  function searchScopeButtonText() {
    var label = activeSearchScope && activeSearchScope.label
      ? String(activeSearchScope.label) : "this area"
    if (label.length > 24) label = label.substring(0, 23) + "…"
    return "In " + label
  }

  function syncUnifiedSearchField() {
    if (!unifiedSearchField) return
    var next = unifiedSearchText()
    if (unifiedSearchField.text !== next)
      unifiedSearchField.text = next
  }

  function runUnifiedSearch(force) {
    unifiedSearchDelay.stop()
    if (!service) return
    if (activeSearchScope.available && searchInContext) {
      if (activeSearchScope.mode === "artist")
        service.findArtistMusic(artistSearchText)
      return
    }
    if (currentTab !== "search" && searchText.trim() !== "")
      universalSearchActive = true
    if (searchText.trim() === "") service.clearSearch()
    else service.search(searchText, searchType, force === true)
  }

  function editUnifiedSearch(value) {
    unifiedSearchDelay.stop()
    var text = String(value || "")
    if (activeSearchScope.available && searchInContext) {
      setScopedSearchText(text)
      if (activeSearchScope.mode === "artist") {
        if (text.trim() === "") {
          if (service) service.findArtistMusic("")
        } else {
          if (service) service.cancelArtistCatalog()
          unifiedSearchDelay.restart()
        }
      }
      return
    }
    searchText = text
    if (!service) return
    if (text.trim() === "") {
      service.clearSearch()
      if (currentTab !== "search") universalSearchActive = false
    } else {
      service.cancelSearch(false)
      unifiedSearchDelay.restart()
    }
  }

  function clearUnifiedSearch() {
    unifiedSearchDelay.stop()
    if (activeSearchScope.available && searchInContext) {
      setScopedSearchText("")
      if (activeSearchScope.mode === "artist" && service)
        service.findArtistMusic("")
    } else {
      searchText = ""
      if (service) service.clearSearch()
      if (currentTab !== "search") {
        universalSearchActive = false
        if (activeSearchScope.available) {
          searchInContext = true
          setScopedSearchText("")
          if (activeSearchScope.mode === "artist" && service)
            service.findArtistMusic("")
        }
      }
    }
    syncUnifiedSearchField()
  }

  function toggleSearchScope() {
    if (!activeSearchScope.available) return
    unifiedSearchDelay.stop()
    var text = unifiedSearchText()
    if (searchInContext) {
      searchText = text
      searchInContext = false
      universalSearchActive = true
      if (service) {
        if (searchText.trim() === "") service.clearSearch()
        else service.search(searchText, searchType)
      }
    } else {
      searchInContext = true
      universalSearchActive = false
      setScopedSearchText(text)
      if (service) {
        service.cancelSearch(false)
        if (activeSearchScope.mode === "artist")
          service.findArtistMusic(text)
      }
    }
    syncUnifiedSearchField()
    Qt.callLater(function() {
      unifiedSearchField.selectAll()
      unifiedSearchField.forceActiveFocus()
    })
  }

  // Popups live in their own files and hand focus back through this.
  function restoreFocus() {
    focusScope.forceActiveFocus()
  }

  // Focus without selecting, for the search-history chips.
  function focusSearchField() {
    unifiedSearchField.forceActiveFocus()
  }

  function focusSearch() {
    if (!unifiedSearchBar.visible) return
    unifiedSearchField.selectAll()
    unifiedSearchField.forceActiveFocus()
  }

  function activateSearch() {
    if (!unifiedSearchBar.visible) return
    var action = Api.searchShortcutAction(unifiedSearchField.activeFocus,
      activeSearchScope.available, searchInContext)
    if (action === "toggle-scope" || action === "enter-global")
      toggleSearchScope()
    else focusSearch()
  }

  function selectSearchType(type) {
    var value = Api.normalizedSearchType(type)
    if (searchType !== value) searchType = value
    if (service && showingUniversalSearch && searchText.trim() !== "")
      service.search(searchText, value)
  }

  function seekBy(seconds) {
    if (!service || !service.playbackControllable) return
    service.seekSeconds(Api.seekPosition(service.positionSeconds, seconds,
      service.lengthSeconds))
  }

  function setPanelVolume(value, live) {
    if (!service || !service.volumeSupported) return
    var next = Api.nextVolume(value, 0)
    if (Api.shouldRememberVolume(next)) volumeBeforeMute = next
    service.setVolume(next, live === true)
  }

  function adjustVolume(delta) {
    if (!service) return
    var now = Date.now()
    if (now - lastVolumeAdjustAt < 8) return
    lastVolumeAdjustAt = now
    setPanelVolume(Api.nextVolume(service.volume, delta))
  }

  function toggleMute() {
    if (!service || !service.volumeSupported) return
    var current = Api.nextVolume(service.volume, 0)
    if (Api.shouldRememberVolume(current)) {
      volumeBeforeMute = current
      service.setVolume(0)
    } else service.setVolume(Api.unmuteVolume(volumeBeforeMute))
  }

  function toggleShortcutHelp() {
    disarmEscapeClose()
    if (shortcutHelpPopup.opened) shortcutHelpPopup.close()
    else shortcutHelpPopup.open()
  }

  function openSleepPopup() {
    sleepPopup.open()
  }

  function openLyrics() {
    if (!service || !service.lyricsAvailable) return
    var result = service.requestLyrics(lyricsRequestKey)
    if (result !== "opening") lyricsInstallPopup.open()
  }

  function open(payloadJson) {
    searchClock = Date.now()
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) || ({}) } catch (e) {}
    if (shell && shell.bar
        && typeof shell.bar.hideBarWidget === "function")
      shell.bar.hideBarWidget(pluginId)
    var requestedTab = String(payload.tab || "")
    var requestedDetail = requestedTab === "detail" && payload.detailItem
      ? payload.detailItem : null
    restoreUiState(!requestedDetail)
    if (requestedDetail) {
      currentTab = "detail"
      navigationStack = []
      searchInContext = true
      universalSearchActive = false
      artistSearchText = ""
      detailFilter = ""
    } else if (["home", "discover", "search", "library", "playlists", "queue",
      "stats", "devices", "setup"].indexOf(requestedTab) >= 0)
      currentTab = requestedTab
    // Now playing covers the current page instead of replacing it.
    if (requestedTab) nowPlayingExpanded = requestedTab === "nowplaying"
    if (accountConnected) {
      openedForLogin = false
    } else if (!sessionPending) {
      currentTab = "login"
      universalSearchActive = false
      searchInContext = true
      openedForLogin = true
    }
    closingFromHost = false
    opened = true
    if (payload.shortcutLatch) {
      latchShortcutMode()
      showKeyboardCursor()
      ensurePanelCursor("footer")
    } else clearShortcutMode()
    syncDraftSettings()
    if (service) {
      service.setUiVisible("full-panel", true)
      service.activate(currentTab)
      restorePlaylistSelection()
      if (currentTab === "detail" && requestedDetail)
        service.openDetail(requestedDetail)
      if (currentTab === "search" && Api.searchNeedsLoad(searchText,
          service.searchResultQuery, service.searchLoadedTypes[searchType]))
        service.search(searchText, searchType)
    }
    Qt.callLater(function() {
      focusScope.forceActiveFocus()
    })
  }

  function close() {
    persistUiState()
    clearShortcutMode()
    closingFromHost = true
    opened = false
    if (service) {
      service.setUiVisible("full-panel", false)
      service.cancelSearch(false)
    }
    closingFromHost = false
  }

  function requestClose() {
    disarmEscapeClose()
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function rememberCurrentContentTab() {
    var remembered = Api.rememberContentTab(currentTab)
    if (remembered) lastContentTab = remembered
  }

  function leaveUtilityTab() {
    var destination = Api.previousContentTab(currentTab, lastContentTab)
    if (!destination) return false
    disarmEscapeClose()
    chooseTab(destination)
    return true
  }

  function chooseTab(tab) {
    nowPlayingExpanded = false
    if (!accountConnected) {
      currentTab = "login"
      openedForLogin = true
      return
    }
    var enteringSearch = currentTab !== "search" && tab === "search"
    disarmEscapeClose()
    unifiedSearchDelay.stop()
    if (showingUniversalSearch && tab !== "search" && service) service.cancelSearch(false)
    searchInContext = true
    universalSearchActive = false
    rememberCurrentContentTab()
    currentTab = tab
    if (tab !== "detail") navigationStack = []
    openedForLogin = false
    if (service) {
      service.openView(tab, false)
      if (tab === "playlists") restorePlaylistSelection()
      if (enteringSearch && Api.searchNeedsLoad(searchText,
          service.searchResultQuery, service.searchLoadedTypes[searchType]))
        service.search(searchText, searchType)
    }
    syncUnifiedSearchField()
  }

  function openLastRadio() {
    if (!service || !service.lastRadioPlaylist) return
    chooseTab("playlists")
    service.openPlaylist(service.lastRadioPlaylist)
  }

  function primaryNavigationItems() {
    var items = [
      { id: "home", label: "For you", icon: "󰎆" },
      { id: "search", label: "Search", icon: "󰍉" },
      { id: "discover", label: "Discover", icon: "󰲸" }
    ]
    if (service && service.lastRadioPlaylist) items.push({
      id: "radio",
      label: service.lastRadioPlaying ? "Current radio" : "Last radio",
      icon: "󰎆"
    })
    items.push({ id: "nowplaying", label: "Now playing", icon: "󰝚" })
    items.push({ id: "queue", label: "Queue", icon: "󰐕" })
    items.push({ id: "stats", label: "Listening", icon: "󰄨" })
    return items
  }

  function extraNarrowNavigationItems() {
    return [
      { id: "home", label: "For you", icon: "󰎆" },
      { id: "search", label: "Search", icon: "󰍉" },
      { id: "discover", label: "Discover", icon: "󰲸" },
      { id: "queue", label: "Queue", icon: "󰐕" },
      { id: "library", label: "Your Library", icon: "󰋑" },
      { id: "playlists", label: "Playlists", icon: "󱁐" },
      { id: "devices", label: "Devices", icon: "󰋋" },
      { id: "setup", label: "Settings", icon: "󰒓" }
    ]
  }

  function radioNavigationSelected() {
    return currentTab === "playlists" && service && service.lastRadioPlaylist
      && service.selectedPlaylist
      && String(service.selectedPlaylist.id) === String(service.lastRadioPlaylist.id)
  }

  function updateLoginGate() {
    if (!opened) return
    if (sessionPending) return
    if (!accountConnected) {
      currentTab = "login"
      universalSearchActive = false
      searchInContext = true
      openedForLogin = true
      return
    }
    if (openedForLogin || currentTab === "login") {
      openedForLogin = false
      currentTab = "home"
      universalSearchActive = false
      searchInContext = true
      if (service) service.openView("home", false)
    }
  }

  // Track the combined service state directly. During the first login, the
  // Web API token and playback credential finish in separate event turns;
  // listening only to those nested objects can miss the final combined edge
  // while the panel loader is being remapped by the browser.
  onShortcutHintsEnabledChanged: if (!shortcutHintsEnabled) clearShortcutMode()
  onCurrentTabChanged: {
    root.rememberCurrentContentTab()
    if (panelCursorActive) ensurePanelCursor()
  }
  onPanelCursorActionChanged: scheduleCursorRefresh()
  onPanelCursorRegionChanged: scheduleCursorRefresh()
  onPanelCursorActiveChanged: scheduleCursorRefresh()
  onPanelCursorVisibleChanged: scheduleCursorRefresh()
  onPanelCursorFromPointerChanged: scheduleCursorRefresh()
  onShortcutHintsActiveChanged: scheduleCursorRefresh()
  onShortcutModeLatchedChanged: scheduleCursorRefresh()
  onHeldModifierFlagsChanged: scheduleCursorRefresh()
  onPlaylistShortcutIndexChanged: scheduleCursorRefresh()
  onSearchFieldFocusedChanged: scheduleCursorRefresh()
  onArtistScopedSearchActiveChanged: scheduleCursorRefresh()
  onFullyConnectedChanged: Qt.callLater(function() { root.updateLoginGate() })
  onAccountConnectedChanged: Qt.callLater(function() { root.updateLoginGate() })
  onSessionPendingChanged: Qt.callLater(function() { root.updateLoginGate() })
  onServiceChanged: Qt.callLater(function() { root.updateLoginGate() })


  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onPlaylistsChanged() { root.restorePlaylistSelection() }
    function onRadioPlaylistReady(playlist) {
      if (!playlist || !root.service) return
      root.openLastRadio()
    }
  }

  function pageComponent() {
    if (currentTab === "login") return loginPage
    if (showingUniversalSearch) return searchPage
    if (currentTab === "setup") return setupPage
    if (currentTab === "home") return homePage
    if (currentTab === "discover") return discoverPage
    if (currentTab === "library") return libraryPage
    if (currentTab === "playlists") return playlistsPage
    if (currentTab === "detail") return detailPage
    if (currentTab === "stats") return statsPage
    if (currentTab === "queue") return queuePage
    if (currentTab === "devices") return devicesPage
    return searchPage
  }

  function pageTitle() {
    if (currentTab === "login") return "Log in to Spotify"
    if (showingUniversalSearch) return "Search Spotify"
    if (currentTab === "home") return "For you"
    if (currentTab === "discover") return "Discover"
    if (currentTab === "library") return "Your Library"
    if (currentTab === "playlists") return "Playlists"
    if (currentTab === "stats") return "Your listening"
    if (currentTab === "queue") return "Queue"
    if (currentTab === "devices") return "Spotify Connect"
    if (currentTab === "setup") return "Settings"
    if (currentTab === "detail") {
      if (artistScopedSearchActive) return "Search in " + service.detailItem.name
      return service && service.detailItem ? service.detailItem.name : "Loading…"
    }
    return "Search"
  }


  function libraryFilterName(mode) {
    if (mode === "playlist") return "Playlists"
    if (mode === "artist") return "Artists"
    if (mode === "album") return "Albums"
    if (mode === "show") return "Podcasts"
    return "Everything"
  }

  function nextInCycle(modes, current) {
    return modes[(modes.indexOf(current) + 1) % modes.length]
  }

  function libraryFilterLabel() {
    return libraryFilterName(service ? service.libraryFilter : "all")
  }

  function nextLibraryFilterLabel() {
    return libraryFilterName(nextInCycle(Api.libraryFilterModes(),
      service ? service.libraryFilter : "all"))
  }

  function libraryFilterIcon() {
    if (!service) return "󰈲"
    var mode = service.libraryFilter
    if (mode === "playlist") return "󰲸"
    if (mode === "artist") return "󰠃"
    if (mode === "album") return "󰀥"
    if (mode === "show") return "󰦔"
    return "󰈲"
  }

  function cycleLibraryFilter() {
    if (!service) return
    var modes = Api.libraryFilterModes()
    var at = modes.indexOf(service.libraryFilter)
    service.setLibraryFilter(modes[(at + 1) % modes.length])
  }

  function librarySortName(mode) {
    if (mode === "recent") return "Recents"
    if (mode === "added") return "Recently added"
    if (mode === "alpha") return "Alphabetical"
    return "Library order"
  }

  function librarySortLabel() {
    return librarySortName(service ? service.librarySort : "library")
  }

  function nextLibrarySortLabel() {
    return librarySortName(nextInCycle(Api.librarySortModes(),
      service ? service.librarySort : "library"))
  }

  function cycleLibrarySort() {
    if (!service) return
    var modes = Api.librarySortModes()
    var at = modes.indexOf(service.librarySort)
    service.setLibrarySort(modes[(at + 1) % modes.length])
  }

  function libraryViewIcon() {
    var mode = service ? service.libraryView : "list"
    if (mode === "compact-list") return "󰉹"
    if (mode === "grid") return "󰕰"
    if (mode === "compact-grid") return "󰀻"
    return "󰕲"
  }

  function libraryViewName(mode) {
    if (mode === "compact-list") return "Compact list"
    if (mode === "grid") return "Grid"
    if (mode === "compact-grid") return "Compact grid"
    return "List"
  }

  function libraryViewLabel() {
    return libraryViewName(service ? service.libraryView : "list")
  }

  function nextLibraryViewLabel() {
    return libraryViewName(nextInCycle(Api.libraryViewModes(),
      service ? service.libraryView : "list"))
  }

  function cycleLibraryView() {
    if (!service) return
    var modes = Api.libraryViewModes()
    var at = modes.indexOf(service.libraryView)
    service.setLibraryView(modes[(at + 1) % modes.length])
  }

  readonly property bool spokenWordPlaying: !!(service && service.currentIsSpokenWord)
  readonly property bool libraryViewIsGrid: service
    && service.libraryView.indexOf("grid") >= 0
  readonly property bool libraryViewIsCompact: service
    && service.libraryView.indexOf("compact") === 0
  readonly property int libraryRowHeight: libraryViewIsCompact
    ? Style.space(26) : Style.space(40)
  readonly property int libraryThumbSize: libraryViewIsCompact
    ? Style.space(20) : Style.space(32)

  function sidebarItemIcon(item) {
    if (item && item.pinned) return "󰐃"
    var type = item ? String(item.type || "playlist") : "playlist"
    if (type === "artist") return "󰠃"
    if (type === "album") return "󰀥"
    if (type === "show" || type === "episode") return "󰦔"
    return "󰲸"
  }

  function sidebarItemById(id) {
    var key = String(id || "")
    var rows = service ? service.sidebarPlaylists() : []
    for (var i = 0; i < rows.length; i++)
      if (rows[i] && String(rows[i].id || "") === key) return rows[i]
    return null
  }

  function openSidebarItem(item) {
    if (!item || !service) return
    if (String(item.type || "playlist") === "playlist") {
      chooseTab("playlists")
      service.openPlaylist(item)
      return
    }
    openItem(item)
  }

  function sidebarItemSelected(item) {
    if (!item || !service) return false
    if (currentTab === "playlists")
      return !!service.selectedPlaylist && service.selectedPlaylist.id === item.id
    return currentTab === "detail" && !!service.detailItem && service.detailItem.id === item.id
  }

  function sidebarItemPlaying(item) {
    if (!item || !item.uri || !service) return false
    var contextUri = service.remotePlayback ? service.remotePlayback.contextUri : ""
    if (contextUri) return contextUri === item.uri
    return !!service.currentAlbumItem && service.currentAlbumItem.uri === item.uri
  }

  function playlistOptions() {
    var playlists = service ? service.sidebarPlaylists() : []
    var options = []
    for (var i = 0; i < playlists.length; i++) {
      var playlist = playlists[i]
      if (!playlist || !playlist.id) continue
      options.push({
        value: String(playlist.id),
        label: String(playlist.name || "Playlist"),
        description: String(playlist.ownerName || "")
      })
    }
    return options
  }

  function openExternal(item) {
    if (item && item.externalUrl) Qt.openUrlExternally(item.externalUrl)
  }

  function copyExternal(item) {
    if (!item || !item.externalUrl) return
    Quickshell.execDetached(["wl-copy", String(item.externalUrl)])
    if (service) service.succeed("Spotify link copied")
  }

  function playlistPosition(item, sourceItems) {
    if (!service || !item || !contextPlaylist) return -1
    var source = sourceItems === undefined
      ? contextPlaylistItems() : Api.arrayValues(sourceItems)
    var occurrence = 0
    for (var shown = 0; shown < contextSourceIndex; shown++)
      if (contextSourceItems[shown] && contextSourceItems[shown].uri === item.uri) occurrence++
    for (var i = 0; i < source.length; i++) {
      if (source[i] && source[i].uri === item.uri) {
        if (occurrence === 0) return i
        occurrence--
      }
    }
    return -1
  }

  function contextPlaylistItems() {
    return Api.playlistBackingItems(contextPlaylist,
      service ? service.selectedPlaylist : null,
      service ? service.playlistItems : [],
      service ? service.detailItem : null,
      service ? service.detailItems : [])
  }

  function contextPlaylistMoveSpec(delta) {
    var items = contextPlaylistItems()
    var position = playlistPosition(contextItem, items)
    var direction = Number(delta) < 0 ? -1 : (Number(delta) > 0 ? 1 : 0)
    var destination = position >= 0 && direction
      ? Api.listIndexAfterMove(items.length, position, direction) : -1
    return {
      available: !!service && !!contextPlaylist && destination >= 0,
      playlist: contextPlaylist,
      position: position,
      direction: direction,
      count: items.length
    }
  }

  function moveContextPlaylistItem(delta) {
    var action = contextPlaylistMoveSpec(delta)
    var actionService = service
    if (!action.available || !actionService) return
    mediaContextMenu.close()
    actionService.movePlaylistItem(action.position, action.direction,
      action.playlist, action.count)
  }

  function openPlaylistPicker(item) {
    if (!item || item.kind !== "item") return
    pendingPlaylistItem = item
    playlistPicker.open()
  }

  function openCreatePlaylistPopup() {
    if (!service || !accountConnected) return
    createPlaylistName = ""
    createPlaylistPopup.open()
  }

  function createNamedPlaylist() {
    var name = String(createPlaylistName || "").trim()
    if (!service || !name || service.playlistActionBusy) return
    service.createPlaylist(name, function(playlist) {
      // A failure leaves the popup up with the name still in it, to try again.
      if (!playlist) return
      createPlaylistPopup.close()
      createPlaylistName = ""
      root.chooseTab("playlists")
      root.service.openPlaylist(playlist)
    })
  }

  Component.onDestruction: {
    if (service) {
      persistUiState()
      service.setUiVisible("full-panel", false)
      service.cancelSearch(false)
    }
  }

  ShortcutHelpPopup {
    id: shortcutHelpPopup
    panel: root
  }

  LyricsInstallPopup {
    id: lyricsInstallPopup
    panel: root
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onLyricsPluginPromptRequested(surface, availability) {
      if (String(surface) === root.lyricsRequestKey) lyricsInstallPopup.open()
    }
    function onLyricsPluginOpened(surface) {
      if (String(surface) === root.lyricsRequestKey) lyricsInstallPopup.close()
    }
  }

  MediaContextMenu {
    id: mediaContextMenu
    panel: root
  }

  PlaylistPicker {
    id: playlistPicker
    panel: root
  }

  CreatePlaylistPopup {
    id: createPlaylistPopup
    panel: root
  }

  SleepPopup {
    id: sleepPopup
    panel: root
  }

  ConfirmPopup {
    id: confirmPopup
    panel: root
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: "OmaSpotify"
    color: root.background
    implicitWidth: 980
    implicitHeight: 720
    minimumSize: Qt.size(Style.space(560), Style.space(440))

    onVisibleChanged: {
      if (!visible && root.opened && !root.closingFromHost) root.requestClose()
    }
    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      onActiveFocusChanged: if (!activeFocus) {
        root.heldModifierFlags = 0
        root.shortcutModeLatched = false
      }
      Keys.onShortcutOverride: function(event) {
        if (shortcutModifiers.isHintModifierKey(event.key) && !root.typingInField) {
          root.considerShortcutModeKey(event, true)
          event.accepted = true
          return
        }
        if (root.typingInField) return
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
            || event.key === Qt.Key_F6)
          event.accepted = true
        if (!root.shortcutsBlocked && root.service && root.service.volumeSupported
            && (event.modifiers & Qt.ControlModifier)
            && !(event.modifiers & Qt.ShiftModifier)
            && !(event.modifiers & Qt.AltModifier)
            && (event.key === Qt.Key_Up || event.key === Qt.Key_Down))
          event.accepted = true
      }
      Keys.onPressed: function(event) {
        root.considerShortcutModeKey(event, true)
        if (shortcutModifiers.isHintModifierKey(event.key) && !root.typingInField) {
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) return
        if (root.handlePanelCursorKey(event)) event.accepted = true
      }
      Keys.onReturnPressed: function(event) {
        if (root.handlePanelCursorKey(event)) event.accepted = true
      }
      Keys.onEnterPressed: function(event) {
        if (root.handlePanelCursorKey(event)) event.accepted = true
      }
      Keys.onReleased: function(event) {
        root.noteHeldModifiers(event, false)
        if (shortcutModifiers.isHintModifierKey(event.key) && !root.typingInField)
          event.accepted = true
      }
      Keys.onEscapePressed: function(event) {
        root.latchShortcutMode()
        if (root.dismissTransientPopup()) {
          root.disarmEscapeClose()
          event.accepted = true
          return
        }
        if (root.collapseNowPlaying()) {
          root.disarmEscapeClose()
          event.accepted = true
          return
        }
        if (root.dismissSearch()) {
          event.accepted = true
          return
        }
        if (root.typingInField) {
          root.releaseSearchFocus()
          event.accepted = true
          return
        }
        if (root.dismissFailure()) {
          root.disarmEscapeClose()
          event.accepted = true
          return
        }
        if (root.leaveUtilityTab()) {
          event.accepted = true
          return
        }
        if (root.currentTab === "detail" || root.navigationStack.length) {
          root.disarmEscapeClose()
          root.goBack()
        } else if (root.escapeCloseArmed) root.requestClose()
        else root.armEscapeClose()
        event.accepted = true
      }

      PanelShortcuts {
        panel: root
      }

      // A click anywhere else hands the keys back, so Space plays again.
      TapHandler {
        gesturePolicy: TapHandler.DragThreshold
        onTapped: if (root.searchFieldFocused) root.releaseSearchFocus()
      }

      Item {
        anchors.fill: parent
        anchors.margins: Style.space(12)

        Row {
          id: workspace
          visible: !nowPlayingView.visible
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: footerSeparator.top
          anchors.bottomMargin: Style.space(10)
          spacing: sidebar.visible ? Style.space(10) : 0

          PanelSidebar {
            id: sidebar
            panel: root
            visible: root.currentTab !== "login" && !root.extraNarrowWidth
            width: visible
              ? (root.compactWidth ? Style.space(54)
                : Math.min(Style.space(250), Math.max(Style.space(176), workspace.width * 0.23)))
              : 0
            height: parent.height
          }

          Item {
            id: contentPane
            width: Math.max(1, parent.width - sidebar.width - workspace.spacing)
            height: parent.height

            Row {
              id: extraNarrowNavigation
              visible: root.extraNarrowWidth && root.currentTab !== "login"
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: visible ? Style.space(32) : 0
              spacing: Style.space(2)

              Repeater {
                id: extraNarrowButtons
                model: root.extraNarrowNavigationItems()

                Button {
                  id: narrowNavButton
                  required property var modelData
                  width: Math.max(1, (extraNarrowNavigation.width - extraNarrowNavigation.spacing
                    * (extraNarrowButtons.count - 1)) / extraNarrowButtons.count)
                  height: extraNarrowNavigation.height
                  horizontalPadding: 0
                  verticalPadding: 0
                  foreground: root.foreground
                  selected: root.currentTab === modelData.id
                  tooltipText: modelData.label
                  focusable: false
                  hasCursor: root.cursorShown("sidebar", "nav-" + modelData.id)
                  onClicked: root.chooseTab(modelData.id)
                  onHovered: function(on) {
                    if (on) root.setPanelCursor("sidebar", "nav-" + narrowNavButton.modelData.id)
                  }

                  OpticalGlyph {
                    anchors.fill: parent
                    text: narrowNavButton.modelData.icon
                    color: narrowNavButton.selected
                      ? Style.selectedStateColor(root.foreground, root.accent)
                      : root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.icon
                  }
                }
              }
            }

            Item {
              id: pageHeader
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: extraNarrowNavigation.visible
                ? extraNarrowNavigation.bottom : parent.top
              anchors.topMargin: extraNarrowNavigation.visible ? Style.space(4) : 0
              height: Math.max(closeButton.implicitHeight, Style.space(30))

              Row {
                id: headerLeading
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Button {
                  id: backButton
                  visible: root.currentTab === "detail" || root.navigationStack.length > 0
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰁍"
                  foreground: root.foreground
                  tooltipText: root.shortcutHint("Back", "Alt+Left")
                  focusable: false
                  hasCursor: root.cursorShown("header", "back")
                  onClicked: root.goBack()
                  onHovered: function(on) { if (on) root.setPanelCursor("header", "back") }
                  KeyHint { region: "header"; action: "back"; sequences: ["Alt+Left"] }
                }

                Text {
                  id: pageTitleText
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, root.searchInline
                    ? Math.max(Style.space(100), contentPane.width * 0.3)
                    : Math.max(Style.space(80), pageHeader.width - headerActions.width
                      - (backButton.visible ? backButton.width + headerLeading.spacing : 0)
                      - Style.space(8)))
                  text: root.pageTitle()
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  elide: Text.ElideRight
                }
              }

              Row {
                id: headerActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Button {
                  id: shortcutHintsDismissButton
                  visible: root.shortcutHintsActive && !root.extraNarrowWidth
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Ctrl+H · Hide hints"
                  foreground: root.foreground
                  fontSize: Style.font.caption
                  focusable: false
                  tooltipText: "Hide shortcut hints until re-enabled in Settings · Ctrl+H"
                  onClicked: root.disableShortcutHints()
                }

                Button {
                  id: shortcutHelpButton
                  visible: !root.extraNarrowWidth
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰋖"
                  foreground: root.foreground
                  horizontalPadding: Style.space(7)
                  tooltipText: root.shortcutHint("Keyboard shortcuts", "Ctrl+/")
                  focusable: false
                  hasCursor: root.cursorShown("header", "help")
                  onClicked: root.toggleShortcutHelp()
                  onHovered: function(on) { if (on) root.setPanelCursor("header", "help") }
                  KeyHint { region: "header"; action: "help"; sequences: ["Ctrl+/"] }
                }

                Button {
                  id: refreshButton
                  visible: root.currentTab !== "login" && root.currentTab !== "setup"
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰑐"
                  iconSpinning: root.pageRefreshing
                  foreground: root.foreground
                  horizontalPadding: Style.space(7)
                  tooltipText: "Refresh"
                  focusable: false
                  hasCursor: root.cursorShown("header", "refresh")
                  onHovered: function(on) {
                    if (on) root.setPanelCursor("header", "refresh")
                  }
                  KeyHint { region: "header"; action: "refresh" }
                  onClicked: root.refreshCurrentView()
                }

                Button {
                  id: closeButton
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰅖"
                  foreground: root.escapeCloseArmed ? Commons.Color.urgent : root.foreground
                  horizontalPadding: Style.space(7)
                  bordered: root.escapeCloseArmed
                  borderSpec: root.escapeCloseArmed
                    ? Border.flat(Commons.Color.urgent, Math.max(1, Style.normalBorderWidth))
                    : closeButton._borderSpec
                  tooltipText: root.escapeCloseArmed
                    ? "Press Esc again to close"
                    : root.shortcutHint("Close", "Esc, Esc")
                  focusable: false
                  hasCursor: root.cursorShown("header", "close")
                  onClicked: root.requestClose()
                  onHovered: function(on) { if (on) root.setPanelCursor("header", "close") }
                  KeyHint { region: "header"; action: "close"; sequences: ["Esc"] }
                }
              }
            }

            // One field for the page you are on and for all of Spotify. It shares
            // the title row when there is room, and takes its own row when not.
            Item {
              id: unifiedSearchBar
              visible: root.currentTab !== "login" && root.currentTab !== "devices"
                && root.currentTab !== "setup" && root.currentTab !== "stats"
              anchors.left: parent.left
              anchors.leftMargin: root.searchInline ? headerLeading.width + Style.space(14) : 0
              anchors.right: parent.right
              anchors.rightMargin: root.searchInline ? headerActions.width + Style.space(10) : 0
              anchors.top: root.searchInline ? pageHeader.top : pageHeader.bottom
              anchors.topMargin: root.searchInline || !visible ? 0 : Style.space(6)
              height: visible ? Style.space(30) : 0

              TextField {
                id: unifiedSearchField
                anchors.fill: parent
                foreground: root.foreground
                leftPadding: Style.space(26)
                rightPadding: searchAccessories.width + Style.space(6)
                verticalPadding: Style.space(4)
                placeholderText: root.activeSearchScope.available && root.searchInContext
                  ? "Search in " + root.activeSearchScope.label : "Search Spotify"
                placeholderTextColor: root.muted
                enabled: root.service && root.service.auth.loggedIn
                hasCursor: root.cursorShown("header", "search")
                onTextEdited: root.editUnifiedSearch(text)
                onAccepted: root.runUnifiedSearch()

                Binding {
                  target: unifiedSearchField
                  property: "text"
                  value: root.unifiedSearchText()
                  when: !unifiedSearchField.activeFocus
                  restoreMode: Binding.RestoreNone
                }
                Keys.onPressed: function(event) {
                  var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                  var shift = (event.modifiers & Qt.ShiftModifier) !== 0
                  var alt = (event.modifiers & Qt.AltModifier) !== 0
                  if (event.key === Qt.Key_Escape) {
                    root.latchShortcutMode()
                    if (root.dismissSearch()) {
                      event.accepted = true
                      return
                    }
                  }
                  if (ctrl && !shift && !alt && event.key === Qt.Key_F) {
                    root.latchShortcutMode("Ctrl+F")
                    root.activateSearch()
                    event.accepted = true
                    return
                  }
                  if (!ctrl && !shift && !alt
                      && (event.key === Qt.Key_Slash || event.text === "/")) {
                    root.latchShortcutMode("/")
                    root.activateSearch()
                    event.accepted = true
                  }
                }

                PanelToolTip {
                  visible: unifiedSearchField.hovered
                  text: root.activeSearchScope.available
                    ? "Search all of Spotify · Ctrl+F or /\nPress again to search in "
                      + root.activeSearchScope.label
                    : "Search all of Spotify · Ctrl+F or /"
                }
                KeyHint { region: "header"; action: "search"; sequences: ["/", "Ctrl+F"] }
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: "󰍉"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }

              Row {
                id: searchAccessories
                anchors.right: parent.right
                anchors.rightMargin: Style.space(3)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Button {
                  id: searchClearButton
                  visible: unifiedSearchField.text !== ""
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰅖"
                  iconSize: Style.font.bodySmall
                  foreground: root.foreground
                  horizontalPadding: Style.space(5)
                  verticalPadding: Style.space(3)
                  focusable: false
                  tooltipText: "Clear · Esc"
                  onClicked: root.clearUnifiedSearch()
                }

                Button {
                  id: searchScopeButton
                  visible: root.activeSearchScope.available
                  width: visible ? Math.min(unifiedSearchBar.width * 0.42, implicitWidth) : 0
                  anchors.verticalCenter: parent.verticalCenter
                  clip: true
                  text: root.searchInContext ? root.searchScopeButtonText() : "All of Spotify"
                  fontSize: Style.font.bodySmall
                  foreground: root.foreground
                  selected: root.searchInContext
                  focusable: false
                  hasCursor: root.cursorShown("header", "scope")
                  onHovered: function(on) {
                    if (on) root.setPanelCursor("header", "scope")
                  }
                  horizontalPadding: Style.space(7)
                  verticalPadding: Style.space(2)
                  tooltipText: root.searchInContext
                    ? root.shortcutHint("Search all of Spotify", "Ctrl+F or /")
                    : root.shortcutHint("Search only in "
                      + root.activeSearchScope.label, "Ctrl+F or /")
                  onClicked: root.toggleSearchScope()
                  KeyHint {
                    region: "header"
                    action: "scope"
                    sequences: ["/", "Ctrl+F"]
                    active: root.shortcutHintsEnabled && root.shortcutModeLatched
                      && !root.shortcutsBlocked
                      && (root.shortcutHintsActive || unifiedSearchField.activeFocus)
                  }
                }
              }
            }

            Loader {
              id: pageLoader
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: unifiedSearchBar.visible && !root.searchInline
                ? unifiedSearchBar.bottom : pageHeader.bottom
              anchors.topMargin: root.pageGap
              anchors.bottom: parent.bottom
              sourceComponent: root.pageComponent()
              onLoaded: {
                pageFade.restart()
                root.scheduleCursorRefresh()
              }

              NumberAnimation {
                id: pageFade
                target: pageLoader
                property: "opacity"
                from: 0.2
                to: 1
                duration: Style.duration(120)
                easing.type: Easing.OutCubic
              }
            }

            PanelToast {
              panel: root
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(6)
              z: 40
            }
          }
        }

        NowPlayingPage {
          id: nowPlayingView
          panel: root
          visible: root.nowPlayingExpanded && root.currentTab !== "login"
          active: visible && window.visible
          onVisibleChanged: if (visible) nowPlayingFade.restart()
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: footerSeparator.top
          anchors.bottomMargin: Style.space(10)
        }

        NumberAnimation {
          id: nowPlayingFade
          target: nowPlayingView
          property: "opacity"
          from: 0
          to: 1
          duration: Style.duration(160)
          easing.type: Easing.OutCubic
        }

        PanelSeparator {
          id: footerSeparator
          visible: root.currentTab !== "login"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: playerFooter.top
          anchors.bottomMargin: Style.space(4)
          foreground: root.foreground
        }

        PlayerFooter {
          id: playerFooter
          panel: root
          visible: root.currentTab !== "login"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: visible ? Style.space(root.compactHeight ? 68 : 76) : 0
        }
      }
    }
  }

  ShortcutModifiers {
    id: shortcutModifiers
  }

  Timer {
    id: unifiedSearchDelay
    interval: Api.SEARCH_DEBOUNCE_MS
    repeat: false
    onTriggered: root.runUnifiedSearch()
  }

  Timer {
    id: escapeCloseTimer
    interval: 1500
    repeat: false
    onTriggered: root.escapeCloseArmed = false
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.opened && root.service && root.service.playing
    onTriggered: root.service.refreshPosition()
  }

  Component {
    id: homePage

    HomePage {
      panel: root
    }
  }

  Component {
    id: discoverPage

    DiscoverPage {
      panel: root
    }
  }

  Component {
    id: detailPage

    DetailPage {
      panel: root
    }
  }

  Component {
    id: searchPage

    SearchPage {
      panel: root
    }
  }

  Component {
    id: libraryPage

    LibraryPage {
      panel: root
    }
  }

  Component {
    id: playlistsPage

    PlaylistsPage {
      panel: root
    }
  }

  Component {
    id: statsPage

    StatsPage {
      panel: root
    }
  }

  Component {
    id: queuePage

    QueuePage {
      panel: root
    }
  }

  Component {
    id: devicesPage

    DevicesPage {
      panel: root
    }
  }

  Component {
    id: loginPage

    LoginPage {
      panel: root
    }
  }

  Component {
    id: setupPage

    SettingsPage {
      panel: root
    }
  }
}
