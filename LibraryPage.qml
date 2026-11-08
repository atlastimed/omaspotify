pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: page

  property var panel: null

  Component.onCompleted: if (page.panel.service) page.panel.service.loadLibrary(page.panel.libraryType, false)

  Column {
    anchors.fill: parent
    spacing: page.panel.pageGap

    PageTabs {
      id: libraryTypes
      width: parent.width
      panel: page.panel
      actionPrefix: "library-"
      value: page.panel.libraryType
      options: [
        { value: "tracks", label: "Songs", icon: "󰎈" },
        { value: "albums", label: "Albums", icon: "󰀥" },
        { value: "artists", label: "Artists", icon: "󰠃" },
        { value: "shows", label: "Podcasts", icon: "󰦔" },
        { value: "episodes", label: "Episodes", icon: "󰐾" },
        { value: "audiobooks", label: "Books", icon: "󰂺" }
      ]
      onChosen: function(value) {
        page.panel.libraryType = value
        if (page.panel.service) page.panel.service.loadLibrary(value, false)
      }
    }

    MediaCollection {
      id: libraryCollection
      width: parent.width
      height: Math.max(40, parent.height - libraryTypes.height - parent.spacing)
      service: page.panel.service
      sourceItems: page.panel.service ? page.panel.service.libraryItems(page.panel.libraryType) : []
      filterText: page.panel.libraryFilter
      sortKey: page.panel.librarySort
      showSort: true
      showQueue: true
      showSave: true
      browseContexts: true
      loading: page.panel.service && page.panel.service.libraryLoading(page.panel.libraryType)
      hasMore: page.panel.service && page.panel.service.libraryNext(page.panel.libraryType) !== ""
      restoredContentY: page.panel.scrollFor("library:" + page.panel.libraryType)
      stateKey: "library:" + page.panel.libraryType
      emptyGlyph: "󰋑"
      emptyMessage: page.panel.service && page.panel.service.libraryLoading(page.panel.libraryType)
        ? "Loading your library…"
        : (page.panel.libraryFilter.trim()
          ? "No matches in " + page.panel.activeSearchScope.label + "."
          : "Nothing saved here yet. Save something with its heart and it appears here.")
      onActivated: function(item, items, uri) {
        page.panel.activateMedia(item, items, uri)
      }
      onOpened: function(item) { page.panel.openItem(item) }
      onQueued: function(item) { if (page.panel.service) page.panel.service.addToQueue(item) }
      onPlaylistRequested: function(item) { page.panel.openPlaylistPicker(item) }
      onSaveToggled: function(item) { if (page.panel.service) page.panel.service.toggleSaved(item) }
      onContextRequested: function(item, x, y, index, items, uri, playbackUri) {
        page.panel.openMediaContext(item, x, y, items, uri, index, playbackUri)
      }
      onLoadMoreRequested: if (page.panel.service) page.panel.service.loadLibrary(page.panel.libraryType, true)
      onViewStateChanged: function(filter, sort, y) {
        page.panel.libraryFilter = filter
        page.panel.librarySort = sort
        page.panel.rememberScroll("library:" + page.panel.libraryType, y)
      }
    }
  }
}
