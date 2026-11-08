#!/usr/bin/env bash
# Every check this project has. CI runs exactly this, so the two cannot drift.
set -euo pipefail

source_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$source_root"

integration=1
case ${1:-} in
  --no-integration) integration=0 ;;
  "") ;;
  *) echo "Usage: scripts/test.sh [--no-integration]" >&2; exit 2 ;;
esac

# Omarchy hot-reloads a plugin when any file in it changes, so builds stay outside.
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/omaspotify/target}
export PYTHONDONTWRITEBYTECODE=1

qmllint=${QMLLINT:-/usr/lib/qt6/bin/qmllint}
qml_test_runner=/usr/lib/qt6/bin/qmltestrunner
for command_name in "$qmllint" "$qml_test_runner" omarchy rg; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "test.sh: missing test command: $command_name" >&2
    exit 1
  }
done

if command -v cargo >/dev/null 2>&1; then
  cargo fmt --manifest-path backend/Cargo.toml --all -- --check
  cargo test --locked --manifest-path backend/Cargo.toml --quiet
  cargo clippy --locked --manifest-path backend/Cargo.toml --all-targets -- -D warnings
fi

omarchy plugin validate .
# Lint every source file so a new one is never missed.
"$qmllint" -I /usr/share/omarchy/shell ./*.js ./*.qml

QT_QPA_PLATFORM=offscreen "$qml_test_runner" \
  -input tests \
  -import "$source_root" \
  -o -,txt

for python_test in tests/test_*.py; do
  python3 "$python_test"
done
tests/test-scripts.sh

# Optional static checks, all present in CI. Each one that is missing is reported.
run_if_available() {
  if command -v "$1" >/dev/null 2>&1; then
    "$@"
  else
    echo "test.sh: skipped, not installed: $1" >&2
  fi
}
run_if_available ruff check --no-cache scripts tests
mapfile -t shell_scripts < <(git ls-files '*.sh')
run_if_available shellcheck "${shell_scripts[@]}"
run_if_available actionlint
run_if_available zizmor --offline --quiet .github/workflows
run_if_available gitleaks dir --no-banner --redact .
run_if_available osv-scanner scan --config backend/osv-scanner.toml -L backend/Cargo.lock

# rg exits 1 for no match and 2 for an error, and an error must not pass as clean.
forbidden_status=0
rg -n 'QtWebEngine|WebEngineView|WebView|playerctl|node_modules' \
  --glob '*.qml' --glob '*.js' --glob '*.sh' --glob '*.service' \
  --glob '!scripts/test.sh' . || forbidden_status=$?
if (( forbidden_status == 0 )); then
  echo "test.sh: forbidden heavyweight runtime dependency found" >&2
  exit 1
elif (( forbidden_status != 1 )); then
  echo "test.sh: could not scan for forbidden dependencies" >&2
  exit 1
fi

if (( integration )); then
  # Never on the live desktop, even when one is available.
  env -u WAYLAND_DISPLAY bash scripts/test-quickshell.sh
  bash scripts/test-companion.sh
fi

echo "All validation and tests passed."
