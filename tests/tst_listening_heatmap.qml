import QtQuick
import QtQuick.Window
import QtTest

import ".."

TestCase {
  id: testCase
  name: "ListeningHeatmap"
  when: testWindow.visible

  property var sampleGrid: {
    var weeks = []
    for (var w = 0; w < 30; w++) {
      var days = []
      for (var d = 0; d < 7; d++)
        days.push({
          key: "2026-09-0" + (d + 1),
          count: d,
          level: d % 4,
          future: false
        })
      weeks.push(days)
    }
    return weeks
  }

  Window {
    id: testWindow
    width: 600
    height: 200
    visible: true

    ListeningHeatmap {
      id: heatmap
      grid: testCase.sampleGrid
      accent: "#f1dfb4"
      emptyFill: "#33a59d86"
      cellSize: 9
      cellGap: 2
    }
  }

  function init() {
    mouseMove(testWindow, testWindow.width - 1, testWindow.height - 1)
  }

  function test_everyWeekGetsAColumnOfSevenDays() {
    var cells = findChild(heatmap, "heatmap-cells")
    var columns = cells.children[0].children
    var weeks = 0
    for (var i = 0; i < columns.length; i++) {
      var days = 0
      var squares = columns[i].children
      for (var j = 0; j < squares.length; j++)
        if (squares[j].width === heatmap.cellSize) days++
      if (days === 7) weeks++
    }
    compare(weeks, 30)
  }

  function test_noDayIsNamedUntilOneIsHovered() {
    compare(heatmap.hoveredDay, null)
    compare(heatmap.hoveredText, "")
  }

  function test_hoveringADayNamesItAndItsPlays() {
    var cells = findChild(heatmap, "heatmap-cells")

    mouseMove(cells, 4, heatmap.pitch + 4)

    tryVerify(function() { return heatmap.hoveredDay !== null }, 2000)
    compare(heatmap.hoveredText, "2026-09-02 · 1 play")
  }

  function test_aDayWithSeveralPlaysIsPlural() {
    var cells = findChild(heatmap, "heatmap-cells")

    mouseMove(cells, 4, heatmap.pitch * 3 + 4)

    tryVerify(function() { return heatmap.hoveredDay !== null }, 2000)
    compare(heatmap.hoveredText, "2026-09-04 · 3 plays")
  }

  function test_theLegendShowsEveryShade() {
    var legend = findChild(heatmap, "heatmap-legend")
    verify(legend !== null)
    var shades = 0
    for (var i = 0; i < legend.children.length; i++)
      if (legend.children[i].width === heatmap.cellSize) shades++
    compare(shades, 4)
  }
}
