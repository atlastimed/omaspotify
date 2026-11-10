pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

import "Api.js" as Api

// A keycap naming the key that works the control it sits on. It rides on the
// control's top right corner, inside the right edge of a row, or above the end
// of a slider, so it never covers what the control says. Nothing is built until
// one shows.
Item {
  id: root

  property var sequences: []
  property bool ctrlHeld: false
  property bool shiftHeld: false
  property bool altHeld: false
  property bool active: false
  // "corner" for buttons, "inset" for rows, which are wide and stacked, and
  // "above" for sliders, whose whole length is in use.
  property string placement: "corner"
  readonly property bool inset: placement === "inset"
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color hintColor: Commons.Color.urgent

  readonly property string label: active
    ? Api.shortcutHintCaption(sequences, {
      ctrl: ctrlHeld,
      shift: shiftHeld,
      alt: altHeld
    }, true) : ""
  readonly property bool shown: label !== "" && (!parent || parent.enabled !== false)
  // What an inset keycap takes from the row's right edge.
  readonly property real reservedRight: shown && inset && overlay.item
    ? overlay.item.width + Style.space(8) : 0

  anchors.fill: parent
  z: 24
  enabled: false

  Loader {
    id: overlay
    active: root.shown
    x: {
      if (root.inset) return root.width - width - Style.space(4)
      if (root.placement === "above") return root.width - width
      // Hang off the corner, but never past the edge of the window.
      var wanted = root.width - Math.round(width * 0.45)
      var top = root
      while (top.parent) top = top.parent
      var over = root.mapToItem(null, wanted + width, 0).x - (top.width - Style.space(2))
      return wanted - Math.max(0, Math.ceil(over))
    }
    y: root.inset ? Math.round((root.height - height) / 2)
      : (root.placement === "above" ? -height - Style.space(1) : -Math.round(height * 0.6))

    sourceComponent: BorderSurface {
      implicitWidth: Math.max(implicitHeight, keycapText.implicitWidth + Style.space(8))
      implicitHeight: keycapText.implicitHeight + Style.space(3)
      radius: Math.max(2, Math.round(Style.cornerRadius * 0.7))
      // Solid, so it reads over whatever it overlaps.
      color: Api.mixColors(Commons.Color.background, root.hintColor, 0.18)
      borderSpec: Border.flat(root.hintColor, Math.max(1, Style.normalBorderWidth))

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
