#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

fail() {
  printf '%s\n' "hid-driver: $*" >&2
  exit 1
}

[[ $# -eq 0 ]] || fail "this command does not accept arguments"
[[ $(cat /sys/class/dmi/id/sys_vendor) == LENOVO ]] || fail "unsupported DMI vendor"
[[ $(cat /sys/class/dmi/id/product_name) == 83E1 ]] || fail "unsupported DMI product"
[[ $(cat /sys/class/dmi/id/product_version) == "Legion Go 8APU1" ]] || \
  fail "unsupported DMI version"
