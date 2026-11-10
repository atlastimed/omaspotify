#!/usr/bin/env bash
# qmllint against the real Omarchy controls. Quickshell makes the qs.* modules up
# at runtime, so without this path every shared control is an unknown type and
# real mistakes drown in a thousand false warnings.
set -euo pipefail

source_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_path=${OMARCHY_PATH:-/usr/share/omarchy}
qmllint=${QMLLINT:-/usr/lib/qt6/bin/qmllint}

imports=$(mktemp -d)
trap 'rm -rf -- "$imports"' EXIT
mkdir -p "$imports/qs"
ln -s "$omarchy_path/shell/Ui" "$imports/qs/Ui"
ln -s "$omarchy_path/shell/Commons" "$imports/qs/Commons"

cd "$source_root"
# Style groups its tokens in plain objects qmllint cannot see into.
lint_status=0
raw=$("$qmllint" -I "$imports" ./*.js ./*.qml 2>&1) || lint_status=$?
report=$(rg -v 'not found on type "QObject"' <<<"$raw" || true)
if rg -q '^Warning:' <<<"$report"; then
  rg -A3 '^Warning:' <<<"$report"
  echo "lint-qml.sh: fix the warnings above" >&2
  exit 1
fi
# A linter that could not run must not pass for a clean one.
if (( lint_status != 0 )) && ! rg -q '^Warning:' <<<"$raw"; then
  printf '%s\n' "$raw" >&2
  echo "lint-qml.sh: qmllint failed to run (exit $lint_status)" >&2
  exit 1
fi
