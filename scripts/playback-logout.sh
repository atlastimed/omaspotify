#!/usr/bin/env bash
set -euo pipefail

# Local playback's reusable credential is separate from the Web API refresh
# token. Remove only its exact durable and legacy files on explicit logout.
state_root=${XDG_STATE_HOME:-"$HOME/.local/state"}
cache_root=${XDG_CACHE_HOME:-"$HOME/.cache"}
config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}

[[ $state_root == /* && $state_root != / && $cache_root == /* && $cache_root != / ]] || {
  echo "playback-logout.sh: refusing an unsafe credential path" >&2
  exit 3
}

credential_files=(
  "$state_root/omaspotify/oauth/credentials.json"
  "$state_root/omaspotify/zeroconf/credentials.json"
)
# Early releases kept theirs where spotifyd keeps its own. With a spotifyd of
# the user's own installed, that login is not this plugin's to remove.
if [[ ! -e $config_root/spotifyd ]] && ! command -v spotifyd >/dev/null 2>&1; then
  credential_files+=(
    "$cache_root/spotifyd/oauth/credentials.json"
    "$cache_root/spotifyd/zeroconf/credentials.json"
  )
fi
[[ ${credential_files[0]} == "$state_root/omaspotify/oauth/credentials.json" ]] || exit 3

systemctl --user stop omaspotify.service 2>/dev/null || true
rm -f -- "${credential_files[@]}"
