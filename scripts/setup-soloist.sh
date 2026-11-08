#!/usr/bin/env bash
set -euo pipefail
source_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
"$source_root/scripts/setup.sh"
python3 "$source_root/scripts/soloist-runtime.py" install
