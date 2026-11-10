pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui

import "Api.js" as Api

Item {
  id: root
  objectName: "media-collection"

  required property var service
  property var sourceItems: []
  property string filterText: ""
  property string sortKey: "default"
  property bool sortDescending: false
  property string contextUri: ""
  property bool showSort: false
  // Off where a header above already says how many there are.
  property bool showCount: true
  property bool showQueue: true
  property bool showPlaylist: true
  property bool showSave: true
  property bool browseContexts: true
  property bool loading: false
  property bool hasMore: false
  property string emptyMessage: "Nothing here yet."
  property string emptyGlyph: "󰝚"
  property string emptyActionText: ""
  readonly property color muted: Api.secondaryTextColor(Commons.Color.foreground,
    Commons.Color.background)
  property real restoredContentY: 0
  property string stateKey: ""
  property bool restoreReady: true
  property bool restoreApplied: false
  property bool keyboardSortSelected: false
  property bool keyboardMoreSelected: false
  property bool keyboardFilterScanSelected: false
  property bool keyboardAtList: false
  property bool keyboardCtrlHeld: false
  property bool keyboardShiftHeld: false
  property bool keyboardAltHeld: false
  property bool keyboardHintsActive: false
  // True only when the keyboard is showing the cursor, not when hover moved it.
  property bool keyboardCursorShown: false
  property var cursorHost: null
  property string keyboardListId: "list"
  property string modelKey: ""
  property bool pointerSeen: false
  property real pointerX: 0
  property real pointerY: 0
  readonly property int listCurrentIndex: mediaList.currentIndex
  readonly property int listCount: mediaList.count
  property alias listContentY: mediaList.contentY
  property bool allowReorder: false
  property bool reorderBusy: false
  property int dragSourceIndex: -1
  property int dragDestinationIndex: -1
  property real dragSceneY: 0
  property int dragAutoScrollDirection: 0

  readonly property var visibleItems: Api.filteredSorted(sourceItems, filterText,
    sortKey, sortDescending)

  // Whatever this list shows is worth keeping on disk, so a rebuilt row redraws
  // from a local file rather than the CDN.
  onVisibleItemsChanged: {
    if (root.service) root.service.keepArtwork(visibleItems)
    applyModel()
  }
  readonly property bool playbackUsesVisibleOrder: Api.playbackUsesVisibleOrder(
    contextUri, filterText, sortKey)
  readonly property string playbackContextUri: Api.playbackContextForView(
    contextUri, filterText, sortKey)
  readonly property var sortKeys: ["default", "name", "artist", "album", "duration",
    "date"]
  readonly property bool canReorder: allowReorder && !reorderBusy
    && String(filterText || "").trim() === "" && sortKey === "default"
    && visibleItems.length > 1
  readonly property var dragItem: dragSourceIndex >= 0
    && dragSourceIndex < visibleItems.length ? visibleItems[dragSourceIndex] : null

  signal activated(var item, var sourceItems, string contextUri)
  signal opened(var item)
  signal queued(var item)
  signal playlistRequested(var item)
  signal saveToggled(var item)
  signal contextRequested(var item, real sceneX, real sceneY, int index,
    var sourceItems, string contextUri, string playbackContextUri)
  signal reorderRequested(int sourceIndex, int destinationIndex)
  signal loadMoreRequested()
  signal emptyActionRequested()
  signal viewStateChanged(string filterText, string sortKey, real contentY)

  readonly property bool filterScanAvailable: scanner.available
  readonly property bool filterScanPaused: scanner.paused
  function continueFilterScan() { scanner.resume() }
  function cancelFilterScan() { scanner.cancel() }
  FilterScanController {
    id: scanner
    query: root.filterText
    active: root.visible && root.service && root.service.uiVisible
    loading: root.loading
    hasMore: root.hasMore
    itemCount: root.sourceItems.length
    cooldownUntil: root.service ? root.service.searchCooldownUntil : 0
    blocked: !root.service || !root.service.accountConnected
      || root.service.lastError !== ""
    onRequestNext: root.loadMoreRequested()
  }

  function sortLabel() {
    if (sortKey === "name") return "Title"
    if (sortKey === "artist") return "Artist"
    if (sortKey === "album") return "Album"
    if (sortKey === "duration") return "Duration"
    if (sortKey === "date" || sortKey === "date-asc") return "Date added"
    return "Original"
  }

  function cycleSort() {
    var index = sortKeys.indexOf(sortKey)
    sortKey = sortKeys[(index + 1) % sortKeys.length]
    viewStateChanged(filterText, sortKey, mediaList.contentY)
  }

  // A new array resets a ListView to the top, which would throw away your place
  // whenever a page loads or a row moves. Only a new list or sort starts over.
  function applyModel() {
    var key = stateKey + "|" + filterText + "|" + sortKey + "|" + sortDescending
    var same = key === modelKey
    var position = mediaList.contentY
    var index = mediaList.currentIndex
    modelKey = key
    mediaList.model = visibleItems
    if (!same) return
    if (index >= 0 && index < mediaList.count) mediaList.currentIndex = index
    mediaList.contentY = Math.max(mediaList.originY, Math.min(position,
      Math.max(mediaList.originY, mediaList.contentHeight - mediaList.height + mediaList.originY)))
  }

  function focusList() {
    mediaList.forceActiveFocus()
    if (mediaList.currentIndex < 0 && mediaList.count > 0) mediaList.currentIndex = 0
  }

  function moveTo(index) {
    mediaList.currentIndex = index
    mediaList.positionViewAtIndex(index, ListView.Contain)
  }

  function moveCurrent(delta) {
    var next = Api.listIndexAfterMove(mediaList.count, mediaList.currentIndex, delta)
    if (next < 0) return false
    moveTo(next)
    return true
  }

  // Rows slide under a pointer that is not moving, and that must not take the
  // cursor away from the keyboard.
  function notePointer(index, scenePoint) {
    var moved = pointerSeen && (Math.abs(scenePoint.x - pointerX) > 1
      || Math.abs(scenePoint.y - pointerY) > 1)
    pointerSeen = true
    pointerX = scenePoint.x
    pointerY = scenePoint.y
    if (!moved) return
    mediaList.currentIndex = index
    if (cursorHost && (!keyboardAtList || keyboardCursorShown))
      cursorHost.setPanelCursor("page", keyboardListId)
  }

  function currentContextAnchor() {
    var index = mediaList.currentIndex
    if (index < 0 || index >= visibleItems.length) return null
    var row = mediaList.currentItem
    var point = row ? row.mapToItem(null, row.width / 2, row.height / 2)
      : ({ x: 0, y: 0 })
    return {
      item: visibleItems[index],
      index: index,
      x: point.x,
      y: point.y,
      items: visibleItems,
      uri: contextUri,
      playbackUri: playbackContextUri
    }
  }

  function activateCurrent() {
    if (mediaList.currentItem) mediaList.currentItem.triggerPrimary()
  }

  function jumpToEdge(toEnd) {
    if (mediaList.count <= 0) return
    moveTo(toEnd ? mediaList.count - 1 : 0)
  }

  function firstVisibleListIndex() {
    if (mediaList.count <= 0) return 0
    var y = mediaList.contentY + 1
    if (y < mediaList.originY) y = mediaList.originY + 1
    var index = mediaList.indexAt(Math.max(1, mediaList.width / 2), y)
    return Api.listHintRowIndex(mediaList.count, index)
  }

  function jumpToFirstVisible() {
    if (mediaList.count <= 0) return
    mediaList.currentIndex = firstVisibleListIndex()
  }

  function blurList() {
    mediaList.focus = false
  }

  function requestMore() {
    if (hasMore && !loading) loadMoreRequested()
  }

  function reorderIndexAtSceneY(sceneY) {
    if (mediaList.count <= 0) return -1
    var top = mediaList.mapToItem(null, 0, 0)
    var bottom = mediaList.mapToItem(null, 0, mediaList.height)
    var center = mediaList.mapToItem(null, mediaList.width / 2, 0)
    var clampedY = Math.max(top.y + 1, Math.min(bottom.y - 1, sceneY))
    var contentPoint = mediaList.contentItem.mapFromItem(null, center.x, clampedY)
    var candidate = mediaList.indexAt(contentPoint.x, contentPoint.y)
    if (candidate >= 0) return candidate

    // The pointer can land in ListView.spacing, where indexAt() intentionally
    // returns -1. Pick the nearest instantiated row in that case.
    var closest = -1
    var closestDistance = Number.MAX_VALUE
    for (var i = 0; i < mediaList.count; i++) {
      var row = mediaList.itemAtIndex(i)
      if (!row) continue
      var rowCenter = row.mapToItem(null, row.width / 2, row.height / 2)
      var distance = Math.abs(rowCenter.y - clampedY)
      if (distance < closestDistance) {
        closest = i
        closestDistance = distance
      }
    }
    if (closest >= 0) return closest
    return contentPoint.y <= mediaList.originY ? 0 : mediaList.count - 1
  }

  function updateReorder(sceneY) {
    if (dragSourceIndex < 0) return
    dragSceneY = sceneY
    dragDestinationIndex = reorderIndexAtSceneY(sceneY)
    var center = mediaList.mapToItem(null, mediaList.width / 2, 0)
    var point = mediaList.mapFromItem(null, center.x, sceneY)
    var edge = Math.min(Style.space(48), mediaList.height / 3)
    dragAutoScrollDirection = point.y < edge ? -1
      : (point.y > mediaList.height - edge ? 1 : 0)
  }

  function beginReorder(index, sceneY) {
    if (!canReorder || index < 0 || index >= visibleItems.length) return
    mediaList.cancelFlick()
    dragSourceIndex = index
    dragDestinationIndex = index
    dragSceneY = sceneY
    dragAutoScrollDirection = 0
  }

  function finishReorder(sceneY, canceled) {
    if (dragSourceIndex < 0) return
    if (!canceled) updateReorder(sceneY)
    var source = dragSourceIndex
    var destination = dragDestinationIndex
    dragSourceIndex = -1
    dragDestinationIndex = -1
    dragAutoScrollDirection = 0
    rememberView()
    if (!canceled && destination >= 0 && destination !== source)
      reorderRequested(source, destination)
  }

  function cancelReorder() {
    finishReorder(dragSceneY, true)
  }

  function rememberView() {
    viewStateChanged(filterText, sortKey, mediaList.contentY)
  }

  function restoreView() {
    if (!restoreReady || restoreApplied || restoredContentY <= 0
        || mediaList.count <= 0) return
    restoreTimer.restart()
  }

  function resetRestore() {
    restoreApplied = false
    if (restoreReady) restoreTimer.restart()
  }

  Timer {
    id: restoreTimer
    interval: 0
    onTriggered: {
      if (!root.restoreReady || root.restoreApplied) return
      if (root.restoredContentY <= 0) {
        mediaList.contentY = mediaList.originY
        root.restoreApplied = true
        return
      }
      if (mediaList.count <= 0) return
      var maximum = Math.max(mediaList.originY,
        mediaList.contentHeight - mediaList.height + mediaList.originY)
      mediaList.contentY = Math.max(mediaList.originY,
        Math.min(maximum, root.restoredContentY))
      root.restoreApplied = true
    }
  }

  Component.onCompleted: {
    applyModel()
    restoreView()
  }
  onRestoredContentYChanged: resetRestore()
  onStateKeyChanged: resetRestore()
  onRestoreReadyChanged: if (restoreReady) resetRestore()
  onCanReorderChanged: if (!canReorder) cancelReorder()
  Component.onDestruction: rememberView()

  Timer {
    interval: 30
    repeat: true
    running: root.dragSourceIndex >= 0 && root.dragAutoScrollDirection !== 0
    onTriggered: {
      var minimum = mediaList.originY
      var maximum = Math.max(minimum,
        mediaList.contentHeight - mediaList.height + mediaList.originY)
      var next = Math.max(minimum, Math.min(maximum,
        mediaList.contentY + root.dragAutoScrollDirection * Style.space(9)))
      if (next === mediaList.contentY) return
      mediaList.contentY = next
      root.updateReorder(root.dragSceneY)
    }
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(6)

    Row {
      id: tools
      width: parent.width
      height: visible ? sortButton.implicitHeight : 0
      visible: root.showSort
      spacing: Style.space(7)

      Button {
        id: sortDirectionButton
        visible: root.sortKey !== "default"
        anchors.verticalCenter: parent.verticalCenter
        iconText: root.sortDescending ? "󰒽" : "󰒼"
        foreground: Commons.Color.foreground
        tooltipText: root.sortDescending ? "Reverse: showing last first"
          : "Reverse: showing first first"
        focusable: false
        onClicked: {
          root.sortDescending = !root.sortDescending
          root.viewStateChanged(root.filterText, root.sortKey, mediaList.contentY)
        }
      }

      Button {
        id: sortButton
        anchors.verticalCenter: parent.verticalCenter
        text: root.sortLabel()
        iconText: "󰒺"
        foreground: Commons.Color.foreground
        tooltipText: "Change sort order"
        focusable: false
        hasCursor: root.keyboardSortSelected
        onClicked: root.cycleSort()
      }

      Text {
        id: countLabel
        visible: root.showCount || root.filterText.trim() !== ""
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.visibleItems.length
          + (root.filterText ? (root.visibleItems.length === 1 ? " match" : " matches")
            : (root.visibleItems.length === 1 ? " item" : " items"))
        color: root.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    ListView {
      id: mediaList
      width: parent.width
      height: Math.max(30, parent.height - tools.height - moreButton.height
        - filterProgress.height
        - parent.spacing * ((tools.visible ? 1 : 0) + (moreButton.visible ? 1 : 0)
          + (filterProgress.visible ? 1 : 0)))
      clip: true
      spacing: Style.space(2)
      reuseItems: true
      cacheBuffer: Style.space(160)
      interactive: root.dragSourceIndex < 0
      activeFocusOnTab: false
      keyNavigationEnabled: false
      highlightFollowsCurrentItem: false
      ScrollBar.vertical: ScrollBar { }
      onMovementEnded: root.rememberView()
      onAtYEndChanged: if (atYEnd && count > 0 && root.hasMore && !root.loading
          && root.filterText.trim() === "") root.loadMoreRequested()
      onCountChanged: {
        root.restoreView()
        if (root.dragSourceIndex >= count) root.cancelReorder()
      }

      FastScrollHandler {
        parent: mediaList
        flickable: mediaList
        onScrolled: root.rememberView()
      }

      Keys.onReturnPressed: function(event) {
        if (!root.keyboardAtList) {
          event.accepted = false
          return
        }
        const row = currentItem as MediaRow
        if (row) row.triggerPrimary()
        event.accepted = true
      }
      Keys.onEnterPressed: function(event) {
        if (!root.keyboardAtList) {
          event.accepted = false
          return
        }
        const row = currentItem as MediaRow
        if (row) row.triggerPrimary()
        event.accepted = true
      }

      delegate: MediaRow {
        id: row
        required property var modelData
        required property int index
        itemData: modelData
        service: root.service
        foreground: Commons.Color.foreground
        accent: Commons.Color.accent
        fontFamily: Style.font.family
        hasCursor: ListView.isCurrentItem && root.keyboardAtList && root.keyboardCursorShown
        hoverPaints: !root.keyboardCursorShown
        browseOnActivate: root.browseContexts && modelData.kind === "context"
        showQueue: root.showQueue
        showPlaylist: root.showPlaylist
        showSave: root.showSave
        reorderEnabled: root.canReorder
        reorderDragging: root.dragSourceIndex === index
        reorderDropIndicator: root.dragDestinationIndex === index
          && root.dragSourceIndex !== index
          ? (index < root.dragSourceIndex ? -1 : 1) : 0
        saved: root.service ? root.service.isSaved(modelData) : false
        artworkEnabled: !root.service || root.service.artworkEnabled
        // The row the keyboard is on says how to reach its actions.
        Loader {
          anchors.fill: parent
          active: root.keyboardHintsActive && row.hasCursor
          sourceComponent: ShortcutHint {
            placement: "inset"
            ctrlHeld: root.keyboardCtrlHeld
            shiftHeld: root.keyboardShiftHeld
            altHeld: root.keyboardAltHeld
            sequences: ["C"]
            active: true
          }
        }
        onPointerMoved: function(scenePoint) { root.notePointer(index, scenePoint) }
        onActivated: function(item) {
          root.activated(item, root.visibleItems, root.playbackContextUri)
        }
        onOpenRequested: function(item) { root.opened(item) }
        onArtistRequested: function(item) { root.opened(item) }
        onAlbumRequested: function(item) { root.opened(item) }
        onQueueRequested: function(item) { root.queued(item) }
        onPlaylistRequested: function(item) { root.playlistRequested(item) }
        onSaveRequested: function(item) { root.saveToggled(item) }
        onContextRequested: function(item, sceneX, sceneY) {
          root.contextRequested(item, sceneX, sceneY, index,
            root.visibleItems, root.contextUri, root.playbackContextUri)
        }
        onReorderDragStarted: function(sceneY) {
          root.beginReorder(index, sceneY)
        }
        onReorderDragMoved: function(sceneY) { root.updateReorder(sceneY) }
        onReorderDragFinished: function(sceneY) {
          root.finishReorder(sceneY, false)
        }
        onReorderDragCanceled: root.cancelReorder()
      }

      Loader {
        anchors.fill: parent
        active: root.visibleItems.length === 0
        sourceComponent: Item {
          // A quick answer should not flash a placeholder first.
          Timer {
            interval: 150
            running: root.loading && !skeleton.shown
            onTriggered: skeleton.shown = true
          }

          Connections {
            target: root
            function onLoadingChanged() { if (!root.loading) skeleton.shown = false }
          }

          Column {
            id: skeleton
            property bool shown: false
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Style.space(2)
            visible: shown && root.loading
            clip: true
            height: parent.height

            Repeater {
              model: 8

              Item {
                id: skeletonRow
                required property int index
                width: skeleton.width
                height: Style.space(46)

                Rectangle {
                  id: skeletonArt
                  x: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(32)
                  height: width
                  radius: Style.spacing.labelGap
                  color: Style.normalFillFor(Commons.Color.foreground, Commons.Color.accent)
                }
                Rectangle {
                  x: skeletonArt.x + skeletonArt.width + Style.space(9)
                  y: Style.space(13)
                  width: Math.min(parent.width * 0.5, Style.space(190 + (skeletonRow.index * 53) % 130))
                  height: Style.space(7)
                  radius: height / 2
                  color: Style.hoverFillFor(Commons.Color.foreground, Commons.Color.accent)
                }
                Rectangle {
                  x: skeletonArt.x + skeletonArt.width + Style.space(9)
                  y: Style.space(27)
                  width: Math.min(parent.width * 0.35, Style.space(110 + (skeletonRow.index * 37) % 90))
                  height: Style.space(6)
                  radius: height / 2
                  color: Style.normalFillFor(Commons.Color.foreground, Commons.Color.accent)
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - Style.space(24), Style.space(380))
            spacing: Style.space(8)
            visible: !skeleton.visible

            Text {
              width: parent.width
              visible: !root.loading
              horizontalAlignment: Text.AlignHCenter
              text: root.emptyGlyph
              textFormat: Text.PlainText
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.display
            }

            Text {
              objectName: "media-collection-empty"
              width: parent.width
              text: root.emptyMessage
              textFormat: Text.PlainText
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Button {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: root.emptyActionText !== "" && !root.loading
              text: root.emptyActionText
              bordered: true
              foreground: Commons.Color.foreground
              onClicked: root.emptyActionRequested()
            }
          }
        }
      }
    }

    Flow {
      id: filterProgress
      width: parent.width
      height: visible ? implicitHeight : 0
      visible: root.filterText.trim() !== "" && root.hasMore
      spacing: Style.space(6)
      Text {
        textFormat: Text.PlainText
        text: "Filtering " + root.sourceItems.length + " loaded items. More remain."
        color: root.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        width: Math.min(implicitWidth, parent.width)
        wrapMode: Text.WordWrap
      }
      Button {
        text: scanner.paused ? "Continue scan" : "Cancel scan"
        enabled: !scanner.blocked && !scanner.waitingForCooldown
        hasCursor: root.keyboardFilterScanSelected
        foreground: Commons.Color.foreground
        onClicked: scanner.paused ? scanner.resume() : scanner.cancel()
      }
    }

    Button {
      id: moreButton
      anchors.horizontalCenter: parent.horizontalCenter
      height: visible ? implicitHeight : 0
      visible: root.hasMore || (root.loading && root.visibleItems.length > 0)
      text: root.loading ? "Loading…" : "Load more"
      foreground: Commons.Color.foreground
      enabled: root.hasMore && !root.loading
      hasCursor: root.keyboardMoreSelected
      onClicked: root.loadMoreRequested()
    }
  }

  BorderSurface {
    id: dragPreview
    x: Style.space(4)
    width: Math.max(40, parent.width - Style.space(8))
    height: Style.space(48)
    y: Math.max(0, Math.min(parent.height - height,
      root.mapFromItem(null, 0, root.dragSceneY).y - height / 2))
    visible: root.dragSourceIndex >= 0 && !!root.dragItem
    enabled: false
    z: 20
    radius: Style.cornerRadius
    color: Style.selectedFillFor(Commons.Color.foreground, Commons.Color.accent)
    borderSpec: Border.controlSpec("selected", Commons.Color.foreground, Commons.Color.accent)
    opacity: 0.94

    Row {
      anchors.fill: parent
      anchors.margins: Style.space(8)
      spacing: Style.space(8)

      Column {
        width: parent.width
        anchors.verticalCenter: parent.verticalCenter

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.dragItem ? String(root.dragItem.name || "Untitled") : ""
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.dragItem ? String(root.dragItem.subtitle || "") : ""
          color: root.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
