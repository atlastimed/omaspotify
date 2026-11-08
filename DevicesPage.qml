pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: page

  property var panel: null

  readonly property var service: panel ? panel.service : null
  readonly property var devices: service ? service.devices : []
  readonly property bool canStartHere: !!service && service.fullyConnected
    && !service.daemon.running

  function cursorActions() {
    var actions = ["devices-refresh"]
    if (canStartHere) actions.push("devices-start")
    for (var i = 0; i < devices.length; i++) actions.push("device-" + i)
    return actions
  }

  function deviceUsable(device) {
    return !!device && (!device.restricted || !!device.activationRequired)
      && !!service && !service.deviceActivationBusy
  }

  function activateCursorAction(action) {
    var value = String(action)
    if (value === "devices-refresh") {
      service.loadDevices(null, undefined, true)
      return true
    }
    if (value === "devices-start") {
      service.startEngine()
      return true
    }
    if (value.indexOf("device-") === 0) {
      var device = devices[Number(value.substring(7))]
      if (deviceUsable(device)) service.selectDevice(device.id, true)
      return true
    }
    return false
  }

  function deviceGlyph(device) {
    var type = String(device.type || "").toLowerCase()
    if (type === "computer") return "󰟀"
    if (type === "smartphone" || type === "phone") return "󰏲"
    if (type === "tablet") return "󰓶"
    if (type === "tv" || type === "avr" || type === "stb") return "󰔂"
    if (type === "speaker") return "󰓃"
    return "󰋋"
  }

  function deviceDetail(device) {
    return String(device.type || "") + (device.description ? " · " + device.description : "")
      + (device.local ? " · this computer" : "")
      + (device.localDiscovery ? " · nearby" : "")
      + (device.restricted
        ? (device.active
          ? (service && service.sonosControlAvailable ? " · local controls" : " · limited controls")
          : " · unavailable") : "")
  }

  function deviceState(device) {
    if (service && service.deviceActivationBusy && device.id === service.selectedDeviceId)
      return "Connecting…"
    if (device.active) return "Playing here"
    if (device.activationRequired) return "Available"
    var volume = Number(device.volumePercent)
    return isFinite(volume) && volume >= 0 ? "Volume " + Math.round(volume) + "%" : ""
  }

  Connections {
    target: page.panel
    function onPanelCursorActionChanged() {
      var action = String(page.panel.panelCursorAction)
      if (action.indexOf("device-") !== 0 || !page.panel.keyboardCursorShown) return
      var row = deviceRows.itemAt(Number(action.substring(7)))
      var flick = devicesScroll.contentItem
      if (!row || !flick) return
      var top = row.mapToItem(devicesContent, 0, 0).y
      if (top < flick.contentY) flick.contentY = top
      else if (top + row.height > flick.contentY + flick.height)
        flick.contentY = top + row.height - flick.height
    }
  }

  ScrollView {
    id: devicesScroll
    anchors.fill: parent
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    Column {
      id: devicesContent
      width: devicesScroll.availableWidth
      spacing: Style.space(7)

      Item {
        width: parent.width
        height: Math.max(deviceRefresh.implicitHeight, deviceIntro.implicitHeight)

        Text {
          id: deviceIntro
          anchors.left: parent.left
          anchors.right: deviceRefresh.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "Choose where your music plays. A nearby speaker may take a moment to connect the first time."
          color: page.panel.muted
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Button {
          id: deviceRefresh
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: page.service && page.service.devicesLoading ? "Looking…" : "Refresh"
          iconText: "󰑐"
          iconSpinning: page.service && page.service.devicesLoading
          foreground: page.panel.foreground
          focusable: false
          enabled: page.service && !page.service.devicesLoading
            && !page.service.deviceActivationBusy
          hasCursor: page.panel.cursorShown("page", "devices-refresh")
          onClicked: page.service.loadDevices(null, undefined, true)
          onHovered: function(on) { if (on) page.panel.setPanelCursor("page", "devices-refresh") }
          PanelKeyHint { panel: page.panel; region: "page"; action: "devices-refresh" }
        }
      }

      Button {
        text: "Start this computer"
        iconText: "󰐊"
        foreground: page.panel.foreground
        bordered: true
        focusable: false
        visible: page.canStartHere
        enabled: page.service && !page.service.daemon.busy
        hasCursor: page.panel.cursorShown("page", "devices-start")
        onClicked: if (page.service) page.service.startEngine()
        onHovered: function(on) { if (on) page.panel.setPanelCursor("page", "devices-start") }
        PanelKeyHint { panel: page.panel; region: "page"; action: "devices-start" }
      }

      Column {
        width: parent.width
        spacing: Style.space(2)

        Repeater {
          id: deviceRows
          model: page.devices

          delegate: BorderSurface {
            id: deviceRow
            required property var modelData
            required property int index
            readonly property string action: "device-" + index
            readonly property bool usable: page.deviceUsable(modelData)
            readonly property bool hasCursor: page.panel.cursorShown("page", action)
            readonly property bool chosen: page.service
              && modelData.id === page.service.selectedDeviceId
            width: devicesScroll.availableWidth
            implicitHeight: Style.space(46)
            height: implicitHeight
            radius: Style.cornerRadius
            color: hasCursor || (deviceHover.hovered && !page.panel.keyboardCursorShown)
              ? Style.hoverFillFor(page.panel.foreground, page.panel.accent)
              : (chosen ? Style.selectedFillFor(page.panel.foreground, page.panel.accent) : "transparent")
            borderSpec: hasCursor ? Border.controlSpec("hover-cursor", page.panel.foreground, page.panel.accent)
              : (modelData.active ? Border.controlSpec("selected", page.panel.foreground, page.panel.accent)
                : Border.none())

            HoverHandler {
              id: deviceHover
              onHoveredChanged: if (hovered) page.panel.setPanelCursor("page", deviceRow.action)
            }
            MouseArea {
              anchors.fill: parent
              enabled: deviceRow.usable
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
              onClicked: page.service.selectDevice(deviceRow.modelData.id, true)
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(10)

              Text {
                id: deviceIcon
                anchors.verticalCenter: parent.verticalCenter
                text: page.deviceGlyph(deviceRow.modelData)
                color: deviceRow.modelData.active ? page.panel.accent : page.panel.muted
                font.family: page.panel.fontFamily
                font.pixelSize: Style.font.iconLarge
              }

              Column {
                width: Math.max(40, parent.width - deviceIcon.width - deviceStatus.width
                  - parent.spacing * 2)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: deviceRow.modelData.name
                  textFormat: Text.PlainText
                  color: page.panel.foreground
                  font.family: page.panel.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: deviceRow.modelData.active
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: page.deviceDetail(deviceRow.modelData)
                  textFormat: Text.PlainText
                  color: page.panel.muted
                  font.family: page.panel.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              Text {
                id: deviceStatus
                anchors.verticalCenter: parent.verticalCenter
                text: page.deviceState(deviceRow.modelData)
                textFormat: Text.PlainText
                color: deviceRow.modelData.active ? page.panel.accent : page.panel.muted
                font.family: page.panel.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: deviceRow.modelData.active
              }
            }

            PanelKeyHint { panel: page.panel; region: "page"; action: deviceRow.action }
          }
        }
      }

      Text {
        width: parent.width
        visible: page.service && page.service.devicesLoading && page.devices.length === 0
        topPadding: Style.space(24)
        horizontalAlignment: Text.AlignHCenter
        text: "Looking for speakers and this computer…"
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        visible: page.service && page.service.devicesLoaded && page.devices.length === 0
        topPadding: Style.space(24)
        horizontalAlignment: Text.AlignHCenter
        text: "No Spotify Connect devices found. Make sure the device is online, then refresh."
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }
  }

  FastScrollHandler {
    parent: devicesScroll.contentItem
    flickable: devicesScroll.contentItem
  }
}
