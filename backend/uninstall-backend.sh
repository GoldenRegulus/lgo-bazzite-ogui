#!/usr/bin/env bash
# Remove only the files installed by install-backend.sh.
set -euo pipefail

if [[ "$#" -ne 0 ]]; then
  printf '%s\n' 'This uninstaller does not accept arguments.' >&2
  exit 2
fi
if [[ "$(/usr/bin/id -u)" -eq 0 ]]; then
  printf '%s\n' 'Run this uninstaller as a regular user, not as root.' >&2
  exit 2
fi
if [[ ! -x /usr/bin/sudo || ! -x /usr/bin/rm || ! -x /usr/bin/rmdir || \
      ! -x /usr/bin/systemctl ]]; then
  printf '%s\n' 'Required system tools are not available.' >&2
  exit 3
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(/usr/bin/dirname -- "$0")" && /usr/bin/pwd -P)"
HID_UNINSTALLER="$SCRIPT_DIR/../packaging/hid-lenovo-go/scripts/uninstall.sh"
WMI_UNINSTALLER=/usr/local/lib/legion-go-ogui/wmi-tuning/current/uninstall.sh

printf '%s\n' 'Administrator consent is required to remove the helper.'
/usr/bin/sudo -v
if [[ -x "$WMI_UNINSTALLER" ]]; then
  /usr/bin/sudo "$WMI_UNINSTALLER"
fi
if [[ -f "$HID_UNINSTALLER" ]]; then
  /usr/bin/sudo /usr/bin/bash "$HID_UNINSTALLER"
fi
if [[ -x /usr/local/libexec/legion-go-ogui-controller ]]; then
  /usr/bin/sudo /usr/local/libexec/legion-go-ogui-controller swap-disable
fi
/usr/bin/sudo /usr/bin/rm -f -- \
  /usr/local/libexec/legion-go-ogui-helper \
  /usr/local/libexec/legion-go-ogui-controller \
  /usr/local/libexec/legion-go-ogui-fan \
  /var/lib/legion-go-ogui/controller-swap-state \
  /etc/polkit-1/rules.d/49-legion-go-ogui-helper.rules
/usr/bin/sudo /usr/bin/rmdir --ignore-fail-on-non-empty /var/lib/legion-go-ogui
/usr/bin/sudo /usr/bin/systemctl restart polkit.service

printf '%s\n' 'Removed Legion Go OGUI backend files.'
