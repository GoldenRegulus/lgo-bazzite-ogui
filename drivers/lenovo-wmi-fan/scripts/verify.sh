#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf '%s\n' "Usage: $0 LINUX_SOURCE [KERNEL_CONFIG]" >&2
  exit 2
fi

source=$(realpath "$1")
config=${2:+$(realpath "$2")}
script_dir=$(dirname "$(realpath "$0")")
work=$(mktemp -d /tmp/lenovo-wmi-fan-source.XXXXXX)
trap 'rm -rf "$work"' EXIT

if [[ -n $config && ! -r $config ]]; then
  printf 'Cannot read kernel config: %s\n' "$config" >&2
  exit 2
fi

cp -a "$source/." "$work/linux"
"$script_dir/stage-source.sh" "$work/linux"
mkdir "$work/build"

if [[ -n $config ]]; then
  cp -p "$config" "$work/build/.config"
else
  make -C "$work/linux" O="$work/build" ARCH=x86_64 x86_64_defconfig
fi

"$work/linux/scripts/config" --file "$work/build/.config" \
  --enable MODULES \
  --enable DMI \
  --module ACPI_BATTERY \
  --module ACPI_WMI \
  --module HWMON \
  --module KUNIT \
  --module LENOVO_WMI_CAPDATA \
  --module LENOVO_WMI_EVENTS \
  --module LENOVO_WMI_HELPERS \
  --module LENOVO_WMI_TUNING
make -C "$work/linux" O="$work/build" ARCH=x86_64 olddefconfig
make -C "$work/linux" O="$work/build" ARCH=x86_64 prepare
make -C "$work/linux" O="$work/build" ARCH=x86_64 W=1 KCFLAGS=-Werror \
  drivers/platform/x86/lenovo/
printf '%s\n' 'verification=pass'
