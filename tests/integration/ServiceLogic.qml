import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as Plugin
import "plugin/Api.js" as Api

// Drives the real Service with a fake network. Each step resets the session, so
// a failure in one does not cascade into the next.
ShellRoot {
  id: top

  Plugin.Service { id: svc }

  readonly property string scratch: Quickshell.env("XDG_STATE_HOME") + "/state-file-test"
  property string fileValue: ""

  Plugin.JsonStateFile {
    id: stateFile
    path: top.scratch + "/one.json"
    saveDelay: 10
    encode: function() { return top.fileValue }
  }

  Plugin.JsonStateFile {
    id: unreadFile
    path: top.scratch + "/two.json"
    active: false
    encode: function() { return "replaced" }
    property var reads: []
    onContentRead: function(text) { reads.push(text) }
  }

  Plugin.JsonStateFile {
    id: failingFile
    path: "/proc/nonexistent/state.json"
    encode: function() { return "cannot be written" }
    property int failuresSeen: 0
    onSaveFailed: failuresSeen++
  }

  FileView {
    id: seedFile
    path: top.scratch + "/two.json"
    printErrors: false
  }

  FileView {
    id: reader
    path: top.scratch + "/one.json"
    blockLoading: true
    printErrors: false
  }

  property var log: []
  property var handler: null
  property var held: []
  property var failures: []
  property string current: ""
  property int stepIndex: -1

  function check(condition, message) {
    if (condition) return
    failures.push(current + ": " + message)
    console.log("SERVICE_LOGIC_FAIL " + current + ": " + message)
  }

  function makeXhr() {
    var x = {
      readyState: 0, status: 0, responseText: "", onreadystatechange: null, url: "", method: "",
      open: function(method, url) { x.method = method; x.url = url },
      setRequestHeader: function() {},
      getResponseHeader: function() { return "" },
      abort: function() { x.aborted = true },
      send: function() {
        top.log.push(x.method + " " + x.url.replace("https://api.spotify.com/v1", ""))
        if (top.handler) top.handler(x)
      }
    }
    return x
  }

  function reply(x, status, payload) {
    x.status = status
    x.responseText = payload === null ? "" : JSON.stringify(payload)
    x.readyState = 4
    if (x.onreadystatechange) x.onreadystatechange()
  }

  function later(ms, fn) {
    var timer = Qt.createQmlObject('import QtQuick; Timer { repeat: false }', top)
    timer.interval = ms
    timer.triggered.connect(function() {
      timer.destroy()
      try {
        fn()
      } catch (error) {
        top.check(false, "threw " + error)
      }
    })
    timer.start()
  }

  function waitUntil(condition, timeoutMs, fn) {
    var started = Date.now()
    function poll() {
      if (condition() || Date.now() - started >= timeoutMs) fn()
      else later(25, poll)
    }
    poll()
  }

  function requestsTo(path) {
    return log.filter(function(line) { return line.indexOf(path) >= 0 }).length
  }

  function offsetOf(x) {
    var match = x.url.match(/offset=(\d+)/)
    return match ? Number(match[1]) : 0
  }

  function apiRow(kind, index) {
    return { type: kind, id: kind + index, uri: "spotify:" + kind + ":" + kind + index,
      name: kind + " " + index, images: [], artists: [], owner: { id: "other" } }
  }

  function page(kind, from, count, total) {
    var items = []
    for (var i = from; i < from + count && i < total; i++) {
      var row = apiRow(kind, i)
      items.push(kind === "album" ? { added_at: "2024-01-01T00:00:00Z", album: row }
        : (kind === "show" ? { added_at: "2024-01-01T00:00:00Z", show: row } : row))
    }
    return { items: items, total: total, offset: from,
      next: from + count < total ? "https://api.spotify.com/v1/x?offset=" + (from + count) : null }
  }

  function albums(count, from) {
    var rows = []
    for (var i = 0; i < count; i++)
      rows.push(Api.normalizeContext(apiRow("album", (from || 0) + i), 96))
    return rows
  }

  function login() {
    svc.auth.accessToken = "test-token"
    svc.auth.accessTokenExpiresAt = Date.now() + 3600000
    svc.auth.loggedIn = true
    svc.auth.sessionChecked = true
  }

  function emptyLibrary(x) {
    reply(x, 200, x.url.indexOf("/me/following") >= 0
      ? { artists: { items: [], total: 0, next: null } }
      : { items: [], total: 0, next: null })
  }

  function reset() {
    svc.api.cancelAll()
    svc.api.xhrFactory = makeXhr
    svc.auth.loggedOut()
    login()
    log = []
    held = []
    handler = null
    svc.libraryCacheFetchedAt = 0
    svc.lastError = ""
    svc.statusMessage = ""
    svc.api.lastInteractiveStartedAt = 0
    svc.api.lastBackgroundStartedAt = 0
    svc.api.rateLimitedUntil = 0
  }

  readonly property var steps: [
    { name: "the large caches wait for a panel", run: function(done) {
      top.check(!svc.lazyCachesWanted, "wanted before anything was opened")
      top.check(!svc.queryCacheReady && !svc.releaseCacheReady, "read before anything was opened")
      svc.setUiVisible("full-panel", true)
      top.waitUntil(function() { return svc.queryCacheReady && svc.releaseCacheReady }, 3000, function() {
        top.check(svc.queryCacheReady && svc.releaseCacheReady, "never read after opening")
        svc.setUiVisible("full-panel", false)
        done()
      })
    } },

    { name: "a change during a save is not lost", run: function(done) {
      top.waitUntil(function() { return stateFile.loaded }, 2000, function() {
        top.fileValue = "first"
        stateFile.markDirty()
        stateFile.flush()
        top.check(stateFile.saving, "the save did not start")
        top.fileValue = "second"
        stateFile.markDirty()
        top.waitUntil(function() { return !stateFile.dirty && !stateFile.saving }, 3000, function() {
          top.check(!stateFile.dirty, "never settled")
          reader.reload()
          top.check(reader.text() === "second", "the file holds " + reader.text())
          done()
        })
      })
    } },

    { name: "saving the same text does not hang", run: function(done) {
      stateFile.markDirty()
      stateFile.flush()
      top.check(!stateFile.saving, "waiting for a save that will never report back")
      top.check(!stateFile.dirty, "still marked as unsaved")
      done()
    } },

    { name: "wiping an unread file never brings it back", run: function(done) {
      seedFile.setText("private")
      top.later(200, function() {
        unreadFile.replaceContents()
        top.waitUntil(function() { return unreadFile.loaded && !unreadFile.dirty }, 3000, function() {
          top.check(unreadFile.reads.length === 1 && unreadFile.reads[0] === "",
            "the old content was read back")
          seedFile.reload()
          top.later(200, function() {
            top.check(seedFile.text() === "replaced", "the file holds " + seedFile.text())
            done()
          })
        })
      })
    } },

    { name: "a failed save is reported and tried again", run: function(done) {
      top.waitUntil(function() { return failingFile.loaded }, 2000, function() {
        failingFile.markDirty()
        failingFile.flush()
        top.waitUntil(function() { return failingFile.failuresSeen >= 2 }, 4000, function() {
          top.check(failingFile.failuresSeen >= 2, "failed " + failingFile.failuresSeen + " times")
          top.check(!failingFile.saving, "still marked as saving")
          top.check(failingFile.dirty, "marked as saved")
          done()
        })
      })
    } },

    { name: "opening a page keeps the whole collection", run: function(done) {
      svc.savedAlbums = top.albums(300)
      svc.savedAlbumsLoaded = false
      top.handler = function(x) { top.reply(x, 200, top.page("album", 0, 50, 300)) }
      svc.loadLibrary("albums", false)
      top.later(50, function() {
        top.check(svc.savedAlbums.length === 300, "kept " + svc.savedAlbums.length + " of 300 albums")
        done()
      })
    } },

    { name: "saving edits the list instead of reloading it", run: function(done) {
      svc.savedAlbums = top.albums(300)
      svc.savedAlbumsLoaded = true
      var extra = Api.normalizeContext(top.apiRow("album", 999), 96)
      top.handler = function(x) { top.reply(x, 200, null) }
      svc.toggleSaved(extra)
      top.later(50, function() {
        top.check(svc.savedAlbums.length === 301, "saving left " + svc.savedAlbums.length)
        top.check(svc.savedAlbums[0].uri === extra.uri, "the new album is not first")
        top.check(top.requestsTo("GET /me/albums") === 0, "saving reloaded the collection")
        svc.toggleSaved(extra)
        top.later(50, function() {
          top.check(svc.savedAlbums.length === 300, "removing left " + svc.savedAlbums.length)
          done()
        })
      })
    } },

    { name: "cached rows count as loaded and saved", run: function(done) {
      svc.libraryCacheReady = false
      var album = Api.normalizeContext(top.apiRow("album", 1), 96)
      svc.applyLibraryCacheFile(JSON.stringify({ version: 1, savedAlbums: [album],
        fetchedAt: Date.now() }))
      top.check(svc.savedAlbumsLoaded, "a cached collection is asked for again")
      top.check(svc.isSaved(album), "a saved album reads as not saved")
      done()
    } },

    { name: "library freshness follows the clock", run: function(done) {
      svc.libraryCacheFetchedAt = Date.now() - 6 * 3600000 + 300
      top.check(svc.libraryCacheCurrent(), "should still be current")
      top.later(500, function() {
        top.check(!svc.libraryCacheCurrent(), "still current past six hours")
        top.handler = top.emptyLibrary
        svc.loadSidebarPlaylists()
        top.waitUntil(function() { return top.requestsTo("/me/playlists") > 0 }, 2000, function() {
          top.check(top.requestsTo("/me/playlists") > 0, "an expired library was not refreshed")
          top.waitUntil(function() { return !svc.libraryFillRunning }, 8000, done)
        })
      })
    } },

    { name: "a failed refresh renews nothing", run: function(done) {
      svc.savedAlbums = top.albums(300)
      svc.savedAlbumsLoaded = false
      var fetchedAt = Date.now() - 7 * 3600000
      svc.libraryCacheFetchedAt = fetchedAt
      top.handler = function(x) { top.reply(x, 500, { error: { status: 500, message: "boom" } }) }
      svc.startLibraryFill()
      top.waitUntil(function() { return !svc.libraryFillRunning }, 12000, function() {
        top.check(!svc.libraryFillRunning, "the fill never ended")
        top.check(svc.libraryCacheFetchedAt === fetchedAt, "the age was renewed")
        top.check(!svc.savedAlbumsLoaded, "marked loaded after failing")
        top.check(svc.savedAlbums.length === 300, "what we had was lost")
        done()
      })
    } },

    { name: "only a complete fill counts as fresh", run: function(done) {
      top.handler = function(x) {
        if (x.url.indexOf("/me/playlists") >= 0) top.held.push(x)
        else top.emptyLibrary(x)
      }
      svc.savedAlbums = top.albums(2)
      svc.startLibraryFill()
      top.waitUntil(function() { return top.held.length > 0 }, 4000, function() {
        top.later(400, function() {
          top.check(!svc.libraryCacheCurrent(), "a half-finished fill reads as fresh")
          top.reply(top.held[0], 200, top.page("playlist", 0, 2, 2))
          top.waitUntil(function() { return !svc.libraryFillRunning }, 8000, function() {
            top.check(svc.libraryCacheCurrent(), "a complete fill was not stamped")
            done()
          })
        })
      })
    } },

    { name: "pages keep the library's order", run: function(done) {
      var failedOnce = false
      top.handler = function(x) {
        if (x.url.indexOf("/me/albums") < 0) return top.emptyLibrary(x)
        var offset = top.offsetOf(x)
        if (offset === 50 && !failedOnce) {
          failedOnce = true
          return top.reply(x, 500, { error: { message: "x" } })
        }
        top.reply(x, 200, top.page("album", offset, 50, 200))
      }
      svc.startLibraryFill()
      top.waitUntil(function() { return !svc.libraryFillRunning }, 15000, function() {
        var ids = svc.savedAlbums.map(function(a) { return Number(a.id.replace("album", "")) })
        top.check(ids.length === 200, "got " + ids.length + " albums")
        top.check(ids.every(function(v, i) { return i === 0 || v > ids[i - 1] }),
          "out of order: " + ids.slice(45, 60))
        done()
      })
    } },

    { name: "a complete fill drops what was removed elsewhere", run: function(done) {
      svc.savedAlbums = top.albums(5, 500)
      top.handler = function(x) {
        if (x.url.indexOf("/me/albums") < 0) return top.emptyLibrary(x)
        top.reply(x, 200, top.page("album", 0, 50, 2))
      }
      svc.startLibraryFill()
      top.waitUntil(function() { return !svc.libraryFillRunning }, 8000, function() {
        top.check(svc.savedAlbums.length === 2, "kept " + svc.savedAlbums.length + " albums")
        done()
      })
    } },

    { name: "the crawl restarts after signing back in", run: function(done) {
      top.check(svc.playHistoryReady, "the record was never read")
      top.handler = function(x) { top.held.push(x) }
      svc.crawlSavedTracks(0)
      svc.resumeCandidateLoadedAt = 0
      svc.loadResumeCandidate(true)
      top.later(50, function() {
        top.check(svc.savedTracksCrawling, "the crawl did not start")
        svc.auth.loggedOut()
        top.check(!svc.savedTracksCrawling, "the crawl flag survived signing out")
        top.check(!svc.recentPlaysLoading, "the recent-plays flag survived signing out")
        top.login()
        top.log = []
        top.handler = function(x) { top.reply(x, 200, { items: [], total: 0, next: null }) }
        svc.crawlSavedTracks(0)
        // Background work is spaced apart, so this can take a moment to go out.
        top.waitUntil(function() { return top.requestsTo("/me/tracks") > 0 }, 3000, function() {
          top.check(top.requestsTo("/me/tracks") === 1, "no crawl after signing back in")
          done()
        })
      })
    } },

    { name: "the crawl finishes at its cap", run: function(done) {
      svc.savedTracksThrough = 0
      svc.savedTracksNewest = 12345
      svc.savedTracksOffset = 12050
      svc.crawlSavedTracks(svc.savedTracksOffset)
      top.later(30, function() {
        top.check(top.requestsTo("/me/tracks") === 0, "asked past the cap")
        top.check(svc.savedTracksOffset === 0, "stuck at offset " + svc.savedTracksOffset)
        top.check(svc.savedTracksThrough === 12345, "the watermark did not advance")
        done()
      })
    } },

    { name: "newest likes win when an artist has too many to keep", run: function(done) {
      var older = []
      for (var i = 0; i < 200; i++) older.push("old" + i)
      svc.likedByArtist = ({ "spotify:artist:a": older })
      svc.savedTracksThrough = 0
      top.handler = function(x) {
        top.reply(x, 200, { next: null, items: [{ added_at: "2026-01-01T00:00:00Z",
          track: { type: "track", id: "newest", uri: "spotify:track:newest", name: "n", album: {},
            artists: [{ id: "a", uri: "spotify:artist:a", name: "A" }] } }] })
      }
      svc.crawlSavedTracks(0)
      top.waitUntil(function() { return !svc.savedTracksCrawling }, 3000, function() {
        var ids = svc.likedByArtist["spotify:artist:a"]
        top.check(ids.length === 200, "kept " + ids.length)
        top.check(ids[0] === "newest", "the newest like was dropped")
        done()
      })
    } },

    { name: "a failed crawl tries again", run: function(done) {
      top.handler = function(x) { top.reply(x, 500, { error: { message: "x" } }) }
      svc.crawlSavedTracks(0)
      top.later(30, function() {
        top.check(!svc.savedTracksCrawling, "still crawling")
        top.check(svc.crawlRetryPending, "no retry was scheduled")
        done()
      })
    } },

    { name: "failed artwork is not marked as kept", run: function(done) {
      top.check(svc.artwork.scanned, "the artwork directory was never scanned")
      svc.artwork.enabled = true
      var url = "https://127.0.0.1:9/never-downloaded.png"
      svc.keepArtwork([{ imageUrl: url }])
      top.waitUntil(function() { return svc.artwork.failed[url] === true }, 4000, function() {
        top.check(svc.artworkFor(url) === url, "points at a file that does not exist")
        top.check(svc.artwork.failed[url] === true, "the failure was not noticed")
        svc.artwork.enabled = false
        done()
      })
    } },

    { name: "a poll in flight does not swallow the refetch", run: function(done) {
      top.handler = function(x) {
        if (x.method === "GET") top.held.push(x)
        else top.reply(x, 204, null)
      }
      svc.loadPlaybackState()
      svc.remotePlayerAction("PUT", "/me/player/pause", null)
      top.later(30, function() {
        var playing = { is_playing: true, device: { id: "d", name: "Speaker", is_active: true,
          type: "Speaker" }, item: { type: "track", id: "t", uri: "spotify:track:t", name: "x",
          artists: [], album: {} } }
        var poll = top.held.shift()
        top.reply(poll, 200, playing)
        top.later(30, function() {
          top.check(top.held.length === 1, "no fresh state was asked for")
          top.check(!svc.remotePlayback, "the out-of-date answer was shown")
          if (top.held.length) {
            playing.is_playing = false
            top.reply(top.held.shift(), 200, playing)
          }
          top.check(svc.remotePlayback && svc.remotePlayback.playing === false,
            "the fresh answer was not shown")
          svc.remotePlayback = null
          done()
        })
      })
    } },

    { name: "the chosen stats range wins", run: function(done) {
      svc.statsCache = ({})
      top.handler = function(x) { top.held.push(x) }
      svc.setStatsRange("medium_term")
      svc.setStatsRange("long_term")
      top.later(30, function() {
        var first = top.held
        top.held = []
        first.forEach(function(x) {
          top.reply(x, 200, { items: [{ type: x.url.indexOf("tracks") >= 0 ? "track" : "artist",
            id: "m", uri: "spotify:x:m", name: "medium", artists: [], album: {} }] })
        })
        top.later(30, function() {
          top.check(top.held.length === 2, "the chosen range was not asked for")
          top.check(!svc.statsTracks.length || svc.statsTracks[0].name !== "medium",
            "another range's data is on screen")
          top.held.forEach(function(x) {
            top.reply(x, 200, { items: [{ type: x.url.indexOf("tracks") >= 0 ? "track" : "artist",
              id: "l", uri: "spotify:x:l", name: "long", artists: [], album: {} }] })
          })
          top.later(30, function() {
            top.check(svc.statsRange === "long_term", "the range changed")
            top.check(svc.statsTracks.length === 1 && svc.statsTracks[0].name === "long",
              "the chosen range is not shown")
            done()
          })
        })
      })
    } },

    { name: "opening the panel asks once", run: function(done) {
      svc.currentUserId = "someone"
      svc.libraryCacheFetchedAt = Date.now()
      svc.lastPlayHistoryFetch = 0
      top.handler = function(x) {
        top.later(20, function() { top.reply(x, 200, { items: [], total: 0, next: null }) })
      }
      svc.setUiVisible("full-panel", true)
      svc.activate("home")
      top.later(3000, function() {
        top.check(top.requestsTo("/me/player/recently-played") === 1,
          "recently played was asked " + top.requestsTo("/me/player/recently-played") + " times")
        top.check(top.log.filter(function(line) {
          return line.indexOf("GET /me/player?") === 0 }).length <= 1, "playback was asked twice")
        svc.setUiVisible("full-panel", false)
        done()
      })
    } },

    { name: "another account's record is not inherited", run: function(done) {
      svc.playDays = ({ "2026-09-14": 3 })
      svc.rememberSearch("private term")
      svc.currentUserId = ""
      top.handler = function(x) { top.reply(x, 200, { id: "alice", display_name: "Alice" }) }
      svc.loadProfile()
      top.waitUntil(function() { return svc.currentUserId !== "" }, 3000, function() {
        top.check(svc.currentUserId === "alice", "the profile was not read")
        top.check(!!svc.playDays["2026-09-14"], "the first owner lost their record")
        svc.currentUserId = ""
        top.handler = function(x) { top.reply(x, 200, { id: "bob", display_name: "Bob" }) }
        svc.loadProfile()
        top.waitUntil(function() { return svc.currentUserId !== "" }, 3000, function() {
          top.check(svc.currentUserId === "bob", "the second profile was not read")
          top.check(!svc.playDays["2026-09-14"], "the next account inherited the record")
          top.check(svc.searchHistory.length === 0, "the next account inherited searches")
          done()
        })
      })
    } },

    { name: "signing out forgets personal state", run: function(done) {
      svc.rememberSearch("private term")
      var album = Api.normalizeContext(top.apiRow("album", 1), 96)
      svc.togglePinnedItem(album)
      svc.lastRadioPlaylist = Api.normalizeContext(top.apiRow("playlist", 1), 96)
      svc.forgetPersonalRecord()
      top.check(svc.searchHistory.length === 0, "searches survived")
      top.check(svc.pinnedUris.length === 0, "pins survived")
      top.check(!svc.lastRadioPlaylist, "the last radio survived")
      done()
    } },

    { name: "long liked lists keep their cursor", run: function(done) {
      var rows = []
      for (var i = 0; i < 200; i++) rows.push(Api.normalizeTrack(
        { type: "track", id: "t" + i, uri: "spotify:track:t" + i, name: "t", artists: [], album: {} }, 96))
      svc.savedTracks = rows
      svc.savedTracksNext = "https://api.spotify.com/v1/me/tracks?offset=200"
      top.handler = function(x) {
        var items = []
        for (var j = 200; j < 230; j++) items.push({ added_at: "2024-01-01T00:00:00Z",
          track: { type: "track", id: "t" + j, uri: "spotify:track:t" + j, name: "t",
            artists: [], album: {} } })
        top.reply(x, 200, { items: items, total: 500, next: "https://api.spotify.com/v1/me/tracks?offset=230" })
      }
      svc.loadLibrary("tracks", true)
      top.later(30, function() {
        top.check(svc.savedTracks.length === 230, "got " + svc.savedTracks.length)
        top.check(svc.savedTracksNext !== "", "the list stopped at 200 without saying so")
        done()
      })
    } },

    { name: "removing a repeated song says how many went", run: function(done) {
      svc.currentUserId = "me"
      var playlist = Api.normalizeContext({ type: "playlist", id: "p", uri: "spotify:playlist:p",
        name: "Mine", owner: { id: "me" }, snapshot_id: "s" }, 96)
      var song = Api.normalizeTrack({ type: "track", id: "t", uri: "spotify:track:t", name: "t",
        artists: [], album: {} }, 96)
      svc.selectedPlaylist = playlist
      svc.playlistItems = [song, song]
      top.handler = function(x) {
        if (x.method === "DELETE") top.reply(x, 200, { snapshot_id: "s2" })
        else top.reply(x, 200, { items: [], total: 0, next: null })
      }
      svc.removePlaylistItem(song, 0, playlist)
      top.later(50, function() {
        top.check(svc.statusMessage.indexOf("2") >= 0, "said: " + svc.statusMessage)
        svc.selectedPlaylist = null
        done()
      })
    } },

    { name: "unrelated discovery does not answer device waiters", run: function(done) {
      var answered = 0
      svc.deviceLoadWaiters = [function() { answered++ }]
      svc.devicesLoading = true
      svc.connectManager.refreshed()
      top.check(answered === 0, "a waiter was answered by someone else's discovery")
      top.check(svc.devicesLoading, "a load in progress was marked finished")
      svc.devicesLoading = false
      svc.deviceLoadWaiters = []
      done()
    } },

    { name: "a helper that cannot start does not stay busy", run: function(done) {
      var discovery = 0
      var activation = 0
      var control = 0
      svc.connectManager.pluginDir = "/nonexistent"
      svc.connectManager.refreshFailed.connect(function() { discovery++ })
      svc.connectManager.activationFailed.connect(function() { activation++ })
      svc.connectManager.controlFailed.connect(function() { control++ })
      var device = "0123456789abcdef0123456789abcdef01234567"
      svc.connectManager.refresh()
      svc.connectManager.activate(device, "", "someone")
      svc.connectManager.control(device, "play", "")
      top.later(400, function() {
        top.check(!svc.connectManager.loading, "discovery stayed busy")
        top.check(!svc.connectManager.activating, "activation stayed busy")
        top.check(!svc.connectManager.controlling, "control stayed busy")
        top.check(discovery === 1 && activation === 1, "failures reported "
          + discovery + " and " + activation + " times")
        top.check(control === 1, "control failed " + control + " times")
        done()
      })
    } },

    { name: "a playback failure from before does not undo a newer click", run: function(done) {
      svc.pendingPlaybackBody = null
      svc.radioSerial = 5
      svc.pendingPlayback = { uri: "spotify:track:new" }
      svc.pendingPlaybackBody = { uris: ["spotify:track:new"] }
      svc.pendingPlaybackSerial = 5
      var body = svc.pendingPlaybackBody
      svc.handleLocalPlaybackFailure(body, "", null, 4)
      top.check(svc.pendingPlaybackBody === body, "the newer request was replaced")
      top.check(svc.pendingPlaybackSerial === 5, "the newer serial was replaced")
      svc.clearPendingPlayback()
      done()
    } }
  ]

  Timer {
    id: stepWatchdog
    interval: 30000
    onTriggered: {
      top.check(false, "never finished")
      top.runNext()
    }
  }

  function runNext() {
    stepWatchdog.restart()
    stepIndex++
    if (stepIndex >= steps.length) {
      console.log(failures.length ? "SERVICE_LOGIC_FAILED " + failures.length : "SERVICE_LOGIC_PASS")
      Qt.quit()
      return
    }
    current = steps[stepIndex].name
    console.log("SERVICE_LOGIC_STEP " + current)
    reset()
    try {
      steps[stepIndex].run(function() { later(0, runNext) })
    } catch (error) {
      check(false, "threw " + error)
      later(0, runNext)
    }
  }

  Timer {
    interval: 700
    running: true
    onTriggered: {
      svc.applySettings({ clientId: "0123456789abcdef0123456789abcdef" })
      top.later(700, top.runNext)
    }
  }
}
