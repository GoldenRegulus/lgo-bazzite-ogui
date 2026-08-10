#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf '%s\n' "Usage: $0 LINUX_SOURCE_COPY" >&2
  exit 2
fi

linux=$(realpath "$1")
script_dir=$(dirname "$(realpath "$0")")
root=$(realpath "$script_dir/..")
source=$root
target="$linux/drivers/platform/x86/lenovo"

"$script_dir/check-source.sh" "$linux"
install -m 0644 "$source/wmi-other.c" "$target/wmi-other.c"

printf '%s\n' 'source=staged'
