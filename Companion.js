.pragma library

function text(value, limit) { return String(value || "").slice(0, limit || 512) }
function number(value, maximum) {
  return typeof value === "number" && isFinite(value) ? Math.max(0, Math.min(maximum, value)) : 0
}
function artwork(value) {
  var url = text(value, 2048)
  return /^https:\/\/(?:i\.scdn\.co|mosaic\.scdn\.co|image-cdn-[a-z0-9-]+\.spotifycdn\.com)\//i.test(url) ? url : ""
}
function command(line) {
  if (typeof line !== "string" || line.length > 4096) return null
  var data
  try { data = JSON.parse(line) } catch (_) { return null }
  if (!data || data.v !== 1 || typeof data.action !== "string") return null
  if (["playPause", "next", "previous", "shuffle", "repeat", "like"].indexOf(data.action) >= 0)
    return {action: data.action}
  if (data.action === "watch" && typeof data.visible === "boolean"
      && ["", "queue", "devices", "both"].indexOf(data.section) >= 0)
    return {action: "watch", visible: data.visible, section: data.section}
  if (["seek", "volume"].indexOf(data.action) >= 0 && typeof data.value === "number"
      && isFinite(data.value) && data.value >= 0 && data.value <= (data.action === "volume" ? 1 : 604800))
    return {action: data.action, value: data.value}
  if (data.action === "device" && typeof data.value === "string"
      && data.value.length > 0 && data.value.length <= 256 && !/[\x00-\x1f]/.test(data.value))
    return {action: "device", value: data.value}
  return null
}

function snapshot(service) {
  var s = service || {}
  return {
    v: 1, connected: s.accountConnected === true, running: s.hasPlayer === true,
    playing: s.playing === true, title: text(s.title), artist: text(s.artist), album: text(s.album),
    artUrl: s.artworkEnabled === false ? "" : artwork(s.artUrl), uri: text(s.currentTrackItemUri, 256),
    position: number(s.positionSeconds, 604800), length: number(s.lengthSeconds, 604800),
    volume: number(s.volume, 1), shuffle: s.shuffle === true,
    repeat: ["off", "context", "track"].indexOf(s.repeatMode) >= 0 ? s.repeatMode : "off",
    canPlay: s.playbackStartable === true || s.playbackControllable === true,
    canControl: s.playbackControllable === true,
    canVolume: s.volumeSupported === true,
    canLike: s.currentTrackSaveAvailable === true, liked: s.currentTrackSaved === true,
    deviceName: text(s.playbackDeviceName), error: text(s.lastError),
    queueLoading: s.queueLoading === true, devicesLoading: s.devicesLoading === true,
    queueLoaded: s.queueLoaded === true, devicesLoaded: s.devicesLoaded === true,
    queue: (Array.isArray(s.queue) ? s.queue : []).slice(0, 10).map(function(item) {
      return {title: text(item && item.name), artist: text(item && item.subtitle)}
    }),
    devices: (Array.isArray(s.devices) ? s.devices : []).slice(0, 32).map(function(item) {
      var d = item || {}
      return {id: text(d.id, 256), name: text(d.name), type: text(d.type, 64), active: d.active === true,
        restricted: d.restricted === true && d.activationRequired !== true}
    })
  }
}
