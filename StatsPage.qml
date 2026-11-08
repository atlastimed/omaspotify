pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

import "Api.js" as Api

// What you actually listened to. Spotify keeps the last fifty plays and shows
// you none of it; this is built from the record the app keeps itself.
Item {
  id: page

  property var panel: null

  readonly property var service: panel ? panel.service : null
  readonly property int weeks: Math.max(8, Math.min(53,
    Math.floor((width - Style.space(30)) / (Style.space(10) + Style.space(2)))))
  readonly property var grid: service
    ? Api.heatmapWeeks(service.listeningDays, Date.now(), weeks) : []

  Component.onCompleted: {
    if (!service) return
    service.loadStats()
    // Top up the play record on the way in, so the counts above are what you
    // have actually listened to rather than what the last poll happened to see.
    service.refreshPlayHistory(false)
  }

  Column {
    anchors.fill: parent
    spacing: page.panel.pageGap

    Row {
      id: statsNumbers
      width: parent.width
      spacing: Style.space(24)

      Repeater {
        model: [
          { value: page.service ? page.service.listeningPlayCount : 0, label: "plays recorded" },
          { value: page.service ? page.service.listeningDayCount : 0, label: "days listening" },
          { value: page.service ? page.service.likedSongLinkCount : 0, label: "liked songs indexed" }
        ]

        Row {
          id: statistic
          required property var modelData
          spacing: Style.space(6)

          Text {
            anchors.baseline: statisticLabel.baseline
            text: String(statistic.modelData.value)
            color: page.panel.foreground
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
          }

          Text {
            id: statisticLabel
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(4)
            text: statistic.modelData.label
            color: page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }

    ListeningHeatmap {
      id: heatmap
      grid: page.grid
      accent: page.panel.accent
      foreground: page.panel.foreground
      muted: page.panel.muted
      fontFamily: page.panel.fontFamily
      emptyFill: Style.normalFillFor(page.panel.foreground, page.panel.accent)
      cellSize: Style.space(10)
      cellRadius: Style.space(2)
      cellGap: Style.space(2)

      PanelToolTip {
        parent: heatmap.hoverAnchor
        visible: heatmap.hoveredDay !== null
        delay: 0
        text: heatmap.hoveredText
      }
    }

    PageTabs {
      id: statsRanges
      width: parent.width
      panel: page.panel
      actionPrefix: "stats-"
      value: page.service ? page.service.statsRange : ""
      options: [
        { value: "short_term", label: "Last 4 weeks" },
        { value: "medium_term", label: "Last 6 months" },
        { value: "long_term", label: "All time" }
      ]
      onChosen: function(value) { if (page.service) page.service.setStatsRange(value) }
    }

    Row {
      width: parent.width
      height: Math.max(Style.space(60), parent.height - y)
      spacing: Style.space(10)

      Column {
        width: Math.max(80, (parent.width - parent.spacing) / 2)
        height: parent.height
        spacing: Style.space(4)

        PanelSectionHeader {
          id: artistsHeading
          text: "Top artists"
          color: page.panel.muted
          fontFamily: page.panel.fontFamily
        }

        MediaCollection {
          width: parent.width
          height: Math.max(30, parent.height - artistsHeading.height - parent.spacing)
          keyboardListId: "list-stats-artists"
          service: page.service
          sourceItems: page.service ? page.service.statsArtists : []
          showSave: true
          browseContexts: true
          loading: page.service && page.service.statsLoading
          emptyGlyph: "󰠃"
          emptyMessage: "No ranking yet. Spotify builds this as you listen."
          onActivated: function(item, items, uri) { page.panel.activateMedia(item, items, uri) }
          onOpened: function(item) { page.panel.openItem(item) }
          onSaveToggled: function(item) { if (page.service) page.service.toggleSaved(item) }
          onContextRequested: function(item, x, y, index, items, uri, playbackUri) {
            page.panel.openMediaContext(item, x, y, items, uri, index, playbackUri)
          }
        }
      }

      Column {
        width: Math.max(80, parent.width - parent.spacing
          - Math.max(80, (parent.width - parent.spacing) / 2))
        height: parent.height
        spacing: Style.space(4)

        PanelSectionHeader {
          id: tracksHeading
          text: "Top songs"
          color: page.panel.muted
          fontFamily: page.panel.fontFamily
        }

        MediaCollection {
          width: parent.width
          height: Math.max(30, parent.height - tracksHeading.height - parent.spacing)
          keyboardListId: "list-stats-tracks"
          service: page.service
          sourceItems: page.service ? page.service.statsTracks : []
          showQueue: true
          showSave: true
          loading: page.service && page.service.statsLoading
          emptyGlyph: "󰎈"
          emptyMessage: "No ranking yet. Spotify builds this as you listen."
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
