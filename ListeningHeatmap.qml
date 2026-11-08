pragma ComponentBehavior: Bound

import QtQuick

import "Api.js" as Api

// A square for every day, stronger the more you played that day. One hover
// handler covers the grid and works out the day from the pointer, because one
// per square costs more than the rest of the page.
Column {
  id: heatmap

  property var grid: []
  property color accent: "white"
  property color foreground: "white"
  property color muted: "gray"
  property string fontFamily: ""
  property color emptyFill: "transparent"
  property real cellSize: 9
  property real cellRadius: 2
  property real cellGap: 2
  readonly property real pitch: cellSize + cellGap
  readonly property var hoveredDay: {
    if (!cells.hovered || !hoverPoint) return null
    var week = heatmap.grid[Math.floor(hoverPoint.x / pitch)]
    var day = week ? week[Math.floor(hoverPoint.y / pitch)] : null
    return day && !day.future ? day : null
  }
  readonly property string hoveredText: dayText(hoveredDay)
  readonly property point hoverPoint: cells.position
  readonly property string todayKey: Api.playDayKey(Date.now())
  // Where the page should hang its one tooltip.
  readonly property Item hoverAnchor: hoverCell

  spacing: cellGap

  function shade(level) {
    if (level <= 0) return emptyFill
    return Qt.rgba(accent.r, accent.g, accent.b, 0.22 + 0.24 * level)
  }

  function dayText(day) {
    if (!day) return ""
    return day.key + " · " + day.count + (day.count === 1 ? " play" : " plays")
  }

  Item {
    id: monthLabels
    objectName: "heatmap-months"
    width: heatmap.grid.length * heatmap.pitch
    height: monthMetrics.height

    TextMetrics {
      id: monthMetrics
      text: "Mar"
      font.family: heatmap.fontFamily
      font.pixelSize: Math.max(9, heatmap.cellSize)
    }

    Repeater {
      model: Api.heatmapMonthLabels(heatmap.grid)

      Text {
        required property var modelData
        x: modelData.week * heatmap.pitch
        text: modelData.text
        color: heatmap.muted
        font.family: heatmap.fontFamily
        font.pixelSize: Math.max(9, heatmap.cellSize)
      }
    }
  }

  Row {
    spacing: heatmap.cellSize * 2

    Item {
      id: cells
      objectName: "heatmap-cells"
      width: heatmap.grid.length * heatmap.pitch
      height: 7 * heatmap.pitch
      readonly property bool hovered: hover.hovered
      readonly property point position: hover.point.position

      HoverHandler { id: hover }

      Row {
        spacing: heatmap.cellGap

        Repeater {
          model: heatmap.grid

          Column {
            id: week
            required property var modelData
            spacing: heatmap.cellGap

            Repeater {
              model: week.modelData

              Rectangle {
                required property var modelData
                width: heatmap.cellSize
                height: width
                radius: heatmap.cellRadius
                visible: !modelData.future
                color: heatmap.shade(modelData.level)
                border.width: modelData.key === heatmap.todayKey ? 1 : 0
                border.color: heatmap.foreground
              }
            }
          }
        }
      }

      Item {
        id: hoverCell
        x: Math.floor(heatmap.hoverPoint.x / heatmap.pitch) * heatmap.pitch
        y: Math.floor(heatmap.hoverPoint.y / heatmap.pitch) * heatmap.pitch
        width: heatmap.cellSize
        height: heatmap.cellSize
      }
    }

    Row {
      objectName: "heatmap-legend"
      anchors.bottom: parent.bottom
      spacing: heatmap.cellGap

      Text {
        anchors.verticalCenter: parent.verticalCenter
        rightPadding: heatmap.cellGap * 2
        text: "Less"
        color: heatmap.muted
        font.family: heatmap.fontFamily
        font.pixelSize: Math.max(9, heatmap.cellSize)
      }

      Repeater {
        model: [0, 1, 2, 3]

        Rectangle {
          required property int modelData
          width: heatmap.cellSize
          height: width
          radius: heatmap.cellRadius
          color: heatmap.shade(modelData)
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        leftPadding: heatmap.cellGap * 2
        text: "More"
        color: heatmap.muted
        font.family: heatmap.fontFamily
        font.pixelSize: Math.max(9, heatmap.cellSize)
      }
    }
  }
}
