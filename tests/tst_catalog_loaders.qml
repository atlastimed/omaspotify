import QtQuick
import QtTest
import ".." as Plugin

TestCase {
  id: test
  name: "CatalogLoaders"
  property var requests: []
  property double clock: 100000000
  QtObject {
    id: fakeApi
    function request(method, path, query, body, callback, options) {
      var handle = { path: path, query: query, callback: callback, aborted: false }
      test.requests = test.requests.concat([handle])
      return handle
    }
    function abortRequest(handle) { if (handle) handle.aborted = true }
  }
  Component { id: likesComponent; Plugin.ArtistLikedSongs { api: fakeApi; now: function() { return test.clock } } }
  Component { id: releasesComponent; Plugin.FollowedReleases { api: fakeApi; now: function() { return test.clock } } }
  function init() { requests = []; clock = 100000000 }
  function track(id) { return { id: id, uri: "spotify:track:" + id, type: "track", name: id, artists: [] } }
  function artist(id) { return { id: id, uri: "spotify:artist:" + id, type: "artist", name: id } }
  function album(id, date) { return { id: id, uri: "spotify:album:" + id, type: "album", name: id, release_date: date, artists: [] } }
  function respond(index, payload, failure) { requests[index].callback(failure ? 429 : 200, payload, failure || "") }
  function test_likedSongsReuseKnownMetadataAndCancelOnNavigation() {
    var likes = createTemporaryObject(likesComponent, test)
    likes.load(["known", "missing", "later"], [track("known")])
    compare(requests.length, 1)
    compare(requests[0].path, "/tracks/missing")
    compare(likes.items[0].id, "known")
    likes.load(["other"], [])
    verify(requests[0].aborted)
    respond(0, track("missing"))
    compare(likes.items.length, 0, "old artist response cannot populate the new page")
    respond(1, track("other"))
    tryCompare(likes, "loading", false)
    compare(likes.items[0].id, "other")
    compare(requests.length, 2, "cancelled load does not fetch the remaining IDs")
  }
  function test_likedSongsStopOnRateLimitAndKeepPartialResults() {
    var likes = createTemporaryObject(likesComponent, test)
    likes.load(["known", "missing", "later"], [track("known")])
    respond(0, null, "Please wait")
    compare(likes.loading, false)
    compare(likes.items.length, 1)
    compare(likes.error, "Please wait")
    compare(requests.length, 1)
  }
  function test_releaseFeedPaginatesFollowsBoundsWorkAndCachesEmptyResults() {
    var feed = createTemporaryObject(releasesComponent, test, { batchSize: 1 })
    feed.load()
    compare(requests[0].path, "/me/following")
    respond(0, { artists: { items: [artist("a")], next: "/me/following?after=a" } })
    tryVerify(function() { return requests.length === 2 })
    respond(1, { artists: { items: [artist("a"), artist("b")], next: null } })
    compare(requests[2].path, "/artists/a/albums")
    compare(requests[2].query.limit, 10)
    respond(2, { items: [] })
    tryCompare(feed, "loading", false)
    verify(feed.hasMore)
    compare(feed.cursor, 1)
    var raw = feed.serialize()
    var restored = createTemporaryObject(releasesComponent, test, { batchSize: 1 })
    restored.restore(raw)
    restored.load()
    compare(requests.length, 4)
    compare(requests[3].path, "/artists/b/albums", "empty artist a is cached across restart")
    respond(3, { items: [album("new", "2026-11-01"), album("old", "2025")] })
    tryCompare(restored, "loading", false)
    compare(restored.items[0].id, "new")
    verify(!restored.hasMore)
    restored.load()
    compare(requests.length, 4, "reopening a fresh feed makes no requests")
  }
  // Each answer would otherwise re-sort thousands of rows on the desktop's main thread.
  function test_releaseFeedRebuildsOncePerBatchNotOncePerArtist() {
    var feed = createTemporaryObject(releasesComponent, test, { batchSize: 3 })
    feed.artists = [artist("a"), artist("b"), artist("c")]
    feed.artistsAt = clock
    var changes = 0
    feed.itemsChanged.connect(function() { changes++ })
    feed.load()
    respond(0, { items: [album("one", "2026-01-01")] })
    wait(0)
    respond(1, { items: [album("two", "2026-02-01")] })
    wait(0)
    respond(2, { items: [album("three", "2026-03-01")] })
    tryCompare(feed, "loading", false)
    compare(changes, 1, "the list was rebuilt per answer")
    compare(feed.items[0].id, "three")
    verify(JSON.stringify(feed.records.a.items[0]).indexOf("description") < 0)
  }

  function test_aClearedFeedIgnoresALateFileRead() {
    var saved = createTemporaryObject(releasesComponent, test)
    saved.artists = [artist("a")]
    saved.artistsAt = clock
    var text = saved.serialize()
    var feed = createTemporaryObject(releasesComponent, test)
    feed.clear()
    feed.restore(text)
    compare(feed.artists.length, 0)
  }

  function test_releaseFeedKeepsStaleResultsOnErrorAndRejectsLateAccountResponse() {
    var feed = createTemporaryObject(releasesComponent, test)
    feed.artists = [artist("a")]
    feed.artistsAt = clock
    feed.records = ({ a: { at: clock - 86400001, items: [{ type: "album", id: "old", uri: "spotify:album:old", releaseDate: "2026" }] } })
    feed.rebuild()
    feed.load()
    respond(0, null, "Please wait")
    compare(feed.items[0].id, "old")
    compare(feed.error, "Please wait")
    verify(feed.hasMore)
    feed.load()
    feed.clear()
    respond(1, { items: [album("late", "2026-11")] })
    compare(feed.items.length, 0)
    compare(feed.artists.length, 0)
    verify(requests[1].aborted)
  }
  function test_releaseFeedDeduplicatesSortsPartialDatesAndPrunesUnfollowedArtists() {
    var feed = createTemporaryObject(releasesComponent, test)
    feed.artists = [artist("a"), artist("b")]
    var common = { type: "album", uri: "spotify:album:same", releaseDate: "2026-01" }
    feed.records = ({ a: { at: clock, items: [common, { type: "album", uri: "spotify:album:year", releaseDate: "2026" }] },
      b: { at: clock, items: [common, { type: "album", uri: "spotify:album:day", releaseDate: "2026-01-02" }] } })
    feed.rebuild()
    compare(feed.items.length, 3)
    compare(feed.items[0].uri, "spotify:album:day")
    feed.load()
    respond(0, { artists: { items: [artist("a")], next: null } })
    compare(feed.items.length, 2)
    compare(feed.records.b, undefined)
  }
}
