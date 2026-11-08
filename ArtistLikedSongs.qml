import QtQuick
import "Api.js" as Api

// Resolve the saved-song index through supported single-track requests. Reuse
// metadata already read by the library crawl, and cancel work on navigation.
Item {
  id: root
  required property var api
  property var items: []
  property bool loading: false
  property string error: ""
  property int serial: 0
  property var handle: null
  property var tracks: ({})
  property int trackCount: 0
  readonly property int trackLimit: 2000
  property var now: function() { return Date.now() }

  // Called for every page of the liked-song crawl, so it must not copy the whole
  // map. Objects keep insertion order, so the first key is the oldest.
  function remember(rows) {
    for (var i = 0; i < rows.length; i++) {
      var item = rows[i]
      if (!item || item.type !== "track" || !item.id) continue
      var id = String(item.id)
      if (tracks[id]) delete tracks[id]
      else trackCount++
      tracks[id] = { item: item, at: now() }
    }
    for (var oldest in tracks) {
      if (trackCount <= trackLimit) break
      delete tracks[oldest]
      trackCount--
    }
  }

  function cancel() {
    serial++
    api.abortRequest(handle)
    handle = null
    loading = false
  }

  function clear() {
    cancel()
    items = []
    tracks = ({})
    trackCount = 0
    error = ""
  }

  function load(ids, known) {
    cancel()
    items = []
    error = ""
    remember(known || [])
    var wanted = Array.isArray(ids) ? ids.slice(0, 200) : []
    var expected = serial
    var collected = []
    var at = 0
    loading = wanted.length > 0
    function next() {
      if (expected !== root.serial) return
      while (at < wanted.length) {
        var id = String(wanted[at++])
        var kept = root.tracks[id]
        if (kept && Api.timestampIsFresh(kept.at, root.now(), 86400000)) {
          collected.push(kept.item)
          continue
        }
        root.items = collected.slice()
        root.handle = root.api.request("GET", "/tracks/" + encodeURIComponent(id),
          null, null, function(status, payload, failure) {
            if (expected !== root.serial) return
            root.handle = null
            if (failure && status !== 404) {
              root.error = failure
              root.loading = false
              return
            }
            var item = failure ? null : Api.normalizeTrack(payload, 96)
            if (item) { collected.push(item); root.remember([item]) }
            Qt.callLater(next)
          }, { priority: "interactive", timeoutMs: 15000, retryRateLimit: false })
        return
      }
      root.items = collected
      root.loading = false
    }
    next()
  }
}
