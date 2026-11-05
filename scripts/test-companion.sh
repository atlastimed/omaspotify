#!/usr/bin/env bash
set -euo pipefail
source_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
companion_root=${TUNEMARCHY_SOURCE:-"$source_root/../Omarchy-spotify-plugin-integration"}
[[ -f $companion_root/Service.qml ]] || { echo 'Set TUNEMARCHY_SOURCE to a Tunemarchy checkout' >&2; exit 1; }
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/fork" "$test_root/companion" "$test_root/runtime"
chmod 700 "$test_root/runtime"
cp "$source_root/"{CompanionBridge.qml,Companion.js} "$test_root/fork/"
cp "$companion_root/"{Service.qml,Model.js} "$test_root/companion/"
cp "$source_root/tests/integration/Companion.qml" "$test_root/shell.qml"
env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_RUNTIME_DIR="$test_root/runtime" \
  timeout 15s dbus-run-session -- qs --no-color -p "$test_root" > "$test_root/output" 2>&1 || { cat "$test_root/output"; exit 1; }
cat "$test_root/output"
rg -q COMPANION_INTEGRATION_PASS "$test_root/output"
if rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign|Failed to load configuration' "$test_root/output"; then exit 1; fi
