#!/usr/bin/env bash
set -euo pipefail

# The playback unit is installed for whichever runtime and config directory
# setup chose, so its paths are filled in here rather than assumed.
source_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
runtime_dir=${OMASPOTIFY_RUNTIME_DIR:-"$HOME/.local/lib/omaspotify"}
config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}

# Quoted for systemd, which also expands % specifiers inside the quotes.
systemd_quote() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//%/%%}
  printf '"%s"' "$value"
}

backend=$(systemd_quote "$runtime_dir/omaspotify-backend")
config=$(systemd_quote "$config_root/omaspotify/playback.conf")
unit=$(<"$source_root/systemd/omaspotify.service")
# Quoted so bash cannot read & in a path as "the text that matched".
unit=${unit//@BACKEND_BINARY@/"$backend"}
unit=${unit//@CONFIG_FILE@/"$config"}
printf '%s\n' "$unit"
