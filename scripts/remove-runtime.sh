#!/usr/bin/env bash
set -euo pipefail

purge=0
if [[ ${1:-} == "--purge" ]]; then
  purge=1
  shift
fi
if (( $# > 0 )); then
  echo "Usage: scripts/remove-runtime.sh [--purge]" >&2
  exit 2
fi

config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}
cache_root=${XDG_CACHE_HOME:-"$HOME/.cache"}
state_root=${XDG_STATE_HOME:-"$HOME/.local/state"}
session_runtime_root=${XDG_RUNTIME_DIR:-/tmp}
backend_unit_file="$config_root/systemd/user/omaspotify.service"
config_dir="$config_root/omaspotify"
legacy_cache_dir="$cache_root/spotifyd"
build_cache_dir="$cache_root/omaspotify"   # holds target/ and audio/
state_dir="$state_root/omaspotify"
session_runtime_dir="$session_runtime_root/omaspotify"
runtime_dir=${OMASPOTIFY_RUNTIME_DIR:-"$HOME/.local/lib/omaspotify"}
backend_binary="$runtime_dir/omaspotify-backend"
backend_source_id_file="$runtime_dir/backend-source.sha256"
backend_binary_hash_file="$runtime_dir/backend-binary.sha256"
backend_origin_file="$runtime_dir/backend-origin"

require_safe_path() {
  local label=$1 value=$2

  [[ $value == /* && $value != / ]] || {
    echo "remove-runtime.sh: refusing unsafe $label path: $value" >&2
    exit 3
  }
}

require_safe_path "configuration root" "$config_root"
require_safe_path "cache root" "$cache_root"
require_safe_path "state root" "$state_root"
require_safe_path "session runtime root" "$session_runtime_root"
require_safe_path "backend runtime" "$runtime_dir"

systemctl --user disable --now omaspotify.service >/dev/null 2>&1 || true
for unit in omaspotify-soloist.service omaspotify-soloist-update.timer omaspotify-soloist-update.service; do
  systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
  rm -f -- "$config_root/systemd/user/$unit"
done
rm -f -- "$backend_unit_file" "$backend_binary" \
  "$backend_source_id_file" "$backend_binary_hash_file" "$backend_origin_file" \
  "$runtime_dir/soloist" "$runtime_dir/soloist-runtime.py" "$runtime_dir/soloist-build.json" \
  "$runtime_dir/.soloist-install.lock"
# With no user bus the rest of the removal still has to happen.
systemctl --user daemon-reload >/dev/null 2>&1 || true
systemctl --user reset-failed omaspotify.service >/dev/null 2>&1 || true

if [[ -d $config_dir ]]; then
  if (( purge )); then
    [[ $config_dir == "$config_root/omaspotify" ]] || exit 3
    rm -rf -- "$config_dir"
    echo "Removed playback configuration."
  else
    backup="${config_dir}.bak.$(date -u +%Y%m%d%H%M%S)"
    mv -- "$config_dir" "$backup"
    echo "Moved configuration to: $backup"
  fi
fi

if (( purge )); then
  # Releases before 1.0.3 cached playback credentials and audio here.
  if [[ -d $legacy_cache_dir ]]; then
    [[ $legacy_cache_dir == "$cache_root/spotifyd" ]] || exit 3
    rm -rf -- "$legacy_cache_dir"
    echo "Removed cached credentials and audio."
  fi
  if [[ -d $build_cache_dir ]]; then
    [[ $build_cache_dir == "$cache_root/omaspotify" ]] || exit 3
    rm -rf -- "$build_cache_dir"
    echo "Removed backend build cache."
  fi
  if [[ -d $state_dir ]]; then
    [[ $state_dir == "$state_root/omaspotify" ]] || exit 3
    rm -rf -- "$state_dir"
    echo "Removed durable playback authorization and session state."
  fi
  if [[ -d $session_runtime_dir ]]; then
    [[ $session_runtime_dir == "$session_runtime_root/omaspotify" ]] || exit 3
    rm -rf -- "$session_runtime_dir"
    echo "Removed playback sockets and temporary receiver state."
  fi
  if [[ -d $runtime_dir ]]; then
    # Only what setup put here, in case the directory was set to a shared one.
    rm -rf -- "$runtime_dir"/.soloist-*
    rm -f -- "$runtime_dir"/.omaspotify-*
    if rmdir -- "$runtime_dir" 2>/dev/null; then
      echo "Removed installed playback backend."
    else
      echo "Kept unknown files in backend directory: $runtime_dir" >&2
    fi
  fi
  for backup in "$config_root"/omaspotify.bak.*; do
    [[ -e $backup ]] || continue
    rm -rf -- "$backup"
    echo "Removed old configuration backup: $backup"
  done
  if command -v secret-tool >/dev/null 2>&1; then
    keyring_failed=0
    for kind in refresh-token soloist-api-key; do
      # Exit 1 alone also means nothing matched; only an error message means the
      # keyring could not be reached and the secret is still there.
      if ! keyring_error=$(secret-tool clear service omaspotify kind "$kind" 2>&1 >/dev/null) \
          && [[ -n $keyring_error ]]; then
        keyring_failed=1
      fi
    done
    if (( keyring_failed )); then
      echo "Could not reach the desktop keyring; OmaSpotify entries may remain." >&2
    else
      echo "Cleared matching OmaSpotify keyring entries."
    fi
  fi
else
  rmdir -- "$runtime_dir" 2>/dev/null || true
fi

echo "Runtime integration removed."
