#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -Eeuo pipefail

root_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck source=lib.sh
# shellcheck disable=SC1091
source "$root_dir/scripts/lib.sh"

source_dir=$(CDPATH='' cd -- "$root_dir/../../drivers/lenovo-wmi-fan" && pwd)
kver=$(uname -r)
module=$root_dir/lenovo-wmi-tuning.ko
install_root=$TUNING_INSTALL_ROOT
releases=$install_root/releases
unit_source=$root_dir/systemd/$TUNING_UNIT
unit_target=/etc/systemd/system/$TUNING_UNIT

fail() {
  printf '%s\n' "wmi-tuning install: $*" >&2
  exit 1
}

[[ $# -eq 0 ]] || fail "this command does not accept arguments"
[[ $EUID -eq 0 ]] || fail "run as root"
[[ -r $unit_source ]] || fail "service file is missing"
[[ ! -f $TUNING_STATE_DIR/active ]] || fail "deactivate the project driver before installation"
[[ ! -f $TUNING_STATE_DIR/recovery-incomplete ]] || \
  fail "repair the incomplete driver recovery first"
"$root_dir/scripts/validate-host.sh"

# Build the external module.
if [[ ! -r $module ]]; then
  kernel_headers=/lib/modules/$kver/build
  [[ -d $kernel_headers ]] || \
    fail "install kernel-devel for $kver to build the external module"
  make -C "$kernel_headers" M="$root_dir" W=1 KCFLAGS=-Werror clean
  make -C "$kernel_headers" M="$root_dir" W=1 KCFLAGS=-Werror modules
  [[ -r $module ]] || fail "module build produced no output"
fi

# Verify module metadata.
[[ $(modinfo -F name "$module") == "$TUNING_MODULE_NAME" ]] || \
  fail "module name is not $TUNING_MODULE_NAME"
vermagic=$(modinfo -F vermagic "$module") || fail "cannot read module metadata"
[[ ${vermagic%% *} == "$kver" ]] || fail "module vermagic does not match $kver"

stock=$(modinfo -n "$TUNING_STOCK_MODULE") || fail "cannot find the stock module"
[[ -r $stock ]] || fail "stock module is not readable"
tuning_stock_module_loaded || fail "stock module is not loaded"
tuning_verify_stock_interfaces || fail "stock WMI interfaces are incomplete"
stock_sha=$(sha256sum "$stock" | awk '{print $1}')
stock_note=$(mktemp --tmpdir wmi-tuning-stock.XXXXXXXX)
tuning_extract_build_id_note "$stock" "$stock_note" || fail "cannot read stock build ID"
tuning_loaded_note_matches "$TUNING_STOCK_MODULE" "$stock_note" || \
  fail "loaded stock module differs from its file"

# Compute source SHA-256 from the original source tree.
source_sha=$(
  sha256sum "$source_dir/wmi-other.c" \
    "$root_dir/include/wmi-capdata.h" \
    "$root_dir/include/wmi-events.h" \
    "$root_dir/include/wmi-helpers.h" \
    "$root_dir/include/firmware_attributes_class.h" |
  awk '{print $1}' | sha256sum | awk '{print $1}'
)
module_sha=$(sha256sum "$module" | awk '{print $1}')
release_scripts=(
  activate.sh deactivate.sh lib.sh load.sh unload.sh uninstall.sh
  validate-host.sh validate-lifecycle.sh
)
package_sha=$(
  for script in "${release_scripts[@]}"; do
    sha256sum "$root_dir/scripts/$script" | awk '{print $1}'
  done | sha256sum | awk '{print $1}'
)

install -d -m 0700 "$TUNING_STATE_DIR"
exec 9> "$TUNING_STATE_DIR/lock"
flock -x 9
[[ ! -f $TUNING_STATE_DIR/active ]] || fail "project driver became active during installation"
[[ ! -f $TUNING_STATE_DIR/recovery-incomplete ]] || \
  fail "driver recovery became incomplete"
[[ $(systemctl show -p ActiveState --value "$TUNING_UNIT" 2>/dev/null || true) == inactive ]] || \
  fail "the service is not fully inactive"
install -d -m 0755 "$releases"

release_id=$(
  printf '%s\n' "$kver" "$source_sha" "$module_sha" "$stock_sha" "$package_sha" |
  sha256sum | awk '{print $1}'
)
release=$releases/$release_id
stage=$(mktemp -d "$releases/.stage.XXXXXXXX")
chmod 0755 "$stage"
old_link=$(readlink "$install_root/current" 2>/dev/null || true)
unit_backup=$(mktemp --tmpdir wmi-tuning-unit.XXXXXXXX)
unit_existed=0
unit_enabled=0
if [[ -f $unit_target ]]; then
  cp -- "$unit_target" "$unit_backup"
  unit_existed=1
fi
if systemctl is-enabled --quiet "$TUNING_UNIT"; then
  unit_enabled=1
fi

rollback() {
  local rc=$?

  trap - ERR
  set +e
  rm -rf -- "$stage"
  if [[ -n $old_link ]]; then
    ln -sfn -- "$old_link" "$install_root/current.rollback"
    mv -Tf -- "$install_root/current.rollback" "$install_root/current"
  else
    rm -f -- "$install_root/current"
  fi
  if [[ $unit_existed -eq 1 ]]; then
    install -m 0644 "$unit_backup" "$unit_target"
  else
    rm -f -- "$unit_target"
  fi
  systemctl daemon-reload
  if [[ $unit_enabled -eq 0 ]]; then
    systemctl disable "$TUNING_UNIT" 2>/dev/null || true
  fi
  rm -f -- "$unit_backup" "$stock_note"
  exit "$rc"
}
trap rollback ERR

install -d -m 0755 "$stage/modules/$kver"
install -m 0644 "$module" "$stage/modules/$kver/lenovo-wmi-tuning.ko"
install -d -m 0755 "$stage/include"
for header in wmi-capdata.h wmi-events.h wmi-helpers.h \
    firmware_attributes_class.h; do
  install -m 0644 "$root_dir/include/$header" "$stage/include/$header"
done
for script in "${release_scripts[@]}"; do
  install -m 0755 "$root_dir/scripts/$script" "$stage/$script"
done
if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
  chcon -t modules_object_t "$stage/modules/$kver/lenovo-wmi-tuning.ko" 2>/dev/null || true
fi

# Record release metadata.
printf '%s\n' "$kver" > "$stage/kernel-release"
printf '%s\n' "$source_sha" > "$stage/source.sha256"
printf '%s\n' "$module_sha" > "$stage/project.sha256"
printf '%s\n' "$package_sha" > "$stage/package.sha256"
printf '%s\n' "$vermagic" > "$stage/vermagic"
printf '%s\n' "$stock" > "$stage/stock.path"
printf '%s\n' "$stock_sha" > "$stage/stock.sha256"
install -m 0644 "$stock_note" "$stage/stock.note"
tuning_extract_build_id_note "$module" "$stage/project.note" || \
  fail "cannot read project build ID"

if [[ -d $release ]]; then
  rm -rf -- "$stage"
else
  mv -- "$stage" "$release"
fi
install -m 0644 "$unit_source" "$unit_target"
ln -sfn -- "releases/$release_id" "$install_root/current.new"
mv -Tf -- "$install_root/current.new" "$install_root/current"
systemctl daemon-reload
systemctl disable "$TUNING_UNIT" 2>/dev/null || true
trap - ERR
rm -f -- "$unit_backup" "$stock_note"

printf '%s\n' "Installed $release/modules/$kver/lenovo-wmi-tuning.ko"
printf '%s\n' "Release: $release_id"
printf '%s\n' "The service is disabled. Use current/activate.sh for a controlled start."
