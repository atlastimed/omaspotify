pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Passing news floats over the bottom of the page rather than shoving the list
// down. Confirmations clear themselves; a failure stays until it is dealt with.
Item {
  id: part

  property var panel: null

  readonly property var service: panel ? panel.service : null
  readonly property string errorText: service ? String(service.lastError || "") : ""
  readonly property string statusText: service ? String(service.statusMessage || "") : ""
  readonly property bool showing: errorText !== "" || statusText !== ""
  readonly property bool failed: errorText !== ""
  property string shownText: ""
  property bool shownFailed: false

  onErrorTextChanged: remember()
  onStatusTextChanged: remember()

  function remember() {
    var text = errorText || statusText
    if (!text) return
    shownText = text
    shownFailed = errorText !== ""
  }

  function dismiss() {
    if (!service) return
    service.lastError = ""
    service.statusMessage = ""
  }

  implicitHeight: toast.implicitHeight
  height: implicitHeight
  visible: opacity > 0
  opacity: showing ? 1 : 0

  Behavior on opacity {
    NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }
  }

  BorderSurface {
    id: toast
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.min(parent.width, Math.max(Style.space(220),
      content.implicitWidth + Style.space(20)))
    implicitHeight: Math.max(content.implicitHeight + Style.space(10), Style.space(32))
    radius: Style.cornerRadius
    color: part.panel.popupBackground
    borderSpec: part.shownFailed
      ? Border.flat(Commons.Color.urgent, Math.max(1, Style.normalBorderWidth))
      : part.panel.popupBorderSpec

    MouseArea { anchors.fill: parent }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(7)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: part.shownFailed ? "󰀦" : "󰄬"
        color: part.shownFailed ? Commons.Color.urgent : part.panel.accent
        font.family: part.panel.fontFamily
        font.pixelSize: Style.font.icon
      }

      Text {
        id: message
        objectName: "panel-toast-text"
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(Style.space(120), part.width - Style.space(180)))
        text: part.shownText
        textFormat: Text.PlainText
        color: part.panel.foreground
        font.family: part.panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }

      Button {
        anchors.verticalCenter: parent.verticalCenter
        visible: part.shownFailed
        text: "Retry"
        fontSize: Style.font.bodySmall
        foreground: part.panel.foreground
        verticalPadding: Style.space(2)
        focusable: false
        onClicked: part.panel.retryAfterFailure()
      }

      Button {
        anchors.verticalCenter: parent.verticalCenter
        visible: part.shownFailed
        iconText: "󰅖"
        iconSize: Style.font.bodySmall
        foreground: part.panel.foreground
        horizontalPadding: Style.space(5)
        verticalPadding: Style.space(2)
        focusable: false
        tooltipText: "Dismiss · Esc"
        onClicked: part.dismiss()
      }
    }
  }
}
