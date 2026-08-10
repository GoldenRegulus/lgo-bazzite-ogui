#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

if [[ $# -ne 1 ]]; then
	printf '%s\n' "Usage: $0 KUNIT_MODULE" >&2
	exit 2
fi
[[ $EUID -eq 0 ]] || {
	printf '%s\n' 'Run this command as root' >&2
	exit 1
}

module=$(realpath "$1")
[[ -r $module ]]
[[ $(modinfo -F depends "$module") == kunit ]]
[[ -z $(modinfo -F alias "$module") ]]
[[ $(modinfo -F vermagic "$module") == "$(uname -r)"* ]]
if nm "$module" | grep -Eq 'wmi_driver_register|platform_driver_register|acpi_evaluate_object'; then
	printf '%s\n' 'The standalone test contains a hardware registration symbol' >&2
	exit 1
fi

cleanup() {
	rmmod lenovo_wmi_fan_kunit 2>/dev/null || true
	modprobe -r kunit 2>/dev/null || true
}
trap cleanup EXIT
modprobe kunit enable=1 filter_glob=lenovo-wmi-fan
marker=$(date '+%Y-%m-%d %H:%M:%S')
insmod "$module"
log=$(journalctl -k --since "$marker" --no-pager)
printf '%s\n' "$log"
grep -q '# Subtest: lenovo-wmi-fan' <<<"$log"
grep -q '1..6' <<<"$log"
grep -Eq 'ok 6.*lenovo_fan_fullspeed_and_rpm_test' <<<"$log"
if grep -q 'not ok' <<<"$log"; then
	exit 1
fi
rmmod lenovo_wmi_fan_kunit
modprobe -r kunit
trap - EXIT
printf '%s\n' 'result=pass'
