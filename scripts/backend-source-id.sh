#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

source_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_files=(
  backend/Cargo.toml
  backend/Cargo.lock
  rust-toolchain.toml
)

# Sorted explicitly, because the fingerprint must not depend on directory order.
while IFS= read -r source_file; do
  source_files+=("${source_file#"$source_root/"}")
done < <(find "$source_root/backend/src" "$source_root/backend/build.rs" \
  -type f -name '*.rs' 2>/dev/null | sort)

(
  cd "$source_root"
  file_hashes=$(sha256sum -- "${source_files[@]}")
  source_hash=$(printf '%s\n' "$file_hashes" | sha256sum)
  printf '%s\n' "${source_hash%% *}"
)
