pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

import "Api.js" as Api

// One row in any list. At rest it is just artwork, names and a duration; the
// buttons are only built for the row the pointer or keyboard is on.
BorderSurface {
  id: root

  required property var itemData
  property var service: null
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color muted: Api.secondaryTextColor(Commons.Color.foreground, Commons.Color.background)
  property string fontFamily: Style.font.family
  property bool selected: false
  property bool hasCursor: false
  // Off while the keyboard cursor is on show, so only one row looks current.
  property bool hoverPaints: true
  property bool showPlay: true
  property bool showQueue: false
  property bool showPlaylist: true
  property bool showSave: false
  property bool saved: false
  property bool browseOnActivate: false
  property bool reorderEnabled: false
  property bool reorderDragging: false
  property bool artworkEnabled: true
  property int reorderDropIndicator: 0
  property bool actionsExpanded: false
  readonly property bool hovered: hoverHandler.hovered
  readonly property bool playing: Api.itemIsPlaying(
    service ? service.currentTrackItemUri : "", itemData)
  // Paused still counts as the playing row; only the bars stop moving.
  readonly property bool playingNow: playing && !!service && service.playing
  readonly property bool actionsShown: (hovered && hoverPaints) || hasCursor || selected
    || actionsExpanded

  readonly property bool durationColumnVisible: itemData
    && itemData.kind === "item" && Number(itemData.durationMs) > 0
  readonly property bool saveActionVisible: showSave && itemData
    && !!itemData.uri && itemData.type !== "chapter"
  readonly property bool playlistActionVisible: showPlaylist && itemData
    && ["track", "episode"].indexOf(itemData.type) >= 0
  readonly property bool queueActionVisible: showQueue && itemData
    && ["track", "episode"].indexOf(itemData.type) >= 0
  readonly property bool playActionVisible: showPlay && itemData
    && ["show", "audiobook"].indexOf(itemData.type) < 0
  readonly property real actionSize: Style.space(24)
  readonly property int actionCount: (playlistActionVisible ? 1 : 0)
    + (queueActionVisible ? 1 : 0) + (playActionVisible ? 1 : 0)
  readonly property real saveWidth: saveActionVisible ? actionSize : 0
  readonly property real allActionsWidth: saveWidth + actionCount * actionSize
  readonly property real fixedWidth: (artworkEnabled ? Style.space(32) + contentRow.spacing : 0)
    + (durationColumnVisible ? durationColumn.width + contentRow.spacing : 0)
    + contentRow.spacing
  // Narrow rows give the title room until asked, and keep one button for the rest.
  readonly property bool compactActions: width < Style.space(440)
  readonly property real actionZoneWidth: compactActions
    ? (actionsExpanded ? allActionsWidth : (actionsShown ? actionSize : saveWidth))
    : allActionsWidth

  signal activated(var item)
  signal openRequested(var item)
  signal queueRequested(var item)
  signal playlistRequested(var item)
  signal saveRequested(var item)
  signal artistRequested(var item)
  signal albumRequested(var item)
  signal contextRequested(var item, real sceneX, real sceneY)
  signal reorderDragStarted(real sceneY)
  signal reorderDragMoved(real sceneY)
  signal reorderDragFinished(real sceneY)
  signal reorderDragCanceled()
  signal pointerMoved(point scenePoint)

  function triggerPrimary() {
    if (browseOnActivate) openRequested(itemData)
    else activated(itemData)
  }

  function triggerPlay() { activated(itemData) }

  onItemDataChanged: actionsExpanded = false
  onCompactActionsChanged: if (!compactActions) actionsExpanded = false

  width: parent ? parent.width : implicitWidth
  implicitWidth: Style.space(420)
  implicitHeight: root.artworkEnabled ? Style.space(46) : Style.space(44)
  height: implicitHeight
  radius: Style.cornerRadius
  color: selected || reorderDragging
    ? Style.selectedFillFor(foreground, accent)
    : (hasCursor || reorderDropIndicator !== 0 ? Style.hoverFillFor(foreground, accent)
    : (playing ? Qt.rgba(accent.r, accent.g, accent.b, 0.14)
    : (hovered && hoverPaints ? Style.hoverFillFor(foreground, accent) : "transparent")))
  borderSpec: selected || reorderDragging
    ? Border.controlSpec("selected", foreground, accent)
    : (hasCursor ? Border.controlSpec("hover-cursor", foreground, accent) : Border.none())
  opacity: reorderDragging ? 0.55 : 1

  HoverHandler {
    id: hoverHandler
    onPointChanged: if (hovered) root.pointerMoved(point.scenePosition)
  }

  MouseArea {
    id: rowMouseArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    preventStealing: root.reorderEnabled
    cursorShape: root.reorderEnabled
      ? (reorderGesture ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
      : Qt.PointingHandCursor

    property bool reorderCandidate: false
    property bool reorderGesture: false
    property bool suppressActivation: false
    property real pressSceneY: 0

    function pointerSceneY(mouse) {
      return mapToItem(null, mouse.x, mouse.y).y
    }

    onPressed: function(mouse) {
      suppressActivation = false
      reorderCandidate = mouse.button === Qt.LeftButton && root.reorderEnabled
      reorderGesture = false
      if (reorderCandidate) pressSceneY = pointerSceneY(mouse)
    }

    onPositionChanged: function(mouse) {
      if (!reorderCandidate || !pressed) return
      var sceneY = pointerSceneY(mouse)
      if (!reorderGesture
          && Math.abs(sceneY - pressSceneY) >= Style.space(6)) {
        reorderGesture = true
        suppressActivation = true
        root.reorderDragStarted(pressSceneY)
      }
      if (reorderGesture) root.reorderDragMoved(sceneY)
    }

    onReleased: function(mouse) {
      if (reorderGesture) root.reorderDragFinished(pointerSceneY(mouse))
      reorderCandidate = false
      reorderGesture = false
    }

    onCanceled: {
      if (reorderGesture) root.reorderDragCanceled()
      reorderCandidate = false
      reorderGesture = false
      suppressActivation = false
    }

    onClicked: function(mouse) {
      if (suppressActivation) {
        suppressActivation = false
        return
      }
      if (mouse.button === Qt.RightButton) {
        var scenePoint = root.mapToItem(null, mouse.x, mouse.y)
        root.contextRequested(root.itemData, scenePoint.x, scenePoint.y)
      } else {
        root.triggerPrimary()
      }
    }
  }

  Row {
    id: contentRow
    anchors.fill: parent
    anchors.margins: Style.space(6)
    spacing: Style.space(9)

    Item {
      id: artworkSurface
      width: root.artworkEnabled ? Style.space(32) : 0
      height: width
      anchors.verticalCenter: parent.verticalCenter
      visible: root.artworkEnabled

      Rectangle {
        anchors.fill: parent
        radius: Style.spacing.labelGap
        color: Style.normalFillFor(root.foreground, root.accent)
      }

      RetryImage {
        id: rowArtwork
        anchors.fill: parent
        requestedSource: root.artworkEnabled && root.itemData && root.itemData.imageUrl
          ? (root.service ? root.service.artworkFor(root.itemData.imageUrl)
            : root.itemData.imageUrl) : ""
        retryLimit: 4
        sourceSize.width: 64
        sourceSize.height: 64
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // Rows are recycled; only the current track's art stays in Qt's cache.
        cache: false
        visible: status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: rowArtwork.status !== Image.Ready
        textFormat: Text.PlainText
        text: !root.itemData ? "󰝚"
          : (root.itemData.type === "playlist" ? "󰲸"
          : (root.itemData.type === "artist" ? "󰠃"
          : (root.itemData.type === "album" ? "󰀥"
          : (root.itemData.type === "show" || root.itemData.type === "episode" ? "󰦔"
          : (root.itemData.type === "audiobook" || root.itemData.type === "chapter" ? "󰂺" : "󰝚")))))
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      Loader {
        anchors.fill: parent
        active: root.playing
        sourceComponent: Rectangle {
          color: Qt.rgba(0, 0, 0, 0.55)
          radius: Style.spacing.labelGap

          Row {
            id: playingBars
            anchors.centerIn: parent
            spacing: Style.space(2)
            readonly property real span: Style.space(16)

            Repeater {
              model: [
                { peak: 1.0, beat: 480 },
                { peak: 0.6, beat: 330 },
                { peak: 0.82, beat: 610 }
              ]

              Rectangle {
                id: bar
                required property var modelData
                // The animation drives a level rather than the height, so a
                // paused row settles back to an even row of bars.
                property real level: 0.35
                width: Style.space(3)
                height: playingBars.span * (root.playingNow ? level : 0.35)
                anchors.verticalCenter: parent.verticalCenter
                radius: width / 2
                color: root.accent

                SequentialAnimation on level {
                  running: root.playingNow && root.visible && !Style.reduceMotion
                  loops: Animation.Infinite
                  NumberAnimation {
                    to: bar.modelData.peak
                    duration: bar.modelData.beat
                    easing.type: Easing.InOutSine
                  }
                  NumberAnimation {
                    to: 0.25
                    duration: bar.modelData.beat
                    easing.type: Easing.InOutSine
                  }
                }
              }
            }
          }
        }
      }
    }

    Column {
      width: Math.max(20, contentRow.width - root.fixedWidth - root.actionZoneWidth)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Text {
        id: titleText
        objectName: "media-row-title"
        width: parent.width
        text: root.itemData ? String(root.itemData.name || "Untitled") : "Untitled"
        textFormat: Text.PlainText
        color: root.playing ? root.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: root.selected || root.playing
        elide: Text.ElideRight

        Loader {
          active: root.hovered && titleText.truncated
          sourceComponent: PanelToolTip {
            visible: true
            text: titleText.text
          }
        }
      }

      MediaByline {
        width: parent.width
        itemData: root.itemData
        foreground: root.foreground
        muted: root.playing ? root.foreground : root.muted
        accent: root.accent
        albumColor: root.playing ? root.foreground : root.muted
        fontFamily: root.fontFamily
        fontPixelSize: Style.font.bodySmall
        onArtistRequested: function(item) { root.artistRequested(item) }
        onAlbumRequested: function(item) { root.albumRequested(item) }
        onContextRequested: function(item) { root.openRequested(item) }
      }
    }

    Item {
      id: actionZone
      width: root.actionZoneWidth
      height: root.actionSize
      anchors.verticalCenter: parent.verticalCenter

      // A saved row keeps its heart without the weight of a button.
      Text {
        objectName: "media-row-saved"
        anchors.right: parent.right
        width: root.actionSize
        height: parent.height
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        visible: root.saved && root.saveActionVisible && !actionsLoader.active
        text: "󰋑"
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Loader {
        id: actionsLoader
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        active: root.actionsShown
        sourceComponent: Row {
          spacing: 0

          Button {
            objectName: "media-row-playlist"
            visible: root.playlistActionVisible
              && (!root.compactActions || root.actionsExpanded)
            width: root.actionSize
            height: root.actionSize
            horizontalPadding: 0
            verticalPadding: 0
            iconText: "󱁐"
            foreground: root.foreground
            tooltipText: "Add to playlist"
            onClicked: root.playlistRequested(root.itemData)
          }

          Button {
            objectName: "media-row-queue"
            visible: root.queueActionVisible
              && (!root.compactActions || root.actionsExpanded)
            width: root.actionSize
            height: root.actionSize
            horizontalPadding: 0
            verticalPadding: 0
            iconText: "󰐕"
            foreground: root.foreground
            tooltipText: "Add to queue"
            onClicked: root.queueRequested(root.itemData)
          }

          Button {
            objectName: "media-row-play"
            visible: root.playActionVisible
              && (!root.compactActions || root.actionsExpanded)
            width: root.actionSize
            height: root.actionSize
            horizontalPadding: 0
            verticalPadding: 0
            iconText: "󰐊"
            foreground: root.foreground
            tooltipText: "Play"
            onClicked: root.triggerPlay()
          }

          Button {
            objectName: "media-row-save"
            visible: root.saveActionVisible && (!root.compactActions || root.actionsExpanded)
            width: root.actionSize
            height: root.actionSize
            horizontalPadding: 0
            verticalPadding: 0
            iconText: root.saved ? "󰋑" : "󰋕"
            iconSize: Style.font.bodySmall
            foreground: root.saved ? root.accent : root.foreground
            accent: root.accent
            tooltipText: root.saved ? "Remove from library" : "Save to library"
            onClicked: root.saveRequested(root.itemData)
          }

          Button {
            objectName: "media-row-actions-toggle"
            visible: root.compactActions
            width: root.actionSize
            height: root.actionSize
            horizontalPadding: 0
            verticalPadding: 0
            iconText: root.actionsExpanded ? "󰅖" : "󰇙"
            foreground: root.foreground
            tooltipText: root.actionsExpanded ? "Hide row actions" : "Show row actions"
            onClicked: root.actionsExpanded = !root.actionsExpanded
          }
        }
      }
    }

    // Measured separately, because sizing a Text from its own implicitWidth
    // makes the layout chase itself.
    TextMetrics {
      id: durationMetrics
      font: durationColumn.font
      text: durationColumn.text
    }

    Text {
      id: durationColumn
      objectName: "media-row-duration"
      visible: root.durationColumnVisible
      width: visible ? Math.max(Style.space(30), durationMetrics.width) : 0
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      text: Api.millisecondsToClock(root.itemData ? root.itemData.durationMs : 0)
      textFormat: Text.PlainText
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    height: Math.max(2, Style.space(2))
    y: root.reorderDropIndicator < 0 ? 0 : parent.height - height
    visible: root.reorderDropIndicator !== 0
    color: root.accent
    z: 5
  }
}
