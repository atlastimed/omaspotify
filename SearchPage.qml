pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

import "Api.js" as Api

Item {
  id: page

  property var panel: null

  readonly property var service: panel ? panel.service : null
  readonly property bool searching: panel && panel.searchText.trim() !== ""
  readonly property var history: service ? service.searchHistory : []
  readonly property string failure: service ? String(service.searchError || "") : ""
  readonly property int cooldown: panel ? panel.searchCooldownSeconds : 0

  // The history chips only exist while the field is empty, so they join the
  // cursor from here rather than from a fixed list in the panel.
  function cursorActions() {
    if (searching || !history.length) return []
    var actions = ["history-clear"]
    for (var i = 0; i < history.length; i++) actions.push("history-" + i)
    return actions
  }

  function searchFromHistory(term) {
    page.panel.searchText = term
    page.service.search(term, page.panel.searchType)
    Qt.callLater(function() { page.panel.focusSearchField() })
  }

  function activateCursorAction(action) {
    if (action === "history-clear") {
      service.clearSearchHistory()
      return true
    }
    if (String(action).indexOf("history-") === 0) {
      searchFromHistory(history[Number(String(action).substring(8))])
      return true
    }
    return false
  }

  Component.onDestruction: {
    if (page.panel.service) page.panel.service.cancelSearch(false)
  }

  Column {
    anchors.fill: parent
    spacing: page.panel.pageGap

    PageTabs {
      id: searchTypes
      width: parent.width
      panel: page.panel
      actionPrefix: "search-"
      value: page.panel.searchType
      options: [
        { value: "track", label: "Songs" },
        { value: "artist", label: "Artists" },
        { value: "album", label: "Albums" },
        { value: "playlist", label: "Playlists" },
        { value: "show", label: "Podcasts" },
        { value: "episode", label: "Episodes" },
        { value: "audiobook", label: "Books" }
      ]
      onChosen: function(value) { page.panel.selectSearchType(value) }
    }

    BorderSurface {
      id: searchFailure
      width: parent.width
      height: visible ? Math.max(failureRow.implicitHeight + Style.space(8), Style.space(34)) : 0
      visible: page.searching && (page.failure !== "" || page.cooldown > 0)
      radius: Style.cornerRadius
      color: Style.normalFillFor(page.panel.foreground, page.panel.accent)
      borderSpec: Border.flat(Commons.Color.urgent, Math.max(1, Style.normalBorderWidth))

      Row {
        id: failureRow
        anchors.fill: parent
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(3)
        spacing: Style.space(7)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰀦"
          color: Commons.Color.urgent
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.icon
        }

        Text {
          objectName: "search-failure-text"
          width: Math.max(40, parent.width - Style.space(30) - retryButton.width)
          anchors.verticalCenter: parent.verticalCenter
          text: page.cooldown > 0
            ? "Spotify asked us to slow down. Try again in " + page.cooldown
              + (page.cooldown === 1 ? " second." : " seconds.")
            : page.failure
          textFormat: Text.PlainText
          color: page.panel.foreground
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        Button {
          id: retryButton
          anchors.verticalCenter: parent.verticalCenter
          text: "Retry"
          foreground: page.panel.foreground
          focusable: false
          enabled: page.cooldown <= 0
          hasCursor: page.panel.cursorShown("page", "retry-search")
          onClicked: if (page.service) page.service.retrySearch(page.panel.searchType)
          onHovered: function(on) { if (on) page.panel.setPanelCursor("page", "retry-search") }
          PanelKeyHint { panel: page.panel; region: "page"; action: "retry-search" }
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(7)
      visible: !page.searching

      Item {
        width: parent.width
        height: clearHistory.implicitHeight
        visible: page.history.length > 0

        PanelSectionHeader {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Recent searches"
          color: page.panel.muted
          fontFamily: page.panel.fontFamily
        }

        Button {
          id: clearHistory
          anchors.right: parent.right
          text: "Clear"
          foreground: page.panel.foreground
          focusable: false
          hasCursor: page.panel.cursorShown("page", "history-clear")
          onClicked: page.service.clearSearchHistory()
          onHovered: function(on) { if (on) page.panel.setPanelCursor("page", "history-clear") }
          PanelKeyHint { panel: page.panel; region: "page"; action: "history-clear" }
        }
      }

      Flow {
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: page.history
          Button {
            id: historyChip
            required property string modelData
            required property int index
            text: modelData
            iconText: "󰋚"
            foreground: page.panel.foreground
            bordered: true
            focusable: false
            hasCursor: page.panel.cursorShown("page", "history-" + index)
            onClicked: page.searchFromHistory(modelData)
            onHovered: function(on) {
              if (on) page.panel.setPanelCursor("page", "history-" + historyChip.index)
            }
            PanelKeyHint { panel: page.panel; region: "page"; action: "history-" + historyChip.index }
          }
        }
      }

      Text {
        width: parent.width
        visible: page.history.length === 0
        topPadding: Style.space(24)
        horizontalAlignment: Text.AlignHCenter
        text: "Search by title, artist, album, playlist, podcast, episode or audiobook."
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }

    MediaCollection {
      id: resultsView
      width: parent.width
      height: Math.max(40, parent.height - searchTypes.height - searchFailure.height
        - parent.spacing * (searchFailure.visible ? 2 : 1))
      visible: page.searching
      service: page.service
      sourceItems: page.service ? page.service.searchItems(page.panel.searchType) : []
      showQueue: true
      showSave: true
      browseContexts: true
      loading: page.service && page.service.searchLoading
      hasMore: page.service && page.service.searchNext(page.panel.searchType) !== ""
      restoredContentY: page.panel.scrollFor("search:" + page.panel.searchType)
      stateKey: "search:" + page.panel.searchType
      emptyGlyph: "󰍉"
      emptyMessage: page.service && page.service.searchLoading
        ? "Searching…"
        : "No " + Api.searchTypeLabel(page.panel.searchType) + " found for “"
          + page.panel.searchText.trim() + "”."
      onActivated: function(item, items, uri) {
        page.panel.activateMedia(item, items, uri)
      }
      onOpened: function(item) { page.panel.openItem(item) }
      onQueued: function(item) { if (page.service) page.service.addToQueue(item) }
      onPlaylistRequested: function(item) { page.panel.openPlaylistPicker(item) }
      onSaveToggled: function(item) { if (page.service) page.service.toggleSaved(item) }
      onContextRequested: function(item, x, y, index, items, uri, playbackUri) {
        page.panel.openMediaContext(item, x, y, items, uri, index, playbackUri)
      }
      onLoadMoreRequested: if (page.service) page.service.loadMoreSearch(page.panel.searchType)
      onViewStateChanged: function(filter, sort, y) {
        page.panel.rememberScroll("search:" + page.panel.searchType, y)
      }
    }
  }
}
