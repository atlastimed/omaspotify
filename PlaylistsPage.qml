pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

import "Api.js" as Api

Item {
  id: page

  property var panel: null

  readonly property var service: panel ? panel.service : null
  readonly property var playlist: service ? service.selectedPlaylist : null
  readonly property bool canCopy: !!playlist && service.currentUserId !== ""
    && !service.playlistOwned(playlist)

  Column {
    anchors.fill: parent
    spacing: page.panel.pageGap

    Column {
      id: selectedPlaylistHeader
      width: parent.width
      spacing: Style.space(6)

      SearchableDropdown {
        visible: page.panel.compactWidth
        width: parent.width
        height: visible ? implicitHeight : 0
        showLabel: false
        foreground: page.panel.foreground
        background: page.panel.background
        accent: page.panel.accent
        fontFamily: page.panel.fontFamily
        placeholderText: "Choose a playlist…"
        emptyText: page.service && page.service.playlistsLoading
          ? "Loading playlists…" : "No playlists found"
        options: page.panel.playlistOptions()
        value: page.playlist ? String(page.playlist.id) : ""
        onChanged: function(value) {
          page.panel.openSidebarItem(page.panel.sidebarItemById(value))
        }
      }

      Button {
        visible: page.panel.compactWidth && page.service && page.service.playlistsNext !== ""
        width: parent.width
        text: page.service && page.service.playlistsLoading
          ? "Loading more playlists…" : "Load more playlists"
        iconText: "󰑐"
        foreground: page.panel.foreground
        enabled: page.service && !page.service.playlistsLoading
        onClicked: page.service.loadMorePlaylists()
      }

      Item {
        width: parent.width
        height: Math.max(playlistArt.height, playlistActions.implicitHeight)
        visible: !!page.playlist

        BorderSurface {
          id: playlistArt
          width: page.service && page.service.artworkEnabled ? Style.space(52) : 0
          height: width
          visible: width > 0
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          radius: Style.cornerRadius
          color: Style.normalFillFor(page.panel.foreground, page.panel.accent)
          borderSpec: Border.none()
          clip: true

          Image {
            anchors.fill: parent
            source: page.playlist && page.service
              ? page.service.artworkFor(page.playlist.imageUrl) : ""
            sourceSize.width: 104
            sourceSize.height: 104
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            onStatusChanged: if (status === Image.Error && page.playlist && page.service
                && String(source).indexOf("file://") === 0)
              page.service.forgetArtwork(page.playlist.imageUrl)
          }
        }

        Column {
          anchors.left: playlistArt.right
          anchors.leftMargin: playlistArt.visible ? Style.space(10) : 0
          anchors.right: playlistActions.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: page.playlist ? String(page.playlist.name || "Playlist") : ""
            textFormat: Text.PlainText
            color: page.panel.foreground
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: {
              if (!page.playlist) return ""
              var parts = []
              if (page.playlist.ownerName) parts.push(page.playlist.ownerName)
              if (page.playlist.total) parts.push(page.playlist.total
                + (page.playlist.total === 1 ? " item" : " items"))
              return parts.join(" · ")
            }
            textFormat: Text.PlainText
            color: page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }

        Row {
          id: playlistActions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)

          Button {
            visible: page.canCopy
            anchors.verticalCenter: parent.verticalCenter
            text: page.service && page.service.playlistConversionBusy
              ? "Making your copy…" : "Make my own copy"
            iconText: "󰒍"
            foreground: page.panel.foreground
            bordered: true
            focusable: false
            enabled: page.service && !page.service.playlistActionBusy
            tooltipText: "Copy every available item, then remove the followed original"
            onClicked: page.panel.turnPlaylistIntoOwn(page.playlist)
          }

          Button {
            id: playPlaylist
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰐊"
            text: "Play"
            foreground: page.panel.foreground
            selected: true
            focusable: false
            enabled: !playlistItemsCollection.playbackUsesVisibleOrder
              || playlistItemsCollection.visibleItems.length > 0
            hasCursor: page.panel.cursorShown("page", "playlist-play")
            tooltipText: playlistItemsCollection.playbackUsesVisibleOrder
              ? Api.visibleOrderPlaybackMessage(playlistItemsCollection.visibleItems.length)
              : "Play this playlist in its original order"
            onClicked: page.panel.playSelectedPlaylist()
            onHovered: function(on) {
              if (on) page.panel.setPanelCursor("page", "playlist-play")
            }
          }

          Button {
            id: playlistMoreActions
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰇙"
            foreground: page.panel.foreground
            horizontalPadding: Style.space(7)
            focusable: false
            tooltipText: page.panel.shortcutHint("More actions", "C")
            hasCursor: page.panel.cursorShown("page", "playlist-more")
            onHovered: function(on) {
              if (on) page.panel.setPanelCursor("page", "playlist-more")
            }
            onClicked: {
              var point = playlistMoreActions.mapToItem(page.panel.windowContentItem,
                playlistMoreActions.width, 0)
              page.panel.openMediaContext(page.playlist, point.x, point.y,
                [], page.playlist.uri, -1)
            }
          }
        }
      }
    }

    MediaCollection {
      id: playlistItemsCollection
      width: parent.width
      height: Math.max(40, parent.height - selectedPlaylistHeader.height - parent.spacing)
      service: page.service
      sourceItems: page.service ? page.service.playlistItems : []
      filterText: page.panel.playlistFilter
      sortKey: page.panel.playlistSort
      contextUri: page.playlist ? page.playlist.uri : ""
      showQueue: true
      showSort: true
      showCount: false
      showSave: true
      browseContexts: false
      allowReorder: page.playlist && page.service.playlistOwned(page.playlist)
      reorderBusy: page.service && page.service.playlistActionBusy
      loading: page.service && page.service.playlistItemsLoading
      hasMore: page.service && page.service.playlistItemsNext !== ""
      emptyGlyph: "󰲸"
      emptyMessage: page.playlist
        ? (page.service.playlistItemsEmptyMessage || "This playlist has no visible items.")
        : (page.panel.compactWidth ? "Choose a playlist above."
          : "Choose a playlist from the sidebar.")
      restoredContentY: page.panel.scrollFor("playlist:" + (page.playlist ? page.playlist.id : ""))
      stateKey: "playlist:" + (page.playlist ? page.playlist.id : "")
      restoreReady: !page.service || !page.service.playlistRestorePending
      onActivated: function(item, items, uri) {
        page.panel.activateMedia(item, items, uri,
          playbackUsesVisibleOrder
            ? Api.visibleOrderPlaybackMessage(items.length) : "")
      }
      onOpened: function(item) { page.panel.openItem(item) }
      onQueued: function(item) { if (page.service) page.service.addToQueue(item) }
      onPlaylistRequested: function(item) { page.panel.openPlaylistPicker(item) }
      onSaveToggled: function(item) { if (page.service) page.service.toggleSaved(item) }
      onContextRequested: function(item, x, y, index, items, uri, playbackUri) {
        page.panel.openMediaContext(item, x, y, items, uri, index, playbackUri)
      }
      onReorderRequested: function(sourceIndex, destinationIndex) {
        if (page.playlist)
          page.service.reorderPlaylistItem(sourceIndex, destinationIndex,
            page.playlist, page.service.playlistItems.length, page.service.playlistItems)
      }
      onLoadMoreRequested: if (page.service) page.service.loadMorePlaylistItems()
      onViewStateChanged: function(filter, sort, y) {
        page.panel.playlistFilter = filter
        page.panel.playlistSort = sort
        page.panel.rememberScroll("playlist:" + (page.playlist ? page.playlist.id : ""), y)
      }
    }
  }
}
