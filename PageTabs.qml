pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

// The row of choices at the top of a page. It wraps rather than overflowing at
// larger type, and every option is reachable from the panel's cursor.
Flow {
  id: part

  property var panel: null
  property var options: []
  property string value: ""
  property string actionPrefix: ""

  signal chosen(string value)

  spacing: Style.space(3)

  Repeater {
    model: part.options

    Button {
      id: tab
      required property var modelData
      readonly property string action: part.actionPrefix + modelData.value
      text: modelData.label
      iconText: modelData.icon || ""
      foreground: part.panel.foreground
      selected: part.value === modelData.value
      focusable: false
      horizontalPadding: Style.space(8)
      hasCursor: part.panel.cursorShown("page", action)
      onClicked: part.chosen(modelData.value)
      onHovered: function(on) { if (on) part.panel.setPanelCursor("page", tab.action) }
      PanelKeyHint { panel: part.panel; region: "page"; action: tab.action }
    }
  }
}
