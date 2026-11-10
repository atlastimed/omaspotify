pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

// A labelled text field in Settings that the panel's keyboard cursor can reach.
Column {
  id: part

  property var panel: null
  property string cursorId: ""
  property string label: ""
  property alias text: field.text
  property alias placeholderText: field.placeholderText
  property alias validator: field.validator
  property alias password: field.password
  readonly property alias fieldEnabled: field.enabled

  signal textEdited()
  signal editingFinished()

  function activate() {
    field.selectAll()
    field.forceActiveFocus()
  }

  spacing: Style.space(3)

  Text {
    visible: part.label !== ""
    width: parent.width
    textFormat: Text.PlainText
    text: part.label
    color: part.panel.muted
    font.family: part.panel.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  TextField {
    id: field
    width: parent.width
    foreground: part.panel.foreground
    placeholderTextColor: part.panel.muted
    enabled: part.enabled
    hasCursor: part.panel.cursorShown("page", part.cursorId)
    onHoveredChanged: if (hovered) part.panel.setPanelCursor("page", part.cursorId)
    onTextEdited: part.textEdited()
    onEditingFinished: part.editingFinished()
  }
}
