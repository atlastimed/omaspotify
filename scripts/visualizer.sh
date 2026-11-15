#!/usr/bin/env bash
# Streams cava spectrum frames for the plugin's own playback stream only.
#
# cava is pointed at the PipeWire object serial of the player's output stream,
# so other applications never show up in the visualiser. While no local stream
# exists (nothing playing here, or playback on another Connect device) the
# script prints "idle" instead of frames, looking less often the longer nothing
# plays. When the stream disappears cava is restarted so a new stream is linked
# again.
#
# Usage: visualizer.sh <config-path> [bars] [player-binary-name] [smoothing 0-100]
set -u

config_path=$1
bars=${2:-64}
backend_binary=${3:-omaspotify-backend}
smoothing=${4:-60}
[[ $bars =~ ^[0-9]+$ ]] || bars=64
[[ $smoothing =~ ^[0-9]+$ ]] && (( smoothing <= 100 )) || smoothing=60

command -v cava >/dev/null 2>&1 || exit 127
command -v pw-dump >/dev/null 2>&1 || exit 126
command -v python3 >/dev/null 2>&1 || exit 126
mkdir -p "$(dirname "$config_path")"

# The player's stream is a node. It names its binary itself, or only points at
# the client that does, which is how Soloist appears. A client can carry the
# same media class and is never the stream. A running stream wins over a
# parked one.
find_stream() {
  pw-dump 2>/dev/null | python3 -c '
import json, sys
binary = sys.argv[1]
try:
    objects = json.load(sys.stdin)
except Exception:
    objects = []
def props(item):
    return ((item.get("info") or {}).get("props") or {}) if isinstance(item, dict) else {}
owners = {item.get("id"): props(item).get("application.process.binary")
          for item in objects if isinstance(item, dict)
          and str(item.get("type", "")).endswith("Client")}
found = []
for item in objects:
    if not isinstance(item, dict) or str(item.get("type", "Node")).endswith("Client"):
        continue
    p = props(item)
    if p.get("media.class") != "Stream/Output/Audio":
        continue
    if binary not in (p.get("application.process.binary"), owners.get(p.get("client.id"))):
        continue
    running = (item.get("info") or {}).get("state") == "running"
    found.append((0 if running else 1, item.get("id", ""), p.get("object.serial", "")))
if found:
    found.sort(key=lambda entry: entry[0])
    print(found[0][1], found[0][2])
' "$backend_binary"
}

stream_alive() {
  pw-dump "$1" 2>/dev/null | grep -q "\"object.serial\": $2,"
}

write_config() {
  printf '%s\n' \
    "[general]" "bars = $bars" "framerate = 60" "autosens = 1" \
    "lower_cutoff_freq = 40" "higher_cutoff_freq = 14000" \
    "[input]" "method = pipewire" "source = $1" \
    "[output]" "method = raw" "raw_target = /dev/stdout" "channels = mono" \
    "data_format = ascii" "ascii_max_range = 1000" \
    "bar_delimiter = 59" "frame_delimiter = 10" \
    "[smoothing]" "noise_reduction = $smoothing" "monstercat = 0" \
    > "$config_path"
}

cava_pid=""
nap_pid=""
cleanup() {
  [[ -n $cava_pid ]] && kill "$cava_pid" 2>/dev/null
  [[ -n $nap_pid ]] && kill "$nap_pid" 2>/dev/null
  exit 0
}
trap cleanup TERM INT HUP

# Waiting on a background sleep lets a stop signal through at once. A plain
# sleep would hold it, and cava would go on listening until the sleep ended.
nap() {
  sleep "$1" &
  nap_pid=$!
  wait "$nap_pid" 2>/dev/null
  nap_pid=""
}

idle_wait=1
while true; do
  read -r node serial <<<"$(find_stream)"
  if [[ -z ${serial:-} ]]; then
    printf 'idle\n'
    nap "$idle_wait"
    (( idle_wait < 5 )) && idle_wait=$(( idle_wait + 1 ))
    continue
  fi
  idle_wait=1
  write_config "$serial"
  cava -p "$config_path" &
  cava_pid=$!
  while kill -0 "$cava_pid" 2>/dev/null; do
    nap 2
    if ! stream_alive "$node" "$serial"; then
      kill "$cava_pid" 2>/dev/null
      wait "$cava_pid" 2>/dev/null
      cava_pid=""
      break
    fi
  done
  if [[ -n $cava_pid ]]; then
    wait "$cava_pid" 2>/dev/null
    cava_pid=""
  fi
  nap 0.5
done
