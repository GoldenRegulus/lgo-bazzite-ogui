#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 MODULE" >&2
  exit 2
fi
if [ "$(id -u)" -ne 0 ]; then
  echo "Run this command as root" >&2
  exit 1
fi

module=$(realpath "$1")
[ -r "$module" ]
[ "$(modinfo -F depends "$module")" = kunit ]
[ -z "$(modinfo -F alias "$module")" ]
vermagic=$(modinfo -F vermagic "$module")
[[ "$vermagic" == "$(uname -r) "* ]]
symbols=$(nm "$module")
if grep -Eq \
  'hid_register_driver|__hid_register_driver|usb_register|module_hid_driver' \
  <<<"$symbols"; then
  echo "The standalone test contains a hardware registration symbol" >&2
  exit 1
fi

modules=$(lsmod)
if grep -Eq '^(hid_lenovo_go_transport_test|kunit)[[:space:]]' \
  <<<"$modules"; then
  echo "KUnit or the test module is already loaded" >&2
  exit 1
fi

binding_map() {
  local device

  for device in /sys/bus/hid/devices/0003:17EF:61E[B-E].*; do
    [ -e "$device" ] || continue
    printf '%s %s\n' "${device##*/}" \
      "$(basename "$(readlink -f "$device/driver")")"
  done
}

owner=$(modinfo -n hid_lenovo_go)
owner_hash=$(sha256sum "$owner" | awk '{print $1}')
bindings_before=$(binding_map)
[ -n "$bindings_before" ]
cleanup() {
  rmmod hid_lenovo_go_transport_test 2>/dev/null || true
  modprobe -r kunit 2>/dev/null || true
}
trap cleanup EXIT

modprobe kunit enable=1 filter_glob=hid-lenovo-go
marker=$(date '+%Y-%m-%d %H:%M:%S')
insmod "$module"
log=$(journalctl -k --since "$marker" --no-pager)
printf '%s\n' "$log"
grep -q '# Subtest: hid-lenovo-go' <<<"$log"
grep -q '1..6' <<<"$log"
grep -Eq 'ok 6.*go_wait_result_test' <<<"$log"
if grep -q 'not ok' <<<"$log"; then
  exit 1
fi

rmmod hid_lenovo_go_transport_test
modprobe -r kunit
trap - EXIT

[ "$(sha256sum "$owner" | awk '{print $1}')" = "$owner_hash" ]
modules=$(lsmod)
grep -q '^hid_lenovo_go[[:space:]]' <<<"$modules"
if grep -Eq '^(hid_lenovo_go_transport_test|kunit)[[:space:]]' \
  <<<"$modules"; then
  echo "A test module remains loaded" >&2
  exit 1
fi
[ "$(binding_map)" = "$bindings_before" ]

echo "result=pass"
