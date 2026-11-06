import QtQuick
import "Api.js" as Api

// An on-demand feed, not a poller. Each step checks at most 25 artists; the
// shared transport handles concurrency and throttling. Empty answers are cached
// too, and a failed request never replaces the last successful answer.
Item {
  id: root
  required property var api
  property var artists: []
  property var records: ({})
  property var items: []
  property double artistsAt: 0
  property int cursor: 0
  property bool loading: false
  property string error: ""
  property bool truncated: false
  property int serial: 0
  property var handle: null
  property int batchSize: 25
  property var now: function() { return Date.now() }
  readonly property bool hasMore: cursor < artists.length || error !== ""
  readonly property string summary: error || (loading ? "Checking releases… " : "")
    + cursor + " of " + artists.length + " followed artists checked"
    + (truncated ? " (first 1,000 artists)" : "")
  signal changed()

  function cancel() {
    serial++
    api.abortRequest(handle)
    handle = null
    loading = false
  }

  function clear() {
    cancel()
    artists = []
    records = ({})
    items = []
    artistsAt = 0
    cursor = 0
    error = ""
    truncated = false
    changed()
  }

  function rebuild() {
    var all = []
    for (var i = 0; i < artists.length; i++) {
      var record = records[String(artists[i].id)]
      if (record && Api.timestampIsFresh(record.at, now(), 604800000)
          && Array.isArray(record.items)) all = all.concat(record.items)
    }
    items = Api.mergeUnique([], all).filter(function(item) {
      return item && item.type === "album" && /^\d{4}(-\d{2}){0,2}$/.test(item.releaseDate)
    }).sort(function(a, b) {
      // Missing month/day means the beginning of that period, not a made-up
      // later date. URI breaks ties so rows do not jump between refreshes.
      var left = (a.releaseDate + "-01-01").slice(0, 10)
      var right = (b.releaseDate + "-01-01").slice(0, 10)
      return right.localeCompare(left) || String(a.uri).localeCompare(String(b.uri))
    }).slice(0, 250)
  }

  function serialize() {
    return JSON.stringify({ version: 1, artists: artists, artistsAt: artistsAt,
      records: records, truncated: truncated })
  }

  function restore(raw) {
    // A late file read must not overwrite this session's work or account reset.
    if (loading || artistsAt || serial) return
    var data = Api.parseJson(raw, null)
    if (!data || data.version !== 1 || !Array.isArray(data.artists)) return
    artists = data.artists.filter(function(a) { return a && a.id && a.type === "artist" }).slice(0, 1000)
    artistsAt = Number(data.artistsAt) || 0
    var kept = {}
    for (var i = 0; i < artists.length; i++) {
      var id = String(artists[i].id)
      var record = data.records && data.records[id]
      if (record && Api.timestampIsFresh(record.at, now(), 604800000)
          && Array.isArray(record.items))
        kept[id] = { at: record.at, items: record.items.slice(0, 10) }
    }
    records = kept
    truncated = data.truncated === true
    rebuild()
  }

  function load() {
    if (loading) return
    cancel()
    error = ""
    loading = true
    var expected = serial
    if (Api.timestampIsFresh(artistsAt, now(), 21600000)) {
      // Revisit cached entries when reopening a complete feed, so its daily
      // expiry is honoured without a background refresh timer.
      if (cursor >= artists.length) cursor = 0
      scan(expected)
      return
    }
    var collected = []
    var visited = {}
    function page(path) {
      if (expected !== root.serial) return
      if (visited[path]) { root.error = "Spotify repeated a page. Try again."; root.loading = false; return }
      visited[path] = true
      root.handle = root.api.request("GET", path,
        path === "/me/following" ? { type: "artist", limit: 50 } : null, null,
        function(status, payload, failure) {
          if (expected !== root.serial) return
          root.handle = null
          if (failure) { root.error = failure; root.loading = false; return }
          var result = Api.normalizeCursorPage(payload && payload.artists,
            function(a) { return Api.normalizeContext(a, 96) })
          collected = Api.mergeUnique(collected, result.items)
          if (result.next && collected.length < 1000) { Qt.callLater(function() { page(result.next) }); return }
          root.truncated = collected.length > 1000 || !!result.next
          root.artists = collected.slice(0, 1000)
          root.artistsAt = root.now()
          root.cursor = 0
          var retained = {}
          for (var i = 0; i < root.artists.length; i++) {
            var id = String(root.artists[i].id)
            if (root.records[id]) retained[id] = root.records[id]
          }
          root.records = retained
          root.rebuild()
          root.changed()
          root.scan(expected)
        }, { priority: "interactive", timeoutMs: 15000, retryRateLimit: false })
    }
    page("/me/following")
  }

  function scan(expected) {
    var fetched = 0
    function next() {
      if (expected !== root.serial) return
      while (root.cursor < root.artists.length) {
        var artist = root.artists[root.cursor]
        var id = String(artist.id)
        var kept = root.records[id]
        if (kept && Api.timestampIsFresh(kept.at, root.now(), 86400000)) { root.cursor++; continue }
        if (fetched >= root.batchSize) break
        fetched++
        var ask = Api.artistAlbumsRequest(artist)
        root.handle = root.api.request("GET", ask.path, ask.query, null,
          function(status, payload, failure) {
            if (expected !== root.serial) return
            root.handle = null
            if (failure) { root.error = failure; root.loading = false; return }
            var result = Api.normalizePage(payload, function(a) { return Api.normalizeContext(a, 96) })
            var updated = Api.shallowCopy(root.records)
            updated[id] = { at: root.now(), items: result.items.slice(0, 10) }
            root.records = updated
            root.cursor++
            root.rebuild()
            root.changed()
            Qt.callLater(next)
          }, { priority: "interactive", timeoutMs: 15000, retryRateLimit: false })
        return
      }
      root.loading = false
    }
    next()
  }
}
