#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

# These constants are used by scripts that source this file.
# shellcheck disable=SC2034
TUNING_DRIVER_NAME=lenovo_wmi_other
TUNING_MODULE_NAME=lenovo_wmi_tuning
TUNING_STOCK_MODULE=lenovo_wmi_other
TUNING_STATE_DIR=/run/legion-go-ogui/wmi-tuning-driver
TUNING_INSTALL_ROOT=/usr/local/lib/legion-go-ogui/wmi-tuning
TUNING_UNIT=legion-go-ogui-wmi-tuning.service

TUNING_OTHER_GUID=DC2A8805-3A8C-41BA-A6F7-092E0089CD3B
TUNING_FAN_GUID=92549549-4BDE-4F06-AC04-CE8BF898DBAA

tuning_extract_build_id_note() {
  local module=$1
  local output=$2
  local temporary
  temporary=$(mktemp --tmpdir wmi-tuning-module.XXXXXXXX)
  case $module in
    *.xz) xz -dc -- "$module" > "$temporary" ;;
    *.zst) zstd -qdc -- "$module" > "$temporary" ;;
    *.gz) gzip -dc -- "$module" > "$temporary" ;;
    *) cp -- "$module" "$temporary" ;;
  esac
  objcopy --dump-section ".note.gnu.build-id=$output" "$temporary" 2>/dev/null || true
  rm -f -- "$temporary"
  [[ -s $output ]]
}

tuning_loaded_note_matches() {
  local name=$1 note=$2

  [[ -r /sys/module/$name/notes/.note.gnu.build-id ]] &&
    cmp -s -- /sys/module/"$name"/notes/.note.gnu.build-id "$note"
}

tuning_file_note_matches() {
  local module=$1 note=$2
  local temporary

  temporary=$(mktemp --tmpdir wmi-tuning-note.XXXXXXXX)
  if tuning_extract_build_id_note "$module" "$temporary" &&
     cmp -s -- "$temporary" "$note"; then
    rm -f -- "$temporary"
    return 0
  fi
  rm -f -- "$temporary"
  return 1
}

tuning_module_loaded() {
  local name=${1:-$TUNING_MODULE_NAME}

  grep -q "^$name " /proc/modules
}

tuning_stock_module_loaded() {
  grep -q "^$TUNING_STOCK_MODULE " /proc/modules
}

tuning_any_module_loaded() {
  tuning_module_loaded "$TUNING_STOCK_MODULE" || tuning_module_loaded "$TUNING_MODULE_NAME"
}

tuning_dependent_count() {
  local name=$1
  local count=0
  local module

  [[ -d /sys/module/$name/holders ]] || return 1
  for module in /sys/module/"$name"/holders/*; do
    [[ -d $module ]] || continue
    count=$((count + 1))
  done
  printf '%d\n' "$count"
}

tuning_wmi_device_path() {
  local guid=$1
  local path name
  local -a matches=()

  for path in /sys/bus/wmi/devices/"$guid"-*; do
    [[ -L $path ]] || continue
    name=${path##*/}
    [[ $name =~ ^${guid}-[0-9]+$ ]] || continue
    matches+=("$path")
  done
  [[ ${#matches[@]} -eq 1 ]] || return 1
  printf '%s\n' "${matches[0]}"
}

tuning_wmi_driver_for_guid() {
  local guid=$1
  local device driver

  device=$(tuning_wmi_device_path "$guid") || return 1
  [[ -L $device/driver ]] || return 1
  driver=$(readlink -f -- "$device/driver")
  printf '%s\n' "${driver##*/}"
}

tuning_wmi_module_for_guid() {
  local guid=$1
  local device module

  device=$(tuning_wmi_device_path "$guid") || return 1
  [[ -L $device/driver/module ]] || return 1
  module=$(readlink -f -- "$device/driver/module")
  printf '%s\n' "${module##*/}"
}

tuning_guid_owners() {
  local guid

  for guid in "$TUNING_OTHER_GUID" "$TUNING_FAN_GUID"; do
    tuning_wmi_driver_for_guid "$guid" 2>/dev/null || true
  done | LC_ALL=C sort -u
}

tuning_battery_path() {
  local supply type
  local -a matches=()

  for supply in /sys/class/power_supply/*; do
    [[ -d $supply && -r $supply/type ]] || continue
    type=$(<"$supply/type")
    [[ $type == Battery && -r $supply/charge_types ]] || continue
    matches+=("$supply")
  done
  [[ ${#matches[@]} -eq 1 ]] || return 1
  printf '%s\n' "${matches[0]}"
}

tuning_hwmon_path() {
  local hwmon name
  local -a matches=()

  for hwmon in /sys/class/hwmon/hwmon*; do
    [[ -d $hwmon && -r $hwmon/name ]] || continue
    name=$(<"$hwmon/name")
    [[ $name == "$TUNING_DRIVER_NAME" && -r $hwmon/fan1_input ]] || continue
    matches+=("$hwmon")
  done
  [[ ${#matches[@]} -eq 1 ]] || return 1
  printf '%s\n' "${matches[0]}"
}

tuning_verify_project_interfaces() {
  local other fan hwmon battery

  other=$(tuning_wmi_device_path "$TUNING_OTHER_GUID") || return 1
  fan=$(tuning_wmi_device_path "$TUNING_FAN_GUID") || return 1
  [[ $(tuning_wmi_driver_for_guid "$TUNING_OTHER_GUID") == "$TUNING_DRIVER_NAME" ]]
  [[ $(tuning_wmi_driver_for_guid "$TUNING_FAN_GUID") == "$TUNING_DRIVER_NAME" ]]
  [[ $(tuning_wmi_module_for_guid "$TUNING_OTHER_GUID") == "$TUNING_MODULE_NAME" ]]
  [[ $(tuning_wmi_module_for_guid "$TUNING_FAN_GUID") == "$TUNING_MODULE_NAME" ]]
  [[ -r $other/fan_fullspeed && -r $fan/fan_curve ]]
  hwmon=$(tuning_hwmon_path) || return 1
  battery=$(tuning_battery_path) || return 1
  [[ -r $hwmon/fan1_input && -r $battery/charge_types ]]
}

tuning_verify_stock_interfaces() {
  local fan

  [[ $(tuning_wmi_driver_for_guid "$TUNING_OTHER_GUID") == "$TUNING_DRIVER_NAME" ]]
  [[ $(tuning_wmi_module_for_guid "$TUNING_OTHER_GUID") == "$TUNING_STOCK_MODULE" ]]
  fan=$(tuning_wmi_device_path "$TUNING_FAN_GUID") || return 1
  [[ ! -e $fan/driver ]]
}

tuning_release_hashes_match() {
  local release=$1 module=$2
  local package_sha script
  local -a scripts=(
    activate.sh deactivate.sh lib.sh load.sh unload.sh uninstall.sh
    validate-host.sh validate-lifecycle.sh
  )

  [[ -r $release/project.sha256 ]] || return 1
  [[ -r $release/source.sha256 ]] || return 1
  [[ -r $release/package.sha256 ]] || return 1
  [[ -r $release/project.note ]] || return 1
  [[ $(sha256sum "$module" | awk '{print $1}') == \
     "$(cat "$release/project.sha256")" ]] || return 1
  package_sha=$(
    for script in "${scripts[@]}"; do
      [[ -r $release/$script ]] || return 1
      sha256sum "$release/$script" | awk '{print $1}'
    done | sha256sum | awk '{print $1}'
  )
  [[ $package_sha == "$(cat "$release/package.sha256")" ]]
}

tuning_release_stock_matches() {
  local release=$1
  local stock

  for file in stock.path stock.sha256 stock.note; do
    [[ -r $release/$file ]] || return 1
  done
  stock=$(modinfo -n "$TUNING_STOCK_MODULE") || return 1
  [[ $stock == "$(cat "$release/stock.path")" ]] || return 1
  [[ $(sha256sum "$stock" | awk '{print $1}') == \
     "$(cat "$release/stock.sha256")" ]] || return 1
  tuning_loaded_note_matches "$TUNING_STOCK_MODULE" "$release/stock.note"
}

tuning_vermagic_matches() {
  local module=$1
  local kver vermagic

  kver=$(uname -r)
  vermagic=$(modinfo -F vermagic "$module" 2>/dev/null) || return 1
  [[ ${vermagic%% *} == "$kver" ]]
}
