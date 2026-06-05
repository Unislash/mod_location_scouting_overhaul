#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src_dir="$repo_root/src"
dist_dir="$repo_root/dist"
default_out="$dist_dir/mod_location_scouting.zip"
out_path="${1:-$default_out}"

if [[ ! -d "$src_dir" ]]; then
    echo "Missing source directory: $src_dir" >&2
    exit 1
fi

mkdir -p "$(dirname "$out_path")"

tmp_path="${out_path}.tmp"
rm -f "$tmp_path" "$out_path"

python3 - "$src_dir" "$tmp_path" <<'PY'
import os
import sys
import zipfile

src_dir = os.path.abspath(sys.argv[1])
out_path = os.path.abspath(sys.argv[2])

with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for root, dirs, files in os.walk(src_dir):
        dirs.sort()
        files.sort()
        for name in files:
            abs_path = os.path.join(root, name)
            rel_path = os.path.relpath(abs_path, src_dir)
            archive.write(abs_path, rel_path)
PY

mv "$tmp_path" "$out_path"
echo "Built $out_path"
