#!/usr/bin/env bash
# Compiles the visualiser's fragment shaders. Each style in shaders/ is put
# behind shaders/common.glsl and baked into the .qsb file Qt loads. The baked
# files are committed, so running the plugin never needs this.
#
# Usage: build-shaders.sh [--check]
#
# --check needs no compiler: it fails when a style's source no longer matches
# the hash recorded the last time it was baked.
set -euo pipefail

source_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shaders=$source_root/shaders
record=$shaders/baked.sha256

source_hashes() {
  local style name
  for style in "$shaders"/*.glsl; do
    name=$(basename -- "$style" .glsl)
    [[ $name == common ]] && continue
    printf '%s  %s\n' "$(cat "$shaders/common.glsl" "$style" | sha256sum | cut -d' ' -f1)" "$name"
  done
}

if [[ ${1:-} == --check ]]; then
  stale=0
  while read -r hash name; do
    [[ -s $shaders/$name.frag.qsb ]] || { echo "build-shaders.sh: $name.frag.qsb is missing" >&2; stale=1; }
    grep -qx "$hash  $name" "$record" 2>/dev/null \
      || { echo "build-shaders.sh: $name changed since it was baked; run scripts/build-shaders.sh" >&2; stale=1; }
  done < <(source_hashes)
  exit "$stale"
fi

qsb=${QSB:-/usr/lib/qt6/bin/qsb}
command -v "$qsb" >/dev/null 2>&1 || { echo "build-shaders.sh: missing qsb (qt6-shadertools)" >&2; exit 127; }

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
replace_if_changed() {
  # Omarchy reloads the plugin on any write, so only touch what changed.
  cmp -s "$1" "$2" 2>/dev/null || cp "$1" "$2"
}
while read -r _ name; do
  cat "$shaders/common.glsl" "$shaders/$name.glsl" > "$work/$name.frag"
  "$qsb" --glsl "300 es,330" --hlsl 50 --msl 12 -o "$work/$name.frag.qsb" "$work/$name.frag"
  replace_if_changed "$work/$name.frag.qsb" "$shaders/$name.frag.qsb"
done < <(source_hashes)
source_hashes > "$work/baked.sha256"
replace_if_changed "$work/baked.sha256" "$record"
