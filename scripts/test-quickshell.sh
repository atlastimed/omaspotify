#!/usr/bin/env bash
set -euo pipefail
source_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -m 700 "$test_root/runtime"
if [[ -n ${WAYLAND_DISPLAY:-} && $WAYLAND_DISPLAY != /* ]]; then
  export WAYLAND_DISPLAY="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
fi
export XDG_RUNTIME_DIR="$test_root/runtime"
export QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1
cp "$source_root/"{AuthManager.qml,Api.js,OAuth.js} "$test_root/"
sed 's|import "../.." as Plugin|import "." as Plugin|' \
  "$source_root/tests/integration/AuthIdentity.qml" > "$test_root/shell.qml"
env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen timeout 15s \
  qs --no-color -p "$test_root" > "$test_root/output" 2>&1 || {
  cat "$test_root/output"
  exit 1
}
rg -q AUTH_IDENTITY_PASS "$test_root/output" || {
  cat "$test_root/output"
  exit 1
}
echo 'Quickshell authorization integration passed.'

mkdir -p "$test_root/soloist/plugin/scripts"
cp "$source_root/SoloistManager.qml" "$test_root/soloist/plugin/"
cp "$source_root/tests/integration/SoloistLifecycle.qml" "$test_root/soloist/shell.qml"
cp "$source_root/tests/integration/soloist-runtime-fixture.py" "$test_root/soloist/plugin/scripts/soloist-runtime.py"
printf '#!/bin/sh\nread -r device\n' > "$test_root/soloist/plugin/scripts/configure-playback.sh"
env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 \
  timeout 15s dbus-run-session --config-file "$source_root/tests/isolated-session.conf" -- qs --no-color -p "$test_root/soloist" > "$test_root/soloist-output" 2>&1 || {
  cat "$test_root/soloist-output"
  exit 1
}
if ! rg -q SOLOIST_LIFECYCLE_PASS "$test_root/soloist-output" || \
  rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign' "$test_root/soloist-output"; then
  cat "$test_root/soloist-output"
  exit 1
fi
echo 'Quickshell Soloist key/start/replacement integration passed.'

mkdir -p "$test_root/app/plugin" "$test_root/state"
cp "$source_root/"*.qml "$source_root/"*.js "$test_root/app/plugin/"
cp -r /usr/share/omarchy/shell/Commons /usr/share/omarchy/shell/Ui "$test_root/app/"
cp "$source_root/tests/integration/AppSmoke.qml" "$test_root/app/shell.qml"
if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
  # Service/authentication tests still use real Quickshell without a compositor.
  sed -i '/Plugin.Panel {/d; /Plugin.BarWidget {/d; /panel.primaryNavigationItems()/,+1d' "$test_root/app/shell.qml"
  app_platform=offscreen
else
  app_platform=wayland
fi
env QT_QPA_PLATFORM="$app_platform" QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/state" \
  timeout 15s dbus-run-session --config-file "$source_root/tests/isolated-session.conf" -- qs --no-color -p "$test_root/app" > "$test_root/app-output" 2>&1 || {
  cat "$test_root/app-output"
  exit 1
}
rg -q APP_SMOKE_PASS "$test_root/app-output" || {
  cat "$test_root/app-output"
  exit 1
}
if rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign|Failed to load configuration' "$test_root/app-output"; then
  exit 1
fi
echo 'Quickshell app smoke test passed.'

mkdir -p "$test_root/sonos/plugin/scripts" "$test_root/sonos-state"
cp "$source_root/"*.qml "$source_root/"*.js "$test_root/sonos/plugin/"
cp "$source_root/tests/integration/SonosControl.qml" "$test_root/sonos/shell.qml"
# Stands in for the speaker: answers each command after a short pause.
cat > "$test_root/sonos/plugin/scripts/spotify-connect-device.py" <<'HELPER'
#!/bin/sh
read -r device; read -r action; read -r value
sleep 0.2
printf '{"id":"%s","status":"controlled","action":"%s"}\n' "$device" "$action"
HELPER
chmod +x "$test_root/sonos/plugin/scripts/spotify-connect-device.py"
env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/sonos-state" \
  timeout 15s dbus-run-session --config-file "$source_root/tests/isolated-session.conf" -- qs --no-color -p "$test_root/sonos" > "$test_root/sonos-output" 2>&1 || {
  cat "$test_root/sonos-output"
  exit 1
}
rg -q SONOS_CONTROL_PASS "$test_root/sonos-output" || {
  cat "$test_root/sonos-output"
  exit 1
}
if rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign' "$test_root/sonos-output"; then
  exit 1
fi
echo 'Quickshell Sonos control test passed.'

mkdir -p "$test_root/local/plugin" "$test_root/local-state" "$test_root/local-runtime/omaspotify"
cp "$source_root/"*.qml "$source_root/"*.js "$test_root/local/plugin/"
cp "$source_root/tests/integration/LocalPlayback.qml" "$test_root/local/shell.qml"
# Stands in for the backend socket, in a private runtime dir so the real
# backend can never receive the test's load command. Records every request.
python3 - "$test_root/local-runtime/omaspotify/backend.sock" "$test_root/local-requests" <<'BACKEND' &
import json, socket, sys
server = socket.socket(socket.AF_UNIX)
server.bind(sys.argv[1])
server.listen(4)
while True:
    connection, _ = server.accept()
    for line in connection.makefile():
        with open(sys.argv[2], "a") as log:
            log.write(line)
        if json.loads(line)["command"] == "disconnect_fixture":
            connection.shutdown(socket.SHUT_RDWR)
            connection.close()
            break
        reply = {"type": "response", "id": json.loads(line)["id"], "ok": True, "result": {}}
        connection.sendall((json.dumps(reply) + "\n").encode())
BACKEND
backend_pid=$!
env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/local-state" \
  XDG_RUNTIME_DIR="$test_root/local-runtime" \
  timeout 15s dbus-run-session --config-file "$source_root/tests/isolated-session.conf" -- qs --no-color -p "$test_root/local" > "$test_root/local-output" 2>&1 || true
kill "$backend_pid" 2>/dev/null || true
rg -q LOCAL_PLAYBACK_SENT "$test_root/local-output" || {
  cat "$test_root/local-output"
  exit 1
}
rg -q '"command":"load".*"offset_uri":"spotify:track:clicked"' "$test_root/local-requests" || {
  echo 'The clicked song never reached the backend as the offset to start from:' >&2
  cat "$test_root/local-requests" >&2
  exit 1
}
echo 'Quickshell local playback test passed.'
