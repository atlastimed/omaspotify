pragma ComponentBehavior: Bound

import QtQuick
import qs.Ui

// A button in Settings that the panel's keyboard cursor can reach.
Button {
  id: part

  property var panel: null
  property string cursorId: ""

  function activate() { clicked() }

  foreground: part.panel.foreground
  bordered: true
  focusable: false
  hasCursor: part.panel.cursorShown("page", cursorId)
  onHovered: function(on) { if (on) part.panel.setPanelCursor("page", part.cursorId) }
}
