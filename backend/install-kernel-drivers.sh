#!/usr/bin/env bash
# Install the exact-kernel HID and WMI tuning modules that the unprivileged
# installer built. Restore WMI tuning when it was enabled before a kernel
# update. A first installation leaves it disabled. Preserve the prior HID
# service-enabled state.
set -Eeuo pipefail
PATH=/usr/sbin:/usr/bin:/sbin:/bin

if [[ $# -ne 0 || $EUID -ne 0 ]]; then
  printf '%s\n' 'Run this script as root without arguments.' >&2
  exit 2
fi

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
plugin_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)

# HID package.
hid_package=$plugin_dir/packaging/hid-lenovo-go
hid_unit=legion-go-ogui-hid.service
hid_current=/usr/local/lib/legion-go-ogui/hid/current
hid_state=/run/legion-go-ogui/hid-driver

# WMI tuning package.
wmi_package=$plugin_dir/packaging/lenovo-wmi-tuning
wmi_unit=legion-go-ogui-wmi-tuning.service
wmi_current=/usr/local/lib/legion-go-ogui/wmi-tuning/current
wmi_state=/run/legion-go-ogui/wmi-tuning-driver

fail() {
  printf '%s\n' "kernel-driver install: $*" >&2
  exit 1
}

[[ -x $hid_package/scripts/install.sh ]] || fail 'HID installer is missing'
[[ -r $plugin_dir/drivers/hid-lenovo-go/hid-lenovo-go.ko ]] || \
  fail 'built HID module is missing'
[[ -x $wmi_package/scripts/install.sh ]] || fail 'WMI tuning installer is missing'
[[ -r $wmi_package/lenovo-wmi-tuning.ko ]] || \
  fail 'built WMI tuning module is missing'

# -- HID driver --

hid_was_enabled=0
if systemctl is-enabled --quiet "$hid_unit"; then
  hid_was_enabled=1
fi

restore_hid_enabled() {
  local rc=$?

  trap - ERR
  set +e
  if [[ $hid_was_enabled -eq 1 && -x $hid_current/activate.sh ]]; then
    "$hid_current/activate.sh"
    systemctl enable "$hid_unit"
  fi
  exit "$rc"
}
trap restore_hid_enabled ERR

if [[ -f $hid_state/active && -x $hid_current/deactivate.sh ]]; then
  "$hid_current/deactivate.sh"
fi
systemctl stop "$hid_unit" || true
systemctl reset-failed "$hid_unit" || true

"$hid_package/scripts/install.sh"

if [[ $hid_was_enabled -eq 1 ]]; then
  "$hid_current/activate.sh"
  systemctl enable "$hid_unit"
fi

trap - ERR
printf '%s\n' "Installed HID driver for $(uname -r)"

# -- WMI tuning driver --

wmi_was_enabled=0
if systemctl is-enabled --quiet "$wmi_unit"; then
  wmi_was_enabled=1
fi

if [[ -f $wmi_state/active && -x $wmi_current/deactivate.sh ]]; then
  "$wmi_current/deactivate.sh" || fail 'WMI tuning deactivation failed'
fi
systemctl stop "$wmi_unit" || true
systemctl reset-failed "$wmi_unit" || true

"$wmi_package/scripts/install.sh"

if [[ $wmi_was_enabled -eq 1 ]]; then
  "$wmi_current/activate.sh"
  systemctl enable "$wmi_unit"
  printf '%s\n' "Restored the enabled WMI tuning driver for $(uname -r)."
else
  printf '%s\n' "Installed WMI tuning driver for $(uname -r)."
  printf '%s\n' "The service is disabled. Use current/activate.sh for a controlled start."
fi
