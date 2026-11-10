#!/usr/bin/env bash
set -euo pipefail
source_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
"$source_root/scripts/setup.sh"
python3 "$source_root/scripts/soloist-runtime.py" install
# Only someone choosing to install gets here, and a running player keeps the old backend.
systemctl --user try-restart omaspotify-soloist.service 2>/dev/null || true
