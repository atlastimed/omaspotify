pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: page

  property var panel: null
  readonly property var feed: panel && panel.service ? panel.service.releaseFeed : null
  readonly property bool releasesActive: visible && panel && panel.opened && panel.currentTab === "home"
    && panel.homeType === "releases" && panel.accountConnected
  onReleasesActiveChanged: {
    if (!feed) return
    if (releasesActive) feed.load()
    else feed.cancel()
  }
  Component.onDestruction: if (feed) feed.cancel()

  Column {
    anchors.fill: parent
    spacing: page.panel.pageGap

    PageTabs {
      id: homeTypes
      width: parent.width
      panel: page.panel
      actionPrefix: "home-"
      value: page.panel.homeType
      options: [
        { value: "recent", label: "Recently played", icon: "󰋚" },
        { value: "tracks", label: "Top songs", icon: "󰎈" },
        { value: "artists", label: "Top artists", icon: "󰠃" },
        { value: "releases", label: "Followed releases", icon: "󰀥" }
      ]
      onChosen: function(value) { page.panel.homeType = value }
    }

    Row {
      id: releaseStatus
      width: parent.width
      spacing: Style.space(8)
      visible: page.releasesActive
      height: visible ? implicitHeight : 0
      Text {
        width: Math.max(0, parent.width - releaseMore.width - parent.spacing)
        anchors.verticalCenter: parent.verticalCenter
        text: page.feed ? page.feed.summary : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Button {
        id: releaseMore
        text: page.feed && page.feed.error ? "Retry" : "Check more artists"
        foreground: page.panel.foreground
        visible: page.feed && page.feed.hasMore
        enabled: page.feed && !page.feed.loading
        focusable: false
        hasCursor: page.panel.cursorShown("page", "releases-more")
        onHovered: function(on) { if (on) page.panel.setPanelCursor("page", "releases-more") }
        onClicked: if (page.feed) {
          if (page.feed.error) page.panel.service.retryReleaseFeed()
          else page.feed.load()
        }
        PanelKeyHint { panel: page.panel; region: "page"; action: "releases-more" }
      }
    }

    MediaCollection {
      width: parent.width
      height: Math.max(40, parent.height - homeTypes.height - releaseStatus.height
        - parent.spacing * (releaseStatus.visible ? 2 : 1))
      service: page.panel.service
      sourceItems: page.panel.service ? page.panel.service.homeItems(page.panel.homeType) : []
      filterText: page.panel.homeFilter
      showQueue: true
      showSave: true
      browseContexts: true
      loading: page.releasesActive ? !!page.feed && page.feed.loading
        : page.panel.service && page.panel.service.homeLoading
      hasMore: false
      restoredContentY: page.panel.scrollFor("home:" + page.panel.homeType)
      stateKey: "home:" + page.panel.homeType
      emptyGlyph: page.releasesActive ? "󰀥" : "󰋚"
      emptyMessage: page.releasesActive
        ? (page.feed && page.feed.error ? page.feed.error
          : page.feed && page.feed.loading ? "Finding releases from artists you follow…"
          : page.panel.homeFilter.trim() ? "No releases match your search."
          : "Follow artists on Spotify to see their latest albums and singles here.")
        : page.panel.service && page.panel.service.homeLoading
        ? "Loading your listening history…"
        : (page.panel.homeFilter.trim() ? "No matches in " + page.panel.activeSearchScope.label + "."
          : "No listening history yet. Play something and it appears here.")
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
      onViewStateChanged: function(filter, sort, y) {
        page.panel.rememberScroll("home:" + page.panel.homeType, y)
      }
    }
  }
}
