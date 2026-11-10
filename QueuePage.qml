pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Ui

Item {
  id: page

  property var panel: null

  Column {
    anchors.fill: parent
    spacing: page.panel.pageGap

    Item {
      width: parent.width
      height: queueRefresh.implicitHeight

      PanelSectionHeader {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "Up next"
        color: page.panel.muted
        fontFamily: page.panel.fontFamily
      }

      Button {
        id: queueRefresh
        anchors.right: parent.right
        text: page.panel.service && page.panel.service.queueLoading ? "Loading…" : "Refresh"
        iconText: "󰑐"
        iconSpinning: page.panel.service && page.panel.service.queueLoading
        foreground: page.panel.foreground
        focusable: false
        hasCursor: page.panel.cursorShown("page", "queue-refresh")
        enabled: page.panel.service && !page.panel.service.queueLoading
        onClicked: page.panel.service.loadQueue()
        onHovered: function(on) { if (on) page.panel.setPanelCursor("page", "queue-refresh") }
      }
    }

    MediaCollection {
      width: parent.width
      height: Math.max(60, parent.height - queueRefresh.height - parent.spacing)
      service: page.panel.service
      sourceItems: page.panel.service ? page.panel.service.queue : []
      filterText: page.panel.queueFilter
      showQueue: false
      showSave: true
      browseContexts: false
      loading: page.panel.service && page.panel.service.queueLoading
      emptyGlyph: "󰲸"
      emptyMessage: page.panel.service && page.panel.service.queueLoading
        ? "Loading the queue…"
        : (page.panel.queueFilter.trim()
          ? "No matching songs in the queue."
          : "Nothing is queued to play next. Add a song from any list with its + button.")
      onActivated: function(item, items, uri) { page.panel.activateMedia(item, items, "") }
      onOpened: function(item) { page.panel.openItem(item) }
      onPlaylistRequested: function(item) { page.panel.openPlaylistPicker(item) }
      onSaveToggled: function(item) { if (page.panel.service) page.panel.service.toggleSaved(item) }
      onContextRequested: function(item, x, y, index, items, uri, playbackUri) {
        page.panel.openMediaContext(item, x, y, items, "", index)
      }
    }
  }
}
