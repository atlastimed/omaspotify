pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

// The left column: where you can go, then everything in your library.
Item {
  id: part

  property var panel: null

  // The library is a list or a grid, never both. Everything the keyboard does
  // has to follow whichever one is on screen.
  readonly property var libraryView: part.panel && part.panel.libraryViewIsGrid
    ? playlistGrid : playlistList
  readonly property bool titleRowShown: !part.panel.compactHeight

  readonly property real compactRowHeight: Style.space(30)

  component NavGlyph: OpticalGlyph {
    anchors.fill: parent
    visible: part.panel.compactWidth
    fontFamily: part.panel.fontFamily
    fontSize: Style.font.icon
  }

  function noteLibraryPointer(view, index, scenePoint) {
    if (view.pointerSeen && (Math.abs(scenePoint.x - view.pointerX) > 1
        || Math.abs(scenePoint.y - view.pointerY) > 1)) {
      view.currentIndex = index
      if (part.panel.panelCursorAction !== "sidebar-playlists"
          || !part.panel.panelCursorFromPointer)
        part.panel.setPanelCursor("sidebar", "sidebar-playlists")
    }
    view.pointerSeen = true
    view.pointerX = scenePoint.x
    view.pointerY = scenePoint.y
  }

  Row {
    id: brandRow
    visible: part.titleRowShown
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: visible ? Style.space(2) : 0
    height: visible ? Style.space(26) : 0
    spacing: Style.space(8)

    OpticalGlyph {
      width: part.panel.compactWidth ? parent.width : Style.space(18)
      height: parent.height
      text: ""
      color: part.panel.accent
      fontFamily: part.panel.fontFamily
      fontSize: Style.font.iconLarge
    }

    Text {
      visible: !part.panel.compactWidth
      width: Math.max(20, parent.width - Style.space(18) - brandSettingsButton.width
        - parent.spacing * 2)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: part.panel.appName
      color: part.panel.foreground
      font.family: part.panel.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      elide: Text.ElideRight
    }

    Button {
      id: brandSettingsButton
      visible: !part.panel.compactWidth
      width: visible ? implicitWidth : 0
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰒓"
      foreground: part.panel.foreground
      selected: part.panel.currentTab === "setup"
      horizontalPadding: Style.space(5)
      focusable: false
      hasCursor: part.panel.cursorShown("sidebar", "nav-setup")
      tooltipText: part.panel.shortcutHint("Settings", "Ctrl+,")
      onClicked: part.panel.chooseTab("setup")
      onHovered: function(on) {
        if (on) part.panel.setPanelCursor("sidebar", "nav-setup")
      }
      PanelKeyHint { panel: part.panel; region: "sidebar"; action: "nav-setup"; sequences: ["Ctrl+,"] }
    }
  }

  Column {
    id: primaryNavigation
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: brandRow.visible ? brandRow.bottom : parent.top
    anchors.margins: Style.space(2)
    anchors.topMargin: Style.space(6)
    spacing: Style.space(1)

    Repeater {
      model: part.panel ? part.panel.primaryNavigationItems() : []

      Button {
        id: navButton
        required property var modelData
        readonly property bool radioEntry: modelData.id === "radio"
        width: primaryNavigation.width
        height: part.panel.compactWidth ? part.compactRowHeight : implicitHeight
        text: part.panel.compactWidth ? "" : modelData.label
        iconText: part.panel.compactWidth ? "" : modelData.icon
        foreground: part.panel.foreground
        selected: radioEntry ? part.panel.radioNavigationSelected()
          : (modelData.id === "nowplaying" ? part.panel.nowPlayingExpanded
            : part.panel.currentTab === modelData.id)
        leftAlign: !part.panel.compactWidth
        horizontalPadding: part.panel.compactWidth ? 0 : Style.spacing.controlPaddingX
        focusable: false
        hasCursor: part.panel.cursorShown("sidebar", "nav-" + modelData.id)
        tooltipText: radioEntry && part.panel.service && part.panel.service.lastRadioPlaylist
          ? modelData.label + " · " + part.panel.service.lastRadioPlaylist.name
          : part.panel.shortcutHint(modelData.label,
            part.panel.primaryNavigationShortcut(modelData.id))
        onClicked: {
          if (radioEntry) part.panel.openLastRadio()
          else if (modelData.id === "nowplaying") part.panel.toggleNowPlayingExpanded()
          else part.panel.chooseTab(modelData.id)
        }
        onHovered: function(on) {
          if (on) part.panel.setPanelCursor("sidebar", "nav-" + navButton.modelData.id)
        }
        PanelKeyHint {
          panel: part.panel
          region: "sidebar"
          action: "nav-" + navButton.modelData.id
          sequences: part.panel.primaryNavigationShortcut(navButton.modelData.id)
        }
        NavGlyph {
          text: navButton.modelData.icon
          color: navButton.selected
            ? Style.selectedStateColor(part.panel.foreground, part.panel.accent)
            : part.panel.foreground
        }
      }
    }
  }

  PanelSeparator {
    id: navigationSeparator
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: primaryNavigation.bottom
    anchors.margins: Style.space(2)
    anchors.topMargin: Style.space(6)
    foreground: part.panel.foreground
  }

  Grid {
    id: libraryNavigation
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: navigationSeparator.bottom
    anchors.margins: Style.space(2)
    anchors.topMargin: Style.space(6)
    columns: part.panel.compactWidth ? 1 : 2
    spacing: Style.space(1)

    Button {
      id: likedSongsButton
      width: part.panel.compactWidth ? parent.width
        : Math.max(20, parent.width - createPlaylistShortcut.width - parent.spacing)
      height: part.panel.compactWidth ? part.compactRowHeight : implicitHeight
      text: part.panel.compactWidth ? "" : "Your library"
      iconText: part.panel.compactWidth ? "" : "󰋑"
      foreground: part.panel.foreground
      selected: part.panel.currentTab === "library"
      leftAlign: !part.panel.compactWidth
      horizontalPadding: part.panel.compactWidth ? 0 : Style.spacing.controlPaddingX
      focusable: false
      hasCursor: part.panel.cursorShown("sidebar", "nav-library")
      tooltipText: "Your library: liked songs, albums, artists, podcasts"
      onClicked: part.panel.chooseTab("library")
      onHovered: function(on) {
        if (on) part.panel.setPanelCursor("sidebar", "nav-library")
      }
      PanelKeyHint { panel: part.panel; region: "sidebar"; action: "nav-library" }
      NavGlyph {
        text: "󰋑"
        color: likedSongsButton.selected
          ? Style.selectedStateColor(part.panel.foreground, part.panel.accent)
          : part.panel.foreground
      }
    }

    Button {
      id: createPlaylistShortcut
      width: part.panel.compactWidth ? parent.width : implicitWidth
      height: part.panel.compactWidth ? part.compactRowHeight : implicitHeight
      iconText: "󰐕"
      foreground: part.panel.foreground
      horizontalPadding: Style.space(7)
      focusable: false
      hasCursor: part.panel.cursorShown("sidebar", "nav-create")
      tooltipText: "Create a new playlist"
      enabled: part.panel.accountConnected && part.panel.service
        && !part.panel.service.playlistActionBusy
      onClicked: part.panel.openCreatePlaylistPopup()
      onHovered: function(on) {
        if (on) part.panel.setPanelCursor("sidebar", "nav-create")
      }
      PanelKeyHint { panel: part.panel; region: "sidebar"; action: "nav-create" }
    }
  }

  // Kind of thing, sort order and view, all on one row. The two icons say what
  // they are; the sort order needs its words.
  Row {
    id: libraryControls
    visible: !part.panel.compactWidth
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: libraryNavigation.bottom
    anchors.margins: Style.space(2)
    anchors.topMargin: Style.space(4)
    height: visible ? implicitHeight : 0
    spacing: Style.space(1)

    Button {
      id: libraryFilterButton
      iconText: part.panel.libraryFilterIcon()
      foreground: part.panel.muted
      focusable: false
      horizontalPadding: Style.space(7)
      hasCursor: part.panel.cursorShown("sidebar", "lib-filter")
      tooltipText: "Showing " + part.panel.libraryFilterLabel() + ". Next: "
        + part.panel.nextLibraryFilterLabel()
      onClicked: part.panel.cycleLibraryFilter()
      onHovered: function(on) { if (on) part.panel.setPanelCursor("sidebar", "lib-filter") }
      PanelKeyHint { panel: part.panel; region: "sidebar"; action: "lib-filter" }
    }

    Button {
      id: librarySortButton
      width: Math.max(40, parent.width - libraryFilterButton.width
        - libraryViewButton.width - parent.spacing * 2)
      text: part.panel.librarySortLabel()
      iconText: "󰒺"
      foreground: part.panel.muted
      fontSize: Style.font.bodySmall
      leftAlign: true
      focusable: false
      hasCursor: part.panel.cursorShown("sidebar", "lib-sort")
      tooltipText: "Sorted by " + part.panel.librarySortLabel() + ". Next: "
        + part.panel.nextLibrarySortLabel()
      onClicked: part.panel.cycleLibrarySort()
      onHovered: function(on) { if (on) part.panel.setPanelCursor("sidebar", "lib-sort") }
      PanelKeyHint { panel: part.panel; region: "sidebar"; action: "lib-sort" }
    }

    Button {
      id: libraryViewButton
      iconText: part.panel.libraryViewIcon()
      foreground: part.panel.muted
      focusable: false
      horizontalPadding: Style.space(7)
      hasCursor: part.panel.cursorShown("sidebar", "lib-view")
      tooltipText: "View as " + part.panel.libraryViewLabel() + ". Next: "
        + part.panel.nextLibraryViewLabel()
      onClicked: part.panel.cycleLibraryView()
      onHovered: function(on) { if (on) part.panel.setPanelCursor("sidebar", "lib-view") }
      PanelKeyHint { panel: part.panel; region: "sidebar"; action: "lib-view" }
    }
  }

  GridView {
    id: playlistGrid
    property bool pointerSeen: false
    property real pointerX: 0
    property real pointerY: 0
    visible: !part.panel.compactWidth && part.panel.libraryViewIsGrid
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: libraryControls.bottom
    anchors.bottom: setupNavButton.top
    anchors.margins: Style.space(2)
    model: visible && part.panel.service ? part.panel.service.sidebarItems : []
    cellWidth: Math.max(Style.space(56),
      Math.floor(width / Math.max(1, Math.floor(width / Style.space(84)))))
    cellHeight: part.panel.libraryViewIsCompact
      ? cellWidth : cellWidth + Style.space(16)
    clip: true
    reuseItems: true
    keyNavigationEnabled: false
    highlightFollowsCurrentItem: false
    readonly property int columns: Math.max(1, Math.floor(width / cellWidth))
    onAtYEndChanged: if (atYEnd && part.panel.service && part.panel.service.playlistsNext
        && !part.panel.service.playlistsLoading) part.panel.service.loadMorePlaylists()

    FastScrollHandler {
      parent: playlistGrid
      flickable: playlistGrid
    }

    delegate: SidebarRow {
      id: gridCell
      required property var modelData
      required property int index
      width: playlistGrid.cellWidth
      height: playlistGrid.cellHeight
      item: modelData
      compact: part.panel.libraryViewIsCompact
      grid: true
      thumbnailSize: Math.min(width, height - (compact ? 0 : Style.space(16))) - Style.space(10)
      fallbackGlyph: part.panel.sidebarItemIcon(modelData)
      service: part.panel.service
      foreground: part.panel.foreground
      accent: part.panel.accent
      muted: part.panel.muted
      fontFamily: part.panel.fontFamily
      hasCursor: GridView.isCurrentItem && part.panel.cursorShown("sidebar", "sidebar-playlists")
      hoverPaints: !part.panel.keyboardCursorShown
      playing: part.panel.sidebarItemPlaying(modelData)
      selected: part.panel.sidebarItemSelected(modelData)
      onActivated: part.panel.openSidebarItem(modelData)
      onContextRequested: function(x, y) { part.panel.openSidebarContext(gridCell.modelData, x, y) }
      onPointerMoved: function(point) { part.noteLibraryPointer(playlistGrid, gridCell.index, point) }
      Loader {
        anchors.fill: parent
        active: part.panel.shortcutHintsActive
        sourceComponent: PanelKeyHint {
          panel: part.panel
          navHint: part.panel.sidebarListRowHint(gridCell.index, playlistGrid.currentIndex,
            playlistGrid.contentY, part.panel.cursorNav)
        }
      }
    }
  }

  ListView {
    id: playlistList
    property bool pointerSeen: false
    property real pointerX: 0
    property real pointerY: 0
    visible: !part.panel.compactWidth && !part.panel.libraryViewIsGrid
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: libraryControls.bottom
    anchors.bottom: setupNavButton.top
    anchors.margins: Style.space(2)
    model: visible && part.panel.service ? part.panel.service.sidebarItems : []
    clip: true
    spacing: Style.space(1)
    reuseItems: true
    keyNavigationEnabled: false
    highlightFollowsCurrentItem: false

    FastScrollHandler {
      parent: playlistList
      flickable: playlistList
      onScrolled: {
        if (playlistList.atYEnd && part.panel.service
            && part.panel.service.playlistsNext
            && !part.panel.service.playlistsLoading)
          part.panel.service.loadMorePlaylists()
      }
    }

    onMovementEnded: {
      if (atYEnd && part.panel.service && part.panel.service.playlistsNext
          && !part.panel.service.playlistsLoading) part.panel.service.loadMorePlaylists()
    }

    delegate: SidebarRow {
      id: listRow
      required property var modelData
      required property int index
      width: ListView.view.width
      height: part.panel.libraryRowHeight
      item: modelData
      compact: part.panel.libraryViewIsCompact
      grid: false
      thumbnailSize: part.panel.libraryThumbSize
      fallbackGlyph: part.panel.sidebarItemIcon(modelData)
      service: part.panel.service
      foreground: part.panel.foreground
      accent: part.panel.accent
      muted: part.panel.muted
      fontFamily: part.panel.fontFamily
      hasCursor: part.panel.cursorShown("sidebar", "sidebar-playlists")
        && ListView.isCurrentItem
      hoverPaints: !part.panel.keyboardCursorShown
      playing: part.panel.sidebarItemPlaying(modelData)
      selected: part.panel.sidebarItemSelected(modelData)
      onActivated: part.panel.openSidebarItem(modelData)
      onContextRequested: function(x, y) { part.panel.openSidebarContext(listRow.modelData, x, y) }
      onPointerMoved: function(point) { part.noteLibraryPointer(playlistList, listRow.index, point) }
      Loader {
        anchors.fill: parent
        active: part.panel.shortcutHintsActive
        sourceComponent: PanelKeyHint {
          panel: part.panel
          navHint: part.panel.sidebarListRowHint(listRow.index, playlistList.currentIndex,
            playlistList.contentY, part.panel.cursorNav)
        }
      }
    }
  }

  // The cog lives in the title row, so this only covers the narrow and short
  // layouts where that row is gone.
  Button {
    id: setupNavButton
    // Reads the layout, because the cog's visibility also changes as the panel appears.
    visible: part.panel.compactWidth || !part.titleRowShown
    height: visible ? (part.panel.compactWidth ? part.compactRowHeight : implicitHeight) : 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(2)
    text: part.panel.compactWidth ? "" : "Settings"
    iconText: part.panel.compactWidth ? "" : "󰒓"
    foreground: part.panel.foreground
    selected: part.panel.currentTab === "setup"
    leftAlign: !part.panel.compactWidth
    focusable: false
    hasCursor: part.panel.cursorShown("sidebar", "nav-setup")
    tooltipText: part.panel.shortcutHint("Settings", "Ctrl+,")
    PanelKeyHint { panel: part.panel; region: "sidebar"; action: "nav-setup"; sequences: ["Ctrl+,"] }
    onClicked: part.panel.chooseTab("setup")
    onHovered: function(on) {
      if (on) part.panel.setPanelCursor("sidebar", "nav-setup")
    }
    NavGlyph {
      text: "󰒓"
      color: setupNavButton.selected
        ? Style.selectedStateColor(part.panel.foreground, part.panel.accent)
        : part.panel.foreground
    }
  }
}
