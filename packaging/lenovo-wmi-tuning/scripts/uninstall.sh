#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -Eeuo pipefail

install_root=/usr/local/lib/legion-go-ogui/wmi-tuning
current=$install_root/current

# shellcheck source=lib.sh
# shellcheck disable=SC1091
source "$current/lib.sh"

fail() {
  printf '%s\n' "wmi-tuning uninstall: $*" >&2
  exit 1
}

[[ $# -eq 0 ]] || fail "this command does not accept arguments"
[[ $EUID -eq 0 ]] || fail "run as root"
[[ -x $current/deactivate.sh ]] || fail "installed recovery scripts are missing"

if systemctl is-active --quiet "$TUNING_UNIT" || [[ -f $TUNING_STATE_DIR/active ]]; then
  "$current/deactivate.sh" || fail "driver deactivation failed; project files were kept"
fi
[[ ! -f $TUNING_STATE_DIR/active ]] || fail "project driver is still active"
[[ ! -f $TUNING_STATE_DIR/recovery-incomplete ]] || \
  fail "driver recovery is incomplete; project files were kept"

install -d -m 0700 "$TUNING_STATE_DIR"
exec 9> "$TUNING_STATE_DIR/lock"
flock -x 9
[[ ! -f $TUNING_STATE_DIR/active ]] || fail "project driver became active during uninstall"
[[ ! -f $TUNING_STATE_DIR/recovery-incomplete ]] || \
  fail "driver recovery became incomplete during uninstall"
[[ $(systemctl show -p ActiveState --value "$TUNING_UNIT" 2>/dev/null || true) == inactive ]] || \
  fail "the service is not fully inactive"

stock=$(modinfo -n "$TUNING_STOCK_MODULE") || fail "cannot find the stock module"
tuning_extract_build_id_note "$stock" "$TUNING_STATE_DIR/uninstall-stock.note" || \
  fail "cannot read the stock module build ID"
tuning_stock_module_loaded || fail "the stock module is not loaded"
tuning_loaded_note_matches "$TUNING_STOCK_MODULE" \
  "$TUNING_STATE_DIR/uninstall-stock.note" || \
  fail "the loaded module is not the stock module"
tuning_verify_stock_interfaces || fail "stock WMI interfaces are incomplete"
rm -f -- "$TUNING_STATE_DIR/uninstall-stock.note"

unit_backup=$(mktemp --tmpdir wmi-tuning-unit.XXXXXXXX)
unit_target=/etc/systemd/system/$TUNING_UNIT
cp -- "$unit_target" "$unit_backup"
quarantine=$install_root.removing.$$
unit_enabled=0
if systemctl is-enabled --quiet "$TUNING_UNIT"; then
  unit_enabled=1
fi

rollback() {
  local rc=$?

  trap - ERR
  set +e
  if [[ -d $quarantine && ! -e $install_root ]]; then
    mv -- "$quarantine" "$install_root"
  fi
  install -m 0644 "$unit_backup" "$unit_target"
  systemctl daemon-reload
  if [[ $unit_enabled -eq 1 ]]; then
    systemctl enable "$TUNING_UNIT" 2>/dev/null || true
  fi
  rm -f -- "$unit_backup"
  exit "$rc"
}
trap rollback ERR

if [[ $unit_enabled -eq 1 ]]; then
  systemctl disable "$TUNING_UNIT" 2>/dev/null || true
fi
mv -- "$install_root" "$quarantine"
rm -f -- "$unit_target"
systemctl daemon-reload
rm -rf -- "$quarantine"
trap - ERR
rm -f -- "$unit_backup"

printf '%s\n' "Removed wmi-tuning project files"
