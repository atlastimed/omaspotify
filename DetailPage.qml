pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

import "Api.js" as Api

Item {
  id: page

  property var panel: null

  readonly property var service: panel ? panel.service : null
  readonly property var item: service ? service.detailItem : null
  readonly property bool isArtist: !!item && item.type === "artist"
  readonly property bool searchActive: isArtist && panel.artistScopedSearchActive
  readonly property bool playsThroughItems: !!item
    && ["show", "audiobook"].indexOf(item.type) >= 0

  // An artist has up to three lists. Side by side while each stays readable,
  // otherwise one at a time behind tabs.
  property string artistSection: "albums"
  property string artistSearchSection: "songs"
  readonly property bool showLiked: !!service && (service.artistLikedSongs.length > 0
    || service.artistLikedSongsLoading)
  readonly property int artistListCount: showLiked ? 3 : 2
  readonly property bool artistTabbed: width / artistListCount < Style.space(300)
  readonly property real artistColumnWidth: artistTabbed ? width
    : Api.evenColumnWidth(width, Style.space(10), artistListCount)

  function cursorActions() {
    if (!isArtist) return []
    if (searchActive) return ["artist-search-songs", "artist-search-albums", "artist-search-playlists"]
    if (!artistTabbed) return []
    return showLiked ? ["artist-albums", "artist-songs", "artist-liked"]
      : ["artist-albums", "artist-songs"]
  }

  function activateCursorAction(action) {
    var value = String(action)
    if (value.indexOf("artist-search-") === 0) {
      artistSearchSection = value.substring(14)
      return true
    }
    if (value.indexOf("artist-") === 0) {
      artistSection = value.substring(7)
      return true
    }
    return false
  }

  function artistSearchItems() {
    if (!service) return []
    if (artistSearchSection === "albums") return service.artistAlbums
    if (artistSearchSection === "playlists") return service.artistPlaylists
    return service.artistSongs
  }

  function artistSearchLabel(label, count, loading) {
    return label + (loading && count === 0 ? " …" : " " + count)
  }

  onShowLikedChanged: if (!showLiked && artistSection === "liked") artistSection = "albums"
  onArtistTabbedChanged: page.panel.scheduleCursorRefresh()

  Column {
    anchors.fill: parent
    spacing: page.panel.pageGap

    Item {
      id: detailHero
      width: parent.width
      height: visible ? Style.space(104) : 0
      visible: !page.searchActive

      BorderSurface {
        id: heroArt
        width: parent.height
        height: width
        anchors.left: parent.left
        radius: Style.cornerRadius
        color: Style.normalFillFor(page.panel.foreground, page.panel.accent)
        borderSpec: Border.none()
        clip: true

        Image {
          id: detailArtwork
          anchors.fill: parent
          source: page.item && page.service && page.service.artworkEnabled
            ? String(page.item.imageUrl || "") : ""
          sourceSize.width: 256
          sourceSize.height: 256
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          visible: status === Image.Ready
        }
        Text {
          anchors.centerIn: parent
          visible: detailArtwork.status !== Image.Ready
          text: page.isArtist ? "󰠃" : ""
          color: page.panel.muted
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.displayLarge
        }
      }

      Column {
        anchors.left: heroArt.right
        anchors.leftMargin: Style.space(12)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)

        ArtistLinks {
          width: parent.width
          artists: page.item ? page.item.artists : []
          fallbackText: page.item ? String(page.item.subtitle || "") : ""
          suffixText: page.item ? Api.artistSubtitleSuffix(page.item) : ""
          color: page.panel.muted
          accent: page.panel.accent
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.body
          onArtistRequested: function(item) { page.panel.openItem(item) }
        }

        Text {
          width: parent.width
          visible: text !== ""
          text: !page.item ? ""
            : (page.isArtist ? Api.artistDetailLine(page.item)
              : String(page.item.description || ""))
          textFormat: Text.PlainText
          color: page.panel.muted
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.bodySmall
          maximumLineCount: 2
          elide: Text.ElideRight
          wrapMode: Text.WordWrap
        }

        Row {
          spacing: Style.space(3)
          topPadding: Style.space(3)

          Button {
            text: "Play"
            iconText: "󰐊"
            foreground: page.panel.foreground
            selected: true
            focusable: false
            hasCursor: page.panel.cursorShown("page", "detail-play")
            enabled: !!page.item && (!page.playsThroughItems
              || page.service.detailItems.length > 0)
            onClicked: {
              if (page.playsThroughItems)
                page.panel.activateMedia(page.service.detailItems[0], page.service.detailItems, "")
              else page.panel.activateMedia(page.item)
            }
            onHovered: function(on) {
              if (on) page.panel.setPanelCursor("page", "detail-play")
            }
            PanelKeyHint { panel: page.panel; region: "page"; action: "detail-play" }
          }
          Button {
            readonly property bool saved: page.service && page.service.isSaved(page.item)
            text: saved ? "Saved" : "Save"
            iconText: saved ? "󰋑" : "󰋕"
            foreground: saved ? page.panel.accent : page.panel.foreground
            accent: page.panel.accent
            bordered: true
            focusable: false
            hasCursor: page.panel.cursorShown("page", "detail-save")
            enabled: !!page.item && !saved
            onClicked: if (page.service && !saved) page.service.toggleSaved(page.item)
            onHovered: function(on) {
              if (on) page.panel.setPanelCursor("page", "detail-save")
            }
            PanelKeyHint { panel: page.panel; region: "page"; action: "detail-save" }
          }
          Button {
            id: detailMoreActions
            visible: !!page.item
            iconText: "󰇙"
            foreground: page.panel.foreground
            horizontalPadding: Style.space(7)
            tooltipText: page.panel.shortcutHint("More actions", "C")
            focusable: false
            hasCursor: page.panel.cursorShown("page", "detail-more")
            onHovered: function(on) {
              if (on) page.panel.setPanelCursor("page", "detail-more")
            }
            PanelKeyHint {
              panel: page.panel
              region: "page"
              action: "detail-more"
              sequences: ["C"]
            }
            onClicked: {
              var point = detailMoreActions.mapToItem(page.panel.windowContentItem,
                detailMoreActions.width, 0)
              page.panel.openMediaContext(page.item, point.x, point.y,
                page.service.detailItems, page.item.uri, -1)
            }
          }
        }
      }
    }

    Text {
      id: detailNotice
      width: parent.width
      height: visible ? implicitHeight : 0
      visible: page.service && page.service.detailMessage !== ""
      text: page.service ? page.service.detailMessage : ""
      textFormat: Text.PlainText
      color: page.panel.muted
      font.family: page.panel.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Loader {
      width: parent.width
      height: active ? Math.max(40, parent.height - detailHero.height
        - detailNotice.height - parent.spacing * (detailNotice.visible ? 2 : 1)) : 0
      active: page.isArtist && !page.searchActive
      visible: active
      sourceComponent: Column {
      id: artistCatalog
      spacing: Style.space(6)

      PageTabs {
        id: artistTabs
        width: parent.width
        visible: page.artistTabbed
        height: visible ? implicitHeight : 0
        panel: page.panel
        actionPrefix: "artist-"
        value: page.artistSection
        options: page.showLiked
          ? [{ value: "albums", label: "Albums and EPs" }, { value: "songs", label: "Songs" },
            { value: "liked", label: "Your liked songs" }]
          : [{ value: "albums", label: "Albums and EPs" }, { value: "songs", label: "Songs" }]
        onChosen: function(value) { page.artistSection = value }
      }

      Row {
        id: artistLists
        width: parent.width
        height: parent.height - artistTabs.height - (artistTabs.visible ? parent.spacing : 0)
        spacing: Style.space(10)

        Column {
          width: page.artistColumnWidth
          height: parent.height
          spacing: Style.space(5)
          visible: !page.artistTabbed || page.artistSection === "albums"

          PanelSectionHeader {
            id: artistAlbumsHeading
            visible: !page.artistTabbed
            text: "Albums and EPs"
            color: page.panel.muted
            fontFamily: page.panel.fontFamily
          }

          MediaCollection {
            width: parent.width
            height: Math.max(30, parent.height - (artistAlbumsHeading.visible ? artistAlbumsHeading.height + parent.spacing : 0))
            keyboardListId: "list-albums"
            service: page.service
            sourceItems: page.service ? page.service.artistAlbums : []
            showQueue: false
            showSave: true
            browseContexts: true
            loading: page.service && page.service.artistAlbumsLoading
            hasMore: page.service && page.service.artistAlbumsNext !== ""
            emptyGlyph: "󰀥"
            emptyMessage: page.service && (page.service.artistAlbumsLoading
              || page.service.detailLoading)
              ? "Finding releases…" : "No albums or EPs found."
            onActivated: function(item, items, uri) { page.panel.activateMedia(item, items, uri) }
            onOpened: function(item) { page.panel.openItem(item) }
            onSaveToggled: function(item) { if (page.service) page.service.toggleSaved(item) }
            onContextRequested: function(item, x, y, index, items, uri, playbackUri) {
              page.panel.openMediaContext(item, x, y, items, uri, index, playbackUri)
            }
            onLoadMoreRequested: if (page.service) page.service.loadMoreArtistAlbums()
          }
        }

        Column {
          width: page.artistColumnWidth
          height: parent.height
          spacing: Style.space(5)
          visible: !page.artistTabbed || page.artistSection === "songs"

          PanelSectionHeader {
            id: artistSongsHeading
            visible: !page.artistTabbed
            text: "Songs"
            color: page.panel.muted
            fontFamily: page.panel.fontFamily
          }

          MediaCollection {
            width: parent.width
            height: Math.max(30, parent.height - (artistSongsHeading.visible ? artistSongsHeading.height + parent.spacing : 0)
              - artistThisIsRow.height - (artistThisIsRow.visible ? parent.spacing : 0))
            keyboardListId: "list-songs"
            service: page.service
            sourceItems: page.service ? page.service.artistSongs : []
            showQueue: true
            showSave: true
            browseContexts: false
            loading: page.service && page.service.artistSongsLoading
            hasMore: page.service && page.service.artistSongsNext !== ""
            emptyGlyph: "󰎈"
            emptyMessage: page.service && (page.service.artistSongsLoading
              || page.service.detailLoading)
              ? "Finding songs…" : "No songs found."
            onActivated: function(item, items, uri) { page.panel.activateMedia(item, items, uri) }
            onOpened: function(item) { page.panel.openItem(item) }
            onQueued: function(item) { if (page.service) page.service.addToQueue(item) }
            onPlaylistRequested: function(item) { page.panel.openPlaylistPicker(item) }
            onSaveToggled: function(item) { if (page.service) page.service.toggleSaved(item) }
            onContextRequested: function(item, x, y, index, items, uri, playbackUri) {
              page.panel.openMediaContext(item, x, y, items, uri, index, playbackUri)
            }
            onLoadMoreRequested: if (page.service) page.service.loadMoreArtistSongs()
          }

          MediaRow {
            id: artistThisIsRow
            objectName: "artist-thisis"
            service: page.service
            width: parent.width
            height: visible ? implicitHeight : 0
            visible: !!page.service && !!page.service.artistThisIsPlaylist
            itemData: page.service ? page.service.artistThisIsPlaylist : null
            hasCursor: page.panel.cursorShown("page", "detail-thisis")
            foreground: page.panel.foreground
            accent: page.panel.accent
            fontFamily: page.panel.fontFamily
            browseOnActivate: true
            showQueue: false
            showPlaylist: false
            showSave: true
            saved: page.service && page.service.isSaved(itemData)
            onActivated: function(item) { page.panel.activateMedia(item, [item], item.uri) }
            onOpenRequested: function(item) { page.panel.openItem(item) }
            onSaveRequested: function(item) {
              if (page.service) page.service.toggleSaved(item)
            }
            onContextRequested: function(item, sceneX, sceneY) {
              page.panel.openMediaContext(item, sceneX, sceneY, [item], item.uri, 0)
            }
            PanelKeyHint { panel: page.panel; region: "page"; action: "detail-thisis" }
          }
        }

        Column {
          width: page.artistColumnWidth
          height: parent.height
          spacing: Style.space(5)
          visible: page.showLiked && (!page.artistTabbed || page.artistSection === "liked")

          PanelSectionHeader {
            id: artistLikedHeading
            visible: !page.artistTabbed
            text: "Your liked songs"
            color: page.panel.muted
            fontFamily: page.panel.fontFamily
          }

          MediaCollection {
            width: parent.width
            height: Math.max(30, parent.height - (artistLikedHeading.visible ? artistLikedHeading.height + parent.spacing : 0))
            keyboardListId: "list-liked-songs"
            service: page.service
            sourceItems: page.service ? page.service.artistLikedSongs : []
            showQueue: true
            showSave: true
            loading: page.service && page.service.artistLikedSongsLoading
            emptyGlyph: "󰋑"
            emptyMessage: "No liked songs by this artist."
            onActivated: function(item, items, uri) { page.panel.activateMedia(item, items, uri) }
            onOpened: function(item) { page.panel.openItem(item) }
            onQueued: function(item) { if (page.service) page.service.addToQueue(item) }
            onPlaylistRequested: function(item) { page.panel.openPlaylistPicker(item) }
            onSaveToggled: function(item) { if (page.service) page.service.toggleSaved(item) }
            onContextRequested: function(item, x, y, index, items, uri, playbackUri) {
              page.panel.openMediaContext(item, x, y, items, uri, index, playbackUri)
            }
          }
        }
      }
    }

    }

    Loader {
      width: parent.width
      height: active ? Math.max(40, parent.height - detailNotice.height
        - (detailNotice.visible ? parent.spacing : 0)) : 0
      active: page.searchActive
      visible: active
      sourceComponent: Column {
      id: artistSearchPage
      spacing: Style.space(6)

      PageTabs {
        id: artistSearchTabs
        width: parent.width
        panel: page.panel
        actionPrefix: "artist-search-"
        value: page.artistSearchSection
        options: [
          { value: "songs", label: page.artistSearchLabel("Songs",
            page.service ? page.service.artistSongs.length : 0,
            page.service && page.service.artistSongsLoading) },
          { value: "albums", label: page.artistSearchLabel("Albums and EPs",
            page.service ? page.service.artistAlbums.length : 0,
            page.service && page.service.artistAlbumsLoading) },
          { value: "playlists", label: page.artistSearchLabel("Playlists",
            page.service ? page.service.artistPlaylists.length : 0,
            page.service && page.service.artistPlaylistsLoading) }
        ]
        onChosen: function(value) { page.artistSearchSection = value }
      }

      MediaCollection {
        width: parent.width
        height: Math.max(30, parent.height - artistSearchTabs.height - parent.spacing)
        service: page.service
        sourceItems: page.artistSearchItems()
        showQueue: page.artistSearchSection === "songs"
        showPlaylist: page.artistSearchSection === "songs"
        showSave: true
        browseContexts: page.artistSearchSection !== "songs"
        stateKey: "artist-search:" + page.artistSearchSection + ":" + page.panel.artistSearchText
        loading: page.service && page.service.artistCatalogLoading
        hasMore: !!page.service && (page.artistSearchSection === "albums"
          ? page.service.artistAlbumsNext !== ""
          : (page.artistSearchSection === "playlists"
            ? page.service.artistPlaylistsNext !== "" : page.service.artistSongsNext !== ""))
        emptyGlyph: "󰍉"
        emptyMessage: page.service && page.service.artistCatalogLoading
          ? "Searching " + (page.item ? page.item.name : "this artist") + "…"
          : "Nothing here matched this search."
        onActivated: function(item, items, uri) { page.panel.activateMedia(item, items, "") }
        onOpened: function(item) { page.panel.openItem(item) }
        onQueued: function(item) { if (page.service) page.service.addToQueue(item) }
        onPlaylistRequested: function(item) { page.panel.openPlaylistPicker(item) }
        onSaveToggled: function(item) { if (page.service) page.service.toggleSaved(item) }
        onContextRequested: function(item, x, y, index, items, uri, playbackUri) {
          page.panel.openMediaContext(item, x, y, items, "", index)
        }
        onLoadMoreRequested: {
          if (!page.service) return
          if (page.artistSearchSection === "albums") page.service.loadMoreArtistAlbums()
          else if (page.artistSearchSection === "playlists") page.service.loadMoreArtistPlaylists()
          else page.service.loadMoreArtistSongs()
        }
      }
    }

    }

    Loader {
      width: parent.width
      height: active ? Math.max(40, parent.height - detailHero.height - detailNotice.height
        - parent.spacing * (detailNotice.visible ? 2 : 1)) : 0
      active: !page.isArtist
      visible: active
      sourceComponent: MediaCollection {
      id: detailCollection
      service: page.service
      sourceItems: page.service ? page.service.detailItems : []
      filterText: page.panel.detailFilter
      sortKey: page.panel.detailSort
      contextUri: page.item ? page.item.uri : ""
      showQueue: true
      showSort: true
      showSave: true
      browseContexts: true
      allowReorder: !!page.item && page.service.playlistOwned(page.item)
      reorderBusy: page.service && page.service.playlistActionBusy
      loading: page.service && page.service.detailLoading
      hasMore: page.service && page.service.detailNext !== ""
      restoredContentY: page.panel.scrollFor("detail:" + (page.item ? page.item.uri : ""))
      stateKey: "detail:" + (page.item ? page.item.uri : "")
      restoreReady: !page.service || !page.service.detailRestorePending
      emptyMessage: page.service && page.service.detailMessage
        ? page.service.detailMessage : "No items are available for this selection."
      onActivated: function(item, items, uri) { page.panel.activateMedia(item, items, uri) }
      onOpened: function(item) { page.panel.openItem(item) }
      onQueued: function(item) { if (page.service) page.service.addToQueue(item) }
      onPlaylistRequested: function(item) { page.panel.openPlaylistPicker(item) }
      onSaveToggled: function(item) { if (page.service) page.service.toggleSaved(item) }
      onContextRequested: function(item, x, y, index, items, uri, playbackUri) {
        page.panel.openMediaContext(item, x, y, items, uri, index, playbackUri)
      }
      onReorderRequested: function(sourceIndex, destinationIndex) {
        if (page.item)
          page.service.reorderPlaylistItem(sourceIndex, destinationIndex,
            page.item, page.service.detailItems.length, page.service.detailItems)
      }
      onLoadMoreRequested: if (page.service) page.service.loadMoreDetail()
      onViewStateChanged: function(filter, sort, y) {
        page.panel.detailFilter = filter
        page.panel.detailSort = sort
        page.panel.rememberScroll("detail:" + (page.item ? page.item.uri : ""), y)
      }
      }
    }
  }
}
