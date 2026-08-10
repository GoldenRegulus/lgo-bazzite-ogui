#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf '%s\n' "Usage: $0 LINUX_SOURCE" >&2
  exit 2
fi

source=$(realpath "$1")
base="$source/drivers/platform/x86/lenovo"

check_hash() {
  local expected=$1
  local file=$2
  local actual

  [[ -r $file ]]
  actual=$(sha256sum "$file" | awk '{print $1}')
  if [[ $actual != "$expected" ]]; then
    printf 'Base hash mismatch: %s\n' "$file" >&2
    exit 1
  fi
}

check_hash f47cbe92f3f8f61501ffc5fb9ed12a0cb756bd57b51ad5d84e6e830f8de49bb5 "$base/wmi-other.c"
[[ ! -e $base/wmi-fan.c ]]
[[ ! -e $base/wmi-legion-fan-helpers.h ]]

printf '%s\n' 'base=opengamingcollective-master-9c37615c0efca8ec4c7d461ef7ae2f4806951ace'
