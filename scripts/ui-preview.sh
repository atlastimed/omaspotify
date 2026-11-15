#!/usr/bin/env bash
# Screenshots every page using made-up data, inside a private headless
# compositor with no network, so nothing touches the desktop or a real account.
set -euo pipefail

usage() {
  echo "usage: ui-preview.sh [--theme NAME] [--size WxH] [--font-size N] [--only a,b] [--out DIR]" >&2
  exit 2
}

theme=tokyo-night
size=1280x800
out=''
only=''
font_size=''
while (($#)); do
  case $1 in
    --theme) theme=$2; shift 2 ;;
    --size) size=$2; shift 2 ;;
    --only) only=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --font-size) font_size=$2; shift 2 ;;
    *) usage ;;
  esac
done

source_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_path=${OMARCHY_PATH:-/usr/share/omarchy}
theme_dir=$omarchy_path/themes/$theme
[[ -d $theme_dir ]] || { echo "ui-preview.sh: no theme named $theme" >&2; exit 1; }
for tool in sway grim qs magick dbus-run-session unshare; do
  command -v "$tool" >/dev/null || { echo "ui-preview.sh: missing $tool" >&2; exit 1; }
done

# Never inside the checkout: Omarchy hot-reloads a plugin when any file in it changes.
out=${out:-${XDG_CACHE_HOME:-$HOME/.cache}/omaspotify/ui-preview/$theme-$size}
mkdir -p "$out"
out=$(cd -- "$out" && pwd)

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
home=$work/home
mkdir -p "$home/.local/state/omarchy/current" "$home/.config/fontconfig" "$home/.config/omarchy" \
  "$work/runtime" "$work/app/plugin" "$work/art"
chmod 700 "$work/runtime"
cp -r "$theme_dir" "$home/.local/state/omarchy/current/theme"
[[ -f $HOME/.config/fontconfig/fonts.conf ]] && cp "$HOME/.config/fontconfig/fonts.conf" "$home/.config/fontconfig/"
[[ -n $font_size ]] && printf '[font]\nbase-size = %s\n' "$font_size" > "$home/.config/omarchy/shell.toml"

cp "$source_root/"*.qml "$source_root/"*.js "$work/app/plugin/"
cp -r "$omarchy_path/shell/Commons" "$omarchy_path/shell/Ui" "$work/app/"
cp "$source_root/tests/ui/Preview.qml" "$work/app/shell.qml"
cp "$source_root/tests/ui/FixtureApi.js" "$work/app/"
cp -r "$source_root/scripts" "$work/app/plugin/scripts"
cp -r "$source_root/shaders" "$work/app/plugin/shaders"
# Pretend audio, so the visualiser has something to draw: a kick on the low
# end, a wandering middle and some air, as many bands as it was asked for.
mkdir -p "$work/bin"
cat > "$work/bin/pw-dump" <<'FAKE'
#!/usr/bin/env bash
echo '[{"id":1,"info":{"props":{"media.class":"Stream/Output/Audio","application.process.binary":"soloist","object.serial":7}}}]'
FAKE
cat > "$work/bin/cava" <<'FAKE'
#!/usr/bin/env bash
bars=$(sed -n 's/^bars = //p' "$2")
exec awk -v n="${bars:-64}" 'BEGIN {
  for (t = 0; ; t += 0.033) {
    beat = sin(t * 6.2); beat = beat > 0 ? beat ^ 6 : 0
    line = ""
    for (i = 0; i < n; i++) {
      x = i / (n - 1)
      v = exp(-x * 5) * (0.55 + 0.45 * beat) \
        + 0.38 * exp(-((x - 0.38 - 0.1 * sin(t * 1.3)) * 4) ^ 2) \
        + 0.22 * exp(-((x - 0.8) * 5) ^ 2) * (0.5 + 0.5 * sin(t * 9 + i)) \
        + 0.06 * (0.5 + 0.5 * sin(i * 12.9898 + int(t * 20) * 78.233))
      line = line int((v > 1 ? 1 : v) * 1000) ";"
    }
    print line; fflush()
    system("sleep 0.033")
  }
}'
FAKE
chmod +x "$work/bin/pw-dump" "$work/bin/cava"

colors=(1f6f8b 8b1f5e 2d8b1f 8b6d1f 4a1f8b 1f8b7a 8b2d1f 3d5a80 a44a3f 6a994e 7b2cbf 386641)
for i in "${!colors[@]}"; do
  magick -size 320x320 "gradient:#${colors[$i]}-#10131a" -fill '#ffffff22' -draw "circle 160,160 160,60" \
    "$work/art/$i.png"
done

cat > "$work/sway.conf" <<CONF
output HEADLESS-1 resolution $size
default_border none
default_floating_border none
exec dbus-run-session --config-file "$source_root/tests/isolated-session.conf" -- env QT_QPA_PLATFORM=wayland QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 PREVIEW_ART="$work/art" PREVIEW_OUT="$out" PREVIEW_ONLY="$only" qs --no-color -p "$work/app" > "$work/qs.log" 2>&1
CONF

env -i PATH="$work/bin:$PATH" HOME="$home" USER="$USER" LANG="${LANG:-C.UTF-8}" XDG_RUNTIME_DIR="$work/runtime" \
  XDG_STATE_HOME="$home/.local/state" XDG_CACHE_HOME="$home/.cache" XDG_CONFIG_HOME="$home/.config" \
  WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_HEADLESS_OUTPUTS=1 \
  timeout "${PREVIEW_TIMEOUT:-120}" unshare --user --map-current-user --net \
  sway -c "$work/sway.conf" > "$work/sway.log" 2>&1 || true

cp "$work/qs.log" "$out/qs.log" 2>/dev/null || true
cp "$work/sway.log" "$out/sway.log" 2>/dev/null || true
if ! rg -q UI_PREVIEW_DONE "$out/qs.log" 2>/dev/null; then
  echo "ui-preview.sh: did not finish; see $out/qs.log and $out/sway.log" >&2
  exit 1
fi
echo "$out"
