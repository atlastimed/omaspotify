import QtQuick
import Quickshell
import "plugin" as Plugin

ShellRoot {
  Plugin.Service { id: spotifyService }
  Plugin.Panel { id: panel; service: spotifyService; width: 1280; height: 800 }
  Plugin.BarWidget { id: widget }
  Timer {
    interval: 20
    running: true
    onTriggered: {
      for (var section of ["centerBegin", "centerEnd", "tray"]) {
        var layout = {}; layout[section] = [{id: spotifyService.pluginId, deviceName: "Placed"}]
        if (!spotifyService.entryInLayout(layout)) throw new Error("Settings lost in " + section)
      }
      spotifyService.applySettings({ deviceName: "Desk" })
      spotifyService.applySettings({})
      if (spotifyService.deviceName !== "Desk")
        throw new Error("A blank settings push reset saved settings")
      spotifyService.playDays = ({ "2026-09-14": 3 })
      spotifyService.libraryCacheFetchedAt = Date.now()
      spotifyService.auth.loggedOut()
      if (!spotifyService.playDays["2026-09-14"])
        throw new Error("A changed client id erased the listening record")
      if (spotifyService.libraryCacheCurrent())
        throw new Error("A changed client id kept an emptied library as fresh")
      spotifyService.forgetPersonalRecord()
      if (spotifyService.libraryCacheCurrent())
        throw new Error("An emptied library was kept as fresh")
      spotifyService.auth.customClientId = "invalid"
      spotifyService.search("smoke-test", "track")
      if (spotifyService.searchLoading || !spotifyService.searchError)
        throw new Error("Search service did not return the authorization error")
      if (!panel.primaryNavigationItems().some(function(item) { return item.id === "search" }))
        throw new Error("Search navigation is missing")
      spotifyService.clearSearch()
      if (spotifyService.searchQuery !== "") throw new Error("Search state did not clear")
      console.log("APP_SMOKE_PASS")
      Qt.quit()
    }
  }
}
