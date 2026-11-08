pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

import "Api.js" as Api

// Next-key overlay for shortcut mode. Uses a weak theme-urgent (red) wash
// and keycap so tutorial hints stay distinct from hover and selection. Nothing
// is built until a hint actually shows, since most sessions never show one.
Item {
  id: root

  property var sequences: []
  property bool ctrlHeld: false
  property bool shiftHeld: false
  property bool altHeld: false
  property bool active: false
  property string navHint: ""
  property bool showWash: true
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color hintColor: Commons.Color.urgent

  readonly property string label: active || navHint !== ""
    ? Api.shortcutOverlayLabel(sequences, {
      ctrl: ctrlHeld,
      shift: shiftHeld,
      alt: altHeld
    }, active, navHint) : ""
  readonly property bool shown: label !== "" && (!parent || parent.enabled !== false)
  readonly property real reservedRight: shown && overlay.item
    ? overlay.item.keycapWidth + Style.space(4) : 0

  anchors.fill: parent
  z: 24
  enabled: false
  clip: false

  Loader {
    id: overlay
    anchors.fill: parent
    active: root.shown

    sourceComponent: Item {
      readonly property real keycapWidth: keycap.implicitWidth

      BorderSurface {
        anchors.fill: parent
        visible: root.showWash
        radius: Style.cornerRadius
        color: Qt.rgba(root.hintColor.r, root.hintColor.g, root.hintColor.b, Style.hoverFillAlpha)
        borderSpec: Border.flat(Qt.rgba(root.hintColor.r, root.hintColor.g, root.hintColor.b,
          Style.hoverBorderAlpha), Math.max(1, Style.normalBorderWidth))
      }

      BorderSurface {
        id: keycap
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Math.max(1, Style.space(2))
        implicitWidth: keycapText.implicitWidth + Style.space(8)
        implicitHeight: keycapText.implicitHeight + Style.space(3)
        radius: Math.max(2, Math.round(Style.cornerRadius * 0.7))
        color: Qt.rgba(root.hintColor.r, root.hintColor.g, root.hintColor.b, Style.selectedFillAlpha)
        borderSpec: Border.flat(Qt.rgba(root.hintColor.r, root.hintColor.g, root.hintColor.b,
          Style.normalBorderAlpha), Math.max(1, Style.normalBorderWidth))

        Text {
          id: keycapText
          anchors.centerIn: parent
          text: root.label
          textFormat: Text.PlainText
          color: root.hintColor
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
    }
  }
}
