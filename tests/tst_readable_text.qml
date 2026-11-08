import QtQuick
import QtTest

import "../Api.js" as Api

TestCase {
  name: "ReadableText"

  // The stock themes that came out hardest: low-contrast foregrounds, and the
  // ones whose decorative muted colour was under 2:1.
  readonly property var themes: [
    { name: "catppuccin-latte", fg: "#4c4f69", bg: "#eff1f5" },
    { name: "rose-pine", fg: "#575279", bg: "#faf4ed" },
    { name: "matte-black", fg: "#bebebe", bg: "#121212" },
    { name: "tokyo-night", fg: "#a9b1d6", bg: "#1a1b26" },
    { name: "everforest", fg: "#d3c6aa", bg: "#2d353b" },
    { name: "white", fg: "#000000", bg: "#ffffff" }
  ]

  function test_secondaryTextStaysReadableOnEveryTheme() {
    for (var i = 0; i < themes.length; i++) {
      var fg = Qt.color(themes[i].fg), bg = Qt.color(themes[i].bg)
      var text = Api.secondaryTextColor(fg, bg)
      verify(Api.contrastRatio(text, bg) >= 4.5, themes[i].name)
    }
  }

  function test_secondaryTextIsQuieterThanTheForeground() {
    for (var i = 0; i < themes.length; i++) {
      var fg = Qt.color(themes[i].fg), bg = Qt.color(themes[i].bg)
      var text = Api.secondaryTextColor(fg, bg)
      verify(Api.contrastRatio(text, bg) < Api.contrastRatio(fg, bg), themes[i].name)
    }
  }

  function test_aForegroundWithNoRoomIsLeftAlone() {
    var fg = Qt.color("#808080"), bg = Qt.color("#707070")
    compare(Api.secondaryTextColor(fg, bg), fg)
  }

  function test_monthLabelsMarkTheFirstWeekOfEachMonth() {
    var weeks = []
    var keys = ["2026-08-30", "2026-09-06", "2026-09-13", "2026-09-20", "2026-09-27",
      "2026-10-04", "2026-10-11"]
    for (var i = 0; i < keys.length; i++) weeks.push([{ key: keys[i] }])
    var labels = Api.heatmapMonthLabels(weeks)
    compare(labels.length, 2)
    compare(labels[0].week, 1)
    compare(labels[0].text, "Sep")
    compare(labels[1].week, 5)
    compare(labels[1].text, "Oct")
  }
}
