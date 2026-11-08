import QtQuick
import qs.Commons
import qs.Ui

// A switch in Settings that the panel's keyboard cursor can reach.
Toggle {
  id: part

  property var panel: null
  property string cursorId: ""

  function activate() { clicked() }

  foreground: part.panel.foreground
  accent: part.panel.accent
  fontFamily: part.panel.fontFamily
  titleSize: Style.font.body
  activeFocusOnTab: false
  hasCursor: part.panel.cursorShown("page", cursorId)
  onHovered: function(on) { if (on) part.panel.setPanelCursor("page", part.cursorId) }
}
