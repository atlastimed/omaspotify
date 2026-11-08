import QtQuick
import Quickshell
import "plugin" as Plugin
import "plugin/Api.js" as Api
import "FixtureApi.js" as Fixture

// Loads the real Panel and every page, answers the real requests with made-up
// music, and walks the keyboard cursor over each page. The runner fails this on
// any warning in the log, which is how binding loops and bad references show.
ShellRoot {
  id: harness

  Plugin.Service { id: service }
  Plugin.Panel { id: panel; service: service }

  Component {
    id: fakeRequest

    QtObject {
      property int readyState: 0
      property int status: 0
      property string responseText: ""
      property var onreadystatechange: null
      property string method: "GET"
      property string url: ""

      function open(requestMethod, requestUrl) {
        method = requestMethod
        url = requestUrl
      }
      function setRequestHeader() {}
      function getResponseHeader() { return "" }
      function abort() {}
      function send() {
        var result = Fixture.respond(method, url)
        status = result[0]
        responseText = result[1] === null ? "" : JSON.stringify(result[1])
        readyState = XMLHttpRequest.DONE
        if (onreadystatechange) onreadystatechange()
      }
    }
  }

  readonly property var tabs: ["home", "library", "playlists", "search", "queue", "stats",
    "devices", "setup", "discover", "album", "artist", "nowplaying"]
  property int tabIndex: -1
  property int moves: 0

  function signIn() {
    var auth = service.auth
    auth.accessToken = "fixture-token"
    auth.accessTokenExpiresAt = Date.now() + 86400000
    auth.loggedIn = true
    auth.sessionChecked = true
  }

  function openNextTab() {
    tabIndex++
    if (tabIndex >= tabs.length) {
      if (moves < tabs.length) throw new Error("The cursor had nowhere to go")
      console.log("PAGES_SMOKE_PASS", moves, "cursor moves")
      Qt.quit()
      return
    }
    harness.signIn()
    panel.nowPlayingExpanded = false
    var tab = tabs[tabIndex]
    if (tab === "album") panel.openItem(Api.normalizeContext(Fixture.albumObject(1), 128))
    else if (tab === "artist") panel.openItem(Api.normalizeContext(Fixture.artistObject(0), 128))
    else if (tab === "nowplaying") panel.nowPlayingExpanded = true
    else panel.chooseTab(tab)
    walk.start()
  }

  function fail(reason) {
    console.log("PAGES_SMOKE_FAIL", reason)
    Qt.quit()
  }

  // A page arriving replaces the list's array, and that used to reset your place.
  function checkListKeepsItsPlace() {
    var collection = panel.pageCollection()
    if (!collection || collection.listCount < 40) return fail("the library did not load")
    collection.listContentY = 600
    collection.moveCurrent(1)
    var position = collection.listContentY
    var index = collection.listCurrentIndex
    service.savedTracks = service.savedTracks.concat([Api.normalizeTrack(
      { track: Fixture.trackObject(900) }, 96)])
    if (collection.listCount < 41) return fail("the new row never arrived")
    if (Math.abs(collection.listContentY - position) > 1)
      return fail("the list jumped from " + position + " to " + collection.listContentY)
    if (collection.listCurrentIndex !== index) return fail("the list lost its current row")
  }

  // Sidebar rows have a menu of their own, reachable from the keyboard.
  function checkSidebarKeyboard() {
    if (!service.sidebarItems.length) return
    panel.panelCursorRegion = "sidebar"
    panel.panelCursorAction = "sidebar-playlists"
    panel.showKeyboardCursor()
    if (!panel.openCurrentContextMenu()) return fail("no menu for a sidebar row")
    if (!panel.contextFromSidebar) return fail("the menu did not know it came from the sidebar")
    panel.dismissTransientPopup()
    var before = service.librarySort
    panel.panelCursorAction = "lib-sort"
    panel.activatePanelCursor()
    if (service.librarySort === before) return fail("the sort control did nothing")
    service.setLibrarySort(before)
  }

  // With hints on, so the hint path runs too, then once more with them off.
  function walkCursor() {
    panel.latchShortcutMode("Ctrl+Left")
    panel.showKeyboardCursor()
    var regions = panel.panelCursorRegions()
    for (var r = 0; r < regions.length; r++) {
      panel.panelCursorRegion = regions[r]
      panel.ensurePanelCursor(regions[r])
      var actions = panel.regionCursorActions(regions[r])
      for (var a = 0; a < actions.length; a++) {
        panel.movePanelCursor(1)
        panel.refreshCursorState()
        moves++
      }
    }
    panel.clearShortcutMode()
    panel.refreshCursorState()
  }

  Timer {
    id: walk
    interval: 200
    onTriggered: {
      if (harness.tabs[harness.tabIndex] === "library") {
        harness.checkListKeepsItsPlace()
        harness.checkSidebarKeyboard()
      }
      harness.walkCursor()
      next.start()
    }
  }

  Timer {
    id: next
    interval: 30
    onTriggered: harness.openNextTab()
  }

  Timer {
    interval: 100
    running: true
    onTriggered: {
      service.api.xhrFactory = function() { return fakeRequest.createObject(harness) }
      service.auth.customClientId = "0123456789abcdef0123456789abcdef"
      started.start()
    }
  }

  Timer {
    id: started
    interval: 300
    onTriggered: {
      harness.signIn()
      panel.open("{}")
      harness.openNextTab()
    }
  }

  Timer {
    interval: 28000
    running: true
    onTriggered: {
      console.log("PAGES_SMOKE_FAIL timed out on", harness.tabs[harness.tabIndex])
      Qt.quit()
    }
  }
}
