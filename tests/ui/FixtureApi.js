.pragma library

// A small stand-in for the Spotify Web API, so the preview exercises the real
// requests, normalizing and caching with made-up music and no network.

var artDir = ""
var mode = "full"

var TITLES = ["Disappear", "A Long Road Home Through The Quiet Hours", "Satellite",
  "Northern Lights", "Paper Boats", "Slow Motion", "Afterglow", "Glass Rivers",
  "Midnight Transit", "Fable", "Everything In Its Right Place Tonight", "Ember",
  "Cartographer", "Low Tide", "Kintsugi", "Sodium", "Tall Grass", "Weather Report"]
var ARTISTS = ["Lane 8", "Bonobo", "Rival Consoles", "Tycho", "Jon Hopkins", "Nils Frahm"]
var ALBUMS = ["Rise", "Migration", "Persona", "Awake", "Immunity", "All Melody"]
var PLAYLISTS = ["Ambient Space Soundscapes", "Deep focus", "Sunday morning",
  "Running at a steady 170 bpm", "A very long playlist title that keeps going to test elision"]

function art(index) {
  return "file://" + artDir + "/" + (index % 12) + ".png"
}
function image(index) {
  return artDir ? [{ url: art(index), width: 640, height: 640 }] : []
}
function artistRef(index) {
  var at = index % ARTISTS.length
  return { id: "a" + at, uri: "spotify:artist:a" + at, type: "artist", name: ARTISTS[at] }
}
function albumObject(index) {
  var at = index % ALBUMS.length
  return {
    id: "al" + at, uri: "spotify:album:al" + at, type: "album", name: ALBUMS[at],
    album_type: at % 3 ? "album" : "single", release_date: String(2026 - at) + "-03-01",
    total_tracks: 9 + at, artists: [artistRef(at)], images: image(at + 5),
    external_urls: { spotify: "https://open.spotify.invalid/album/al" + at }
  }
}
function artistObject(index) {
  var at = index % ARTISTS.length
  var artist = artistRef(at)
  artist.followers = { total: 120000 + at * 90317 }
  artist.genres = ["ambient", "electronica"]
  artist.images = image(at + 3)
  return artist
}
function trackObject(index) {
  return {
    type: "track", id: "t" + index, uri: "spotify:track:t" + index,
    name: TITLES[index % TITLES.length], duration_ms: 142000 + index * 9137 % 240000,
    explicit: index % 7 === 3, track_number: index + 1, disc_number: 1,
    artists: [artistRef(index)], album: albumObject(index),
    external_urls: { spotify: "https://open.spotify.invalid/track/t" + index }
  }
}
function playlistObject(index) {
  return {
    type: "playlist", id: "p" + index, uri: "spotify:playlist:p" + index,
    name: PLAYLISTS[index % PLAYLISTS.length], description: "Hand-picked for late evenings.",
    owner: { id: "fixture-user", display_name: "Fixture" }, items: { total: 25 + index * 17 },
    snapshot_id: "s" + index, images: image(index + 7),
    external_urls: { spotify: "https://open.spotify.invalid/playlist/p" + index }
  }
}
function range(count, from) {
  var values = []
  for (var i = 0; i < count; i++) values.push(i + (from || 0))
  return values
}
function page(items, total) {
  return { items: items, next: null, total: total === undefined ? items.length : total,
    limit: 50, offset: 0 }
}

function playback() {
  return {
    is_playing: true, progress_ms: 96000, repeat_state: "context", shuffle_state: true,
    device: { id: "0123456789abcdef", name: "Kitchen Sonos", type: "Speaker", is_active: true,
      volume_percent: 62, supports_volume: true },
    context: { uri: "spotify:playlist:p0", type: "playlist" },
    item: trackObject(0)
  }
}

function devices() {
  return { devices: [
    { id: "fedcba9876543210", name: "OmaSpotify", type: "Computer", is_active: false,
      volume_percent: 70, supports_volume: true },
    { id: "0123456789abcdef", name: "Kitchen Sonos", type: "Speaker", is_active: true,
      volume_percent: 62, supports_volume: true },
    { id: "aaaa5555bbbb6666", name: "Pixel 9", type: "Smartphone", is_active: false,
      volume_percent: 80, supports_volume: true }
  ] }
}

// Returns [status, body] for one request.
function respond(method, url) {
  var parsed = String(url).replace(/^https:\/\/api\.spotify\.com\/v1/, "")
  var path = parsed.split("?")[0]
  var query = parsed.indexOf("?") >= 0 ? parsed.slice(parsed.indexOf("?") + 1) : ""
  if (method !== "GET") return [204, null]
  if (path === "/me") return [200, { id: "fixture-user", display_name: "Fixture" }]
  if (path === "/me/player") return mode === "idle" ? [204, null] : [200, playback()]
  if (path === "/me/player/devices") return [200, devices()]
  if (path === "/me/player/queue") return [200, {
    currently_playing: trackObject(0),
    queue: mode === "empty" ? [] : range(12, 5).map(trackObject)
  }]
  if (mode === "empty") {
    if (path === "/me/following") return [200, { artists: { items: [], total: 0 } }]
    if (path === "/search") return [200, { tracks: page([]), artists: page([]) }]
    return [200, page([])]
  }
  if (path === "/me/player/recently-played") return [200, {
    items: range(24).map(function(i) {
      return { track: trackObject(i),
        played_at: new Date(Date.now() - i * 1500000).toISOString() }
    }), next: null
  }]
  if (path === "/me/top/tracks") return [200, page(range(20, 3).map(trackObject))]
  if (path === "/me/top/artists") return [200, page(range(6).map(artistObject))]
  if (path === "/me/tracks") return [200, page(range(60).map(function(i) {
    return { added_at: "2026-10-01T10:00:00Z", track: trackObject(i) }
  }), 60)]
  if (path === "/me/playlists") return [200, page(range(5).map(playlistObject))]
  if (path === "/me/albums") return [200, page(range(6).map(function(i) {
    return { added_at: "2026-09-01T10:00:00Z", album: albumObject(i) }
  }))]
  if (path === "/me/following") return [200, { artists: {
    items: range(6).map(artistObject), total: 6, cursors: { after: null }, next: null
  } }]
  if (path === "/me/shows" || path === "/me/episodes" || path === "/me/audiobooks")
    return [200, page([])]
  if (path === "/me/library/contains") {
    var uris = decodeURIComponent((query.match(/uris=([^&]*)/) || ["", ""])[1]).split(",")
    return [200, uris.map(function(uri, i) { return i % 3 === 0 })]
  }
  var playlistTracks = path.match(/^\/playlists\/([^/]+)\/items$/)
  if (playlistTracks) return [200, page(range(40, 2).map(function(i) {
    return { added_at: "2026-08-01T10:00:00Z", item: trackObject(i), track: trackObject(i) }
  }))]
  var onePlaylist = path.match(/^\/playlists\/p(\d+)$/)
  if (onePlaylist) return [200, playlistObject(Number(onePlaylist[1]))]
  var albumTracks = path.match(/^\/albums\/al(\d+)\/tracks$/)
  if (albumTracks) return [200, page(range(11, Number(albumTracks[1])).map(trackObject))]
  var oneAlbum = path.match(/^\/albums\/al(\d+)$/)
  if (oneAlbum) {
    var album = albumObject(Number(oneAlbum[1]))
    album.tracks = page(range(11, Number(oneAlbum[1])).map(trackObject))
    return [200, album]
  }
  var artistAlbums = path.match(/^\/artists\/a(\d+)\/albums$/)
  if (artistAlbums) return [200, page(range(6).map(albumObject))]
  var oneArtist = path.match(/^\/artists\/a(\d+)$/)
  if (oneArtist) return [200, artistObject(Number(oneArtist[1]))]
  var oneTrack = path.match(/^\/tracks\/t(\d+)$/)
  if (oneTrack) return [200, trackObject(Number(oneTrack[1]))]
  if (path === "/search") {
    var type = (query.match(/type=([^&]*)/) || ["", "track"])[1]
    var body = {}
    body.tracks = page(range(10).map(trackObject), 100)
    if (type.indexOf("artist") >= 0) body.artists = page(range(6).map(artistObject))
    if (type.indexOf("album") >= 0) body.albums = page(range(6).map(albumObject))
    if (type.indexOf("playlist") >= 0) body.playlists = page(range(5).map(playlistObject))
    return [200, body]
  }
  return [404, { error: { status: 404, message: "No fixture for " + path } }]
}
