#!/usr/bin/env bash
set -euo pipefail
source_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
companion_root=${TUNEMARCHY_SOURCE:-"$source_root/tests/fixtures/companion"}
[[ -f $companion_root/Service.qml ]] || { echo 'Set TUNEMARCHY_SOURCE to a Tunemarchy checkout' >&2; exit 1; }
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/fork" "$test_root/companion" "$test_root/runtime" "$test_root/home"
chmod 700 "$test_root/runtime"
# Nothing under the real home is read or written.
export HOME="$test_root/home"
export XDG_CACHE_HOME="$HOME/.cache" XDG_STATE_HOME="$HOME/.local/state" XDG_CONFIG_HOME="$HOME/.config"
cp "$source_root/"{CompanionBridge.qml,Companion.js} "$test_root/fork/"
cp "$companion_root/Service.qml" "$test_root/companion/"
if [[ -f $companion_root/Model.js ]]; then cp "$companion_root/Model.js" "$test_root/companion/"; fi
cp "$source_root/tests/integration/Companion.qml" "$test_root/shell.qml"
env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_RUNTIME_DIR="$test_root/runtime" \
  timeout 15s dbus-run-session --config-file "$source_root/tests/isolated-session.conf" -- qs --no-color -p "$test_root" > "$test_root/output" 2>&1 || { cat "$test_root/output"; exit 1; }
cat "$test_root/output"
rg -q COMPANION_INTEGRATION_PASS "$test_root/output"
if rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign|Failed to load configuration' "$test_root/output"; then exit 1; fi
