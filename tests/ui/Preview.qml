import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as Plugin
import "plugin/Api.js" as Api

// Drives the real Service and Panel through every page with made-up data and
// asks the runner to capture each one. No network or real account is involved.
ShellRoot {
  id: harness

  readonly property string artDir: Quickshell.env("PREVIEW_ART")
  readonly property string outDir: Quickshell.env("PREVIEW_OUT")
  readonly property var only: String(Quickshell.env("PREVIEW_ONLY") || "").split(",").filter(Boolean)

  Plugin.Service { id: service }
  Plugin.Panel { id: panel; service: service }

  function art(index) { return "file://" + artDir + "/" + (index % 12) + ".png" }

  readonly property var titles: ["Disappear", "A Long Road Home Through The Quiet Hours", "Satellite",
    "Northern Lights", "Paper Boats", "Slow Motion", "Afterglow", "Glass Rivers", "Midnight Transit",
    "Fable", "Everything In Its Right Place Tonight", "Ember", "Cartographer", "Low Tide", "Kintsugi"]
  readonly property var artistNames: ["Lane 8", "Bonobo", "Rival Consoles", "Tycho", "Jon Hopkins", "Nils Frahm"]
  readonly property var albumNames: ["Rise", "Migration", "Persona", "Awake", "Immunity", "All Melody"]

  function track(index) {
    var a = index % artistNames.length, b = index % albumNames.length
    return Api.normalizeTrack({
      added_at: "2026-10-" + String(1 + index % 27).padStart(2, "0") + "T10:00:00Z",
      played_at: new Date(Date.now() - index * 1500000).toISOString(),
      track: {
        type: "track", id: "t" + index, uri: "spotify:track:t" + index,
        name: titles[index % titles.length],
        duration_ms: 142000 + index * 9137 % 240000,
        explicit: index % 7 === 3, track_number: index + 1, disc_number: 1,
        artists: [{ id: "a" + a, uri: "spotify:artist:a" + a, type: "artist", name: artistNames[a] }],
        album: { id: "al" + b, uri: "spotify:album:al" + b, type: "album", name: albumNames[b],
          release_date: String(2014 + b) + "-03-01", total_tracks: 11,
          album_type: "album", artists: [{ id: "a" + a, name: artistNames[a], type: "artist" }],
          images: [{ url: art(index), width: 300, height: 300 }] },
        external_urls: { spotify: "https://open.spotify.invalid/track/t" + index }
      }
    }, 96)
  }
  function tracks(count, from) {
    var out = []
    for (var i = 0; i < count; i++) out.push(track(i + (from || 0)))
    return out
  }
  function artistItem(index) {
    return Api.normalizeContext({ type: "artist", id: "a" + index, uri: "spotify:artist:a" + index,
      name: artistNames[index % artistNames.length], followers: { total: 120000 + index * 90317 },
      genres: ["ambient", "electronica"], images: [{ url: art(index + 3), width: 300, height: 300 }] }, 128)
  }
  function albumItem(index) {
    return Api.normalizeContext({ type: "album", id: "al" + index, uri: "spotify:album:al" + index,
      name: albumNames[index % albumNames.length], album_type: index % 3 ? "album" : "single",
      release_date: String(2026 - index) + "-03-01", total_tracks: 9 + index,
      artists: [{ id: "a" + index, name: artistNames[index % artistNames.length], type: "artist" }],
      images: [{ url: art(index + 5), width: 300, height: 300 }] }, 128)
  }
  function playlistItem(index, name) {
    return Api.normalizeContext({ type: "playlist", id: "p" + index, uri: "spotify:playlist:p" + index,
      name: name, description: "Hand-picked for late evenings.", owner: { id: "me", display_name: "Harry" },
      items: { total: 25 + index * 17 }, snapshot_id: "s" + index,
      images: [{ url: art(index + 7), width: 300, height: 300 }] }, 128)
  }

  function seed() {
    var auth = service.auth
    auth.loggedIn = true
    auth.sessionChecked = true
    service.currentUserId = "me"
    service.currentUserName = "Harry"

    var liked = tracks(60)
    service.recentTracks = tracks(24)
    service.topTracks = tracks(20, 3)
    service.topArtists = [0, 1, 2, 3, 4, 5].map(artistItem)
    service.savedTracks = liked
    service.savedTracksLoaded = true
    service.savedAlbums = [0, 1, 2, 3, 4, 5].map(albumItem)
    service.savedAlbumsLoaded = true
    service.followedArtists = [0, 1, 2, 3, 4, 5].map(artistItem)
    service.followedArtistsLoaded = true
    service.playlists = ["Ambient Space Soundscapes", "Deep focus", "Sunday morning",
      "Running — steady 170 bpm", "A very long playlist title that keeps going to test elision in the sidebar"]
      .map(function(name, index) { return playlistItem(index, name) })
    service.playlistsLoaded = true
    service.queue = tracks(12, 5)
    service.queueLoaded = true
    service.homeLoaded = true
    service.apiDevices = [
      { id: "local", name: "OmaSpotify", type: "Computer", is_active: false, volume_percent: 62, supports_volume: true },
      { id: "kitchen", name: "Kitchen Sonos", type: "Speaker", is_active: true, volume_percent: 40, supports_volume: true },
      { id: "phone", name: "Pixel 9", type: "Smartphone", is_active: false, volume_percent: 80, supports_volume: true }
    ].map(function(d) { return ({ id: d.id, name: d.name, type: d.type, active: d.is_active,
      restricted: false, volumePercent: d.volume_percent, supportsVolume: d.supports_volume }) })
    service.devices = service.apiDevices
    service.devicesLoaded = true

    var days = ({}), now = Date.now()
    for (var d = 0; d < 300; d++) {
      var count = Math.floor(Math.max(0, Math.sin(d / 9) * 18 + (d * 7919 % 13) - 4))
      if (count > 0) days[Api.playDayKey(now - d * 86400000)] = count
    }
    service.playDays = days
    seedPlayback()
  }

  function seedPlayback() {
    service.remotePlayback = Api.normalizePlaybackState({
      is_playing: true, progress_ms: 96000, repeat_state: "context", shuffle_state: true,
      device: { id: "kitchen", name: "Kitchen Sonos", type: "Speaker", is_active: true,
        volume_percent: 62, supports_volume: true },
      context: { uri: "spotify:playlist:p0", type: "playlist" },
      item: { type: "track", id: "t0", uri: "spotify:track:t0", name: "Disappear", duration_ms: 268000,
        artists: [{ id: "a0", uri: "spotify:artist:a0", type: "artist", name: "Lane 8" }],
        album: { id: "al0", uri: "spotify:album:al0", type: "album", name: "Rise",
          images: [{ url: art(0), width: 640, height: 640 }] } }
    }, 192)
  }

  // Each step leaves the panel on one page; shot names become file names.
  readonly property var steps: [
    { shot: "home", tab: "home", run: function() { panel.homeType = "recent" } },
    { shot: "home-artists", tab: "home", run: function() { panel.homeType = "artists" } },
    { shot: "library", tab: "library", run: function() { panel.libraryType = "tracks" } },
    { shot: "library-albums", tab: "library", run: function() { panel.libraryType = "albums" } },
    { shot: "playlist", tab: "playlists", run: function() {
      service.selectedPlaylist = service.playlists[0]
      service.playlistItems = harness.tracks(40, 2)
      service.playlistsLoaded = true
    } },
    { shot: "album", tab: "home", run: function() {
      panel.currentTab = "detail"
      service.detailItem = harness.albumItem(1)
      service.detailItems = harness.tracks(11, 4)
      service.detailLoading = false
    } },
    { shot: "artist", tab: "home", run: function() {
      panel.currentTab = "detail"
      service.detailItem = harness.artistItem(0)
      service.detailItems = []
      service.artistAlbums = [0, 1, 2, 3].map(harness.albumItem)
      service.artistSongs = harness.tracks(10, 1)
      service.artistLikedSongs = harness.tracks(4, 6)
      service.detailLoading = false
    } },
    { shot: "search", tab: "search", run: function() {
      panel.searchText = "lane"
      panel.universalSearchActive = true
      service.searchQuery = "lane"
      service.searchResultQuery = "lane"
      service.searchLoadedTypes = ({ track: true })
      var groups = Api.searchGroups({}, 128)
      groups.track = { items: harness.tracks(12), next: "", total: 12 }
      service.searchGroups = groups
    } },
    { shot: "queue", tab: "queue" },
    { shot: "stats", tab: "stats", run: function() {
      service.statsArtists = [0, 1, 2, 3, 4, 5].map(harness.artistItem)
      service.statsTracks = harness.tracks(10)
    } },
    { shot: "devices", tab: "devices" },
    { shot: "settings", tab: "setup" },
    { shot: "nowplaying", tab: "nowplaying", run: function() { panel.nowPlayingExpanded = true } },
    { shot: "shortcuts", tab: "home", run: function() {
      panel.nowPlayingExpanded = false
      panel.homeType = "recent"
      panel.toggleShortcutHelp()
    } }
  ]

  property int stepIndex: -1

  function runStep() {
    stepIndex++
    while (stepIndex < steps.length && only.length && only.indexOf(steps[stepIndex].shot) < 0) stepIndex++
    if (stepIndex >= steps.length) {
      console.log("UI_PREVIEW_DONE")
      Quickshell.execDetached(["swaymsg", "exit"])
      return
    }
    var step = steps[stepIndex]
    try {
      panel.nowPlayingExpanded = false
      panel.universalSearchActive = false
      seedPlayback()
      panel.open(JSON.stringify({ tab: step.tab }))
      if (step.run) step.run()
    } catch (e) {
      console.log("UI_PREVIEW_ERROR", step.shot, e)
    }
    settle.restart()
  }

  Timer {
    id: settle
    interval: Number(Quickshell.env("PREVIEW_SETTLE_MS")) || 1100
    onTriggered: {
      // Requests fail without a network, so keep that noise out of the picture.
      service.lastError = ""
      service.statusMessage = ""
      harness.seedPlayback()
      capture.running = true
    }
  }

  Process {
    id: capture
    command: ["grim", harness.outDir + "/" + (harness.steps[harness.stepIndex] || { shot: "x" }).shot + ".png"]
    onExited: harness.runStep()
  }

  Timer {
    interval: 400
    running: true
    onTriggered: {
      harness.seed()
      harness.runStep()
    }
  }
}
