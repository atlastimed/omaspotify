import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Asks once before something that is hard to undo. Cancel holds focus, so an
// Enter that was meant for something else does nothing.
Popup {
  id: popup

  property var panel: null
  property string message: ""
  property string confirmText: "Confirm"
  property var action: null

  parent: popup.panel.windowContentItem
  x: Math.max(Style.space(8), (popup.panel.windowWidth - width) / 2)
  y: Math.max(Style.space(8), (popup.panel.windowHeight - height) / 2)
  width: Math.min(Style.space(400), popup.panel.windowWidth - Style.space(24))
  height: confirmContent.implicitHeight + padding * 2
  padding: Style.space(12)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  onOpened: confirmCancel.forceActiveFocus()
  onClosed: Qt.callLater(function() { popup.panel.restoreFocus() })

  background: BorderSurface {
    color: popup.panel.popupBackground
    radius: Style.cornerRadius
    borderSpec: popup.panel.popupBorderSpec
  }

  contentItem: Column {
    id: confirmContent
    spacing: Style.space(12)

    Text {
      objectName: "confirm-message"
      width: parent.width
      text: popup.message
      textFormat: Text.PlainText
      color: popup.panel.foreground
      font.family: popup.panel.fontFamily
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
    }

    Row {
      anchors.right: parent.right
      spacing: Style.space(6)

      Button {
        id: confirmCancel
        text: "Cancel"
        foreground: popup.panel.foreground
        focusable: true
        onClicked: popup.close()
      }

      Button {
        text: popup.confirmText
        foreground: popup.panel.foreground
        selected: true
        focusable: true
        onClicked: {
          var action = popup.action
          popup.close()
          if (typeof action === "function") action()
        }
      }
    }
  }
}
