import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

import "Api.js" as Api

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

  component KeyHint: PanelKeyHint {
    panel: page.panel
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(7)

    Row {
      id: homeTypes
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: [
          { type: "recent", label: "Recently played", icon: "󰋚" },
          { type: "tracks", label: "Top songs", icon: "󰎈" },
          { type: "artists", label: "Top artists", icon: "󰠃" },
          { type: "releases", label: "Followed releases", icon: "󰀥" }
        ]
        Button {
          required property var modelData
          text: modelData.label
          iconText: modelData.icon
          foreground: page.panel.foreground
          selected: page.panel.homeType === modelData.type
          focusable: false
          hasCursor: page.panel.cursorShown("page", "home-" + modelData.type)
          onClicked: page.panel.homeType = modelData.type
          onHovered: function(on) {
            if (on) page.panel.setPanelCursor("page", "home-" + modelData.type)
          }
          KeyHint { region: "page"; action: "home-" + modelData.type }
        }
      }
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
        color: page.panel.foreground
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.caption
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
        KeyHint { region: "page"; action: "releases-more" }
      }
    }

    MediaCollection {
      width: parent.width
      height: Math.max(40, parent.height - homeTypes.height - releaseStatus.height
        - parent.spacing * (releaseStatus.visible ? 2 : 1))
      service: page.panel.service
      sourceItems: page.panel.service ? page.panel.service.homeItems(page.panel.homeType) : []
      filterText: page.panel.homeFilter
      showFilter: false
      showQueue: true
      showSave: true
      browseContexts: true
      loading: page.releasesActive ? !!page.feed && page.feed.loading
        : page.panel.service && page.panel.service.homeLoading
      hasMore: false
      restoredContentY: page.panel.scrollFor("home:" + page.panel.homeType)
      stateKey: "home:" + page.panel.homeType
      emptyMessage: page.releasesActive
        ? (page.feed && page.feed.error ? page.feed.error
          : page.feed && page.feed.loading ? "Finding releases from artists you follow…"
          : page.panel.homeFilter.trim() ? "No releases match your search."
          : "Follow artists on Spotify to see their latest albums and singles here.")
        : page.panel.service && page.panel.service.homeLoading
        ? "Loading your listening history…"
        : (page.panel.homeFilter.trim() ? "No matches in " + page.panel.activeSearchScope.label + "."
          : "No listening history is available yet.")
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
