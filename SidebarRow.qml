pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

import "Api.js" as Api

// One entry in the library sidebar. Renders as a row or as a grid cell, with or
// without artwork, so the four view modes share a single delegate.
BorderSurface {
  id: row

  property var item: null
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color muted: Api.secondaryTextColor(Commons.Color.foreground, Commons.Color.background)
  property string fontFamily: Style.font.family
  property bool compact: false
  property bool grid: false
  property bool selected: false
  property bool hasCursor: false
  // Off while the keyboard cursor is on show, so only one row looks current.
  property bool hoverPaints: true
  property bool playing: false
  property int thumbnailSize: Style.space(32)
  property string fallbackGlyph: "󰲸"
  property var service: null

  readonly property bool pinned: !!(item && item.pinned)
  readonly property string label: item ? String(item.name || "Untitled") : ""
  readonly property bool hovered: hoverHandler.hovered
  readonly property bool artworkShown: !service || service.artworkEnabled

  signal activated()
  signal contextRequested(real sceneX, real sceneY)
  signal pointerMoved(point scenePoint)

  radius: Style.cornerRadius
  color: selected ? Style.selectedFillFor(foreground, accent)
    : ((hovered && hoverPaints) || hasCursor ? Style.hoverFillFor(foreground, accent) : "transparent")
  borderSpec: hasCursor ? Border.controlSpec("hover-cursor", foreground, accent)
    : (selected ? Border.controlSpec("selected", foreground, accent) : Border.none())
  clip: true

  HoverHandler {
    id: hoverHandler
    onPointChanged: if (hovered) row.pointerMoved(point.scenePosition)
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        var point = row.mapToItem(null, mouse.x, mouse.y)
        row.contextRequested(point.x, point.y)
      } else row.activated()
    }
  }

  // Marks whatever is playing right now, whichever row the cursor is on.
  Rectangle {
    visible: row.playing && !row.grid
    width: Math.max(2, Style.space(2))
    height: parent.height - Style.space(10)
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    radius: width / 2
    color: row.accent
  }

  // Artwork, or the type glyph when there is none to show.
  Component {
    id: artworkPart

    BorderSurface {
      width: row.thumbnailSize
      height: row.thumbnailSize
      radius: Style.spacing.labelGap
      color: Style.normalFillFor(row.foreground, row.accent)
      borderSpec: Border.none()

      Image {
        id: art
        anchors.fill: parent
        source: !row.artworkShown ? ""
          : (row.service && row.item && row.item.imageUrl
            ? row.service.artworkFor(row.item.imageUrl)
            : (row.item && row.item.imageUrl ? row.item.imageUrl : ""))
        sourceSize.width: Math.ceil(row.thumbnailSize * 2)
        sourceSize.height: Math.ceil(row.thumbnailSize * 2)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: art.status !== Image.Ready
        text: row.fallbackGlyph
        color: row.muted
        font.family: row.fontFamily
        font.pixelSize: Style.font.icon
      }
    }
  }

  Component {
    id: rowLayout

    // Children of a positioner must not be anchored, so each takes the full
    // height and centres its own content.
    Row {
      spacing: Style.space(6)

      Item {
        width: row.compact ? Style.space(14) : row.thumbnailSize
        height: parent.height

        Loader {
          anchors.centerIn: parent
          active: !row.compact
          sourceComponent: artworkPart
        }

        Text {
          anchors.centerIn: parent
          visible: row.compact
          text: row.fallbackGlyph
          color: row.muted
          font.family: row.fontFamily
          font.pixelSize: Style.font.iconSmall
        }
      }

      Text {
        id: rowLabel
        width: Math.max(10, parent.width - parent.spacing * 2
          - (row.compact ? Style.space(14) : row.thumbnailSize)
          - (row.pinned ? Style.space(12) : 0))
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        text: row.label
        textFormat: Text.PlainText
        color: row.playing ? row.accent : row.foreground
        font.family: row.fontFamily
        font.pixelSize: row.compact ? Style.font.bodySmall : Style.font.body
        elide: Text.ElideRight

        Loader {
          active: row.hovered && rowLabel.truncated
          sourceComponent: PanelToolTip {
            visible: true
            text: row.label
          }
        }
      }

      Text {
        visible: row.pinned
        width: visible ? Style.space(12) : 0
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        text: "󰐃"
        color: row.accent
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Component {
    id: gridLayout

    Column {
      spacing: Style.space(3)

      Item {
        width: parent.width
        height: row.thumbnailSize

        Loader {
          anchors.centerIn: parent
          sourceComponent: artworkPart
        }
      }

      Text {
        width: parent.width
        visible: !row.compact
        text: row.label
        textFormat: Text.PlainText
        color: row.playing ? row.accent : row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      // A compact cell has no room for a name, so the pointer has to supply it.
      Loader {
        active: row.compact && row.hovered
        sourceComponent: PanelToolTip {
          visible: true
          text: row.label
        }
      }
    }
  }

  Loader {
    anchors.fill: parent
    anchors.margins: Style.space(3)
    sourceComponent: row.grid ? gridLayout : rowLayout
  }
}
