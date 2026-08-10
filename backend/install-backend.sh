#!/usr/bin/env bash
# Install the bundled helpers and the project HID module. Run as a regular user.
set -euo pipefail

if [[ "$#" -ne 0 ]]; then
  printf '%s\n' 'This installer does not accept arguments.' >&2
  exit 2
fi
if [[ "$(/usr/bin/id -u)" -eq 0 ]]; then
  printf '%s\n' 'Run this installer as a regular user, not as root.' >&2
  exit 2
fi
if [[ "$(/usr/bin/uname -m)" != "x86_64" ]]; then
  printf '%s\n' 'This installer supports x86_64 systems only.' >&2
  exit 3
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(/usr/bin/dirname -- "$0")" && /usr/bin/pwd -P)"
BUNDLED_HELPER_B64="$SCRIPT_DIR/payload/legion-go-ogui-helper.b64"
BUNDLED_CONTROLLER_B64="$SCRIPT_DIR/payload/legion-go-ogui-controller.b64"
BUNDLED_FAN_B64="$SCRIPT_DIR/payload/legion-go-ogui-fan.b64"
BUNDLED_RULE="$SCRIPT_DIR/49-legion-go-ogui-helper.rules"
HID_DRIVER_DIR="$SCRIPT_DIR/../drivers/hid-lenovo-go"
HID_PACKAGE_DIR="$SCRIPT_DIR/../packaging/hid-lenovo-go"
WMI_DRIVER_DIR="$SCRIPT_DIR/../drivers/lenovo-wmi-fan"
WMI_PACKAGE_DIR="$SCRIPT_DIR/../packaging/lenovo-wmi-tuning"
KERNEL_INSTALLER="$SCRIPT_DIR/install-kernel-drivers.sh"
HELPER_PATH="/usr/local/libexec/legion-go-ogui-helper"
CONTROLLER_PATH="/usr/local/libexec/legion-go-ogui-controller"
FAN_PATH="/usr/local/libexec/legion-go-ogui-fan"
RULE_PATH="/etc/polkit-1/rules.d/49-legion-go-ogui-helper.rules"

if [[ ! -f "$BUNDLED_HELPER_B64" || ! -f "$BUNDLED_CONTROLLER_B64" || \
      ! -f "$BUNDLED_FAN_B64" || ! -f "$BUNDLED_RULE" || \
      ! -f "$HID_DRIVER_DIR/Makefile" || ! -f "$KERNEL_INSTALLER" || \
      ! -f "$HID_PACKAGE_DIR/scripts/install.sh" || \
      ! -f "$WMI_DRIVER_DIR/wmi-other.c" || \
      ! -f "$WMI_PACKAGE_DIR/scripts/install.sh" ]]; then
  printf '%s\n' 'A local helper payload, driver source, or Polkit rule is missing.' >&2
  exit 4
fi
if [[ ! -x /usr/bin/base64 || ! -x /usr/bin/mktemp || ! -x /usr/bin/chmod ]]; then
  printf '%s\n' 'Required local build tools are not available.' >&2
  exit 4
fi

WORK_DIR="$(/usr/bin/mktemp -d --tmpdir legion-go-ogui-install.XXXXXXXX)"
trap '/usr/bin/rm -rf -- "$WORK_DIR"' EXIT
BUNDLED_HELPER="$WORK_DIR/legion-go-ogui-helper"
BUNDLED_CONTROLLER="$WORK_DIR/legion-go-ogui-controller"
BUNDLED_FAN="$WORK_DIR/legion-go-ogui-fan"
BUILD_ROOT="$WORK_DIR/plugin"
/usr/bin/base64 --decode -- "$BUNDLED_HELPER_B64" > "$BUNDLED_HELPER"
/usr/bin/base64 --decode -- "$BUNDLED_CONTROLLER_B64" > "$BUNDLED_CONTROLLER"
/usr/bin/base64 --decode -- "$BUNDLED_FAN_B64" > "$BUNDLED_FAN"
/usr/bin/chmod 0700 -- "$BUNDLED_HELPER" "$BUNDLED_CONTROLLER" "$BUNDLED_FAN"
/usr/bin/mkdir -p "$BUILD_ROOT/backend" "$BUILD_ROOT/drivers" "$BUILD_ROOT/packaging"
/usr/bin/cp -a -- "$HID_DRIVER_DIR" "$BUILD_ROOT/drivers/hid-lenovo-go"
/usr/bin/cp -a -- "$HID_PACKAGE_DIR" "$BUILD_ROOT/packaging/hid-lenovo-go"
/usr/bin/cp -a -- "$WMI_DRIVER_DIR" "$BUILD_ROOT/drivers/lenovo-wmi-fan"
/usr/bin/cp -a -- "$WMI_PACKAGE_DIR" "$BUILD_ROOT/packaging/lenovo-wmi-tuning"
/usr/bin/cp -- "$KERNEL_INSTALLER" "$BUILD_ROOT/backend/install-kernel-drivers.sh"
HID_DRIVER_DIR="$BUILD_ROOT/drivers/hid-lenovo-go"
HID_PACKAGE_DIR="$BUILD_ROOT/packaging/hid-lenovo-go"
WMI_DRIVER_DIR="$BUILD_ROOT/drivers/lenovo-wmi-fan"
WMI_PACKAGE_DIR="$BUILD_ROOT/packaging/lenovo-wmi-tuning"
KERNEL_INSTALLER="$BUILD_ROOT/backend/install-kernel-drivers.sh"

# Check the exact device before elevation. The stock WMI module on a new
# kernel can omit charge_types until this installer replaces it.
battery_status=0
"$BUNDLED_HELPER" status >/dev/null || battery_status=$?
if [[ $battery_status -ne 0 && $battery_status -ne 4 ]] || \
   ! "$BUNDLED_CONTROLLER" status; then
  printf '%s\n' 'The local helper did not verify this supported device.' >&2
  exit 5
fi
fan_status=0
"$BUNDLED_FAN" status >/dev/null || fan_status=$?
if [[ $fan_status -ne 0 && $fan_status -ne 4 ]]; then
  printf '%s\n' 'The local fan helper did not verify this supported device.' >&2
  exit 5
fi
if [[ ! -x /usr/bin/sudo || ! -x /usr/bin/install || ! -x /usr/bin/systemctl || \
      ! -x /usr/bin/pkcheck || ! -x /usr/bin/make || ! -x /usr/bin/sha256sum || \
      ! -x /usr/bin/cp || ! -x /usr/bin/mkdir || ! -x /usr/bin/awk || \
      ! -x /usr/sbin/modinfo || ! -f "/usr/lib/modules/$(/usr/bin/uname -r)/build/Makefile" || \
      ! -d /etc/polkit-1/rules.d ]]; then
  printf '%s\n' 'Required system tools or the Polkit rules directory are not available.' >&2
  exit 6
fi

printf '%s\n' "Building kernel modules for $(/usr/bin/uname -r)."
/usr/bin/chmod u+x "$HID_PACKAGE_DIR"/scripts/*.sh \
  "$WMI_PACKAGE_DIR"/scripts/*.sh "$KERNEL_INSTALLER"
/usr/bin/make -C "$HID_DRIVER_DIR" clean all W=1 KCFLAGS=-Werror
/usr/bin/make -C "$WMI_PACKAGE_DIR" clean modules W=1 KCFLAGS=-Werror
if [[ "$(/usr/sbin/modinfo -F vermagic "$HID_DRIVER_DIR/hid-lenovo-go.ko")" != \
      "$(/usr/bin/uname -r) "* ]] || \
   [[ "$(/usr/sbin/modinfo -F name "$WMI_PACKAGE_DIR/lenovo-wmi-tuning.ko")" != \
      lenovo_wmi_tuning ]] || \
   [[ "$(/usr/sbin/modinfo -F vermagic "$WMI_PACKAGE_DIR/lenovo-wmi-tuning.ko")" != \
      "$(/usr/bin/uname -r) "* ]]; then
  printf '%s\n' 'A built kernel module does not match the running kernel.' >&2
  exit 6
fi

printf '%s\n' 'Administrator consent is required to install the bounded helpers.'
/usr/bin/sudo -v
/usr/bin/sudo /usr/bin/install -d -o root -g root -m 0755 /usr/local/libexec
/usr/bin/sudo /usr/bin/install -o root -g root -m 0755 -- "$BUNDLED_HELPER" "$HELPER_PATH"
/usr/bin/sudo /usr/bin/install -o root -g root -m 0755 -- "$BUNDLED_CONTROLLER" "$CONTROLLER_PATH"
/usr/bin/sudo /usr/bin/install -o root -g root -m 0755 -- "$BUNDLED_FAN" "$FAN_PATH"
/usr/bin/sudo /usr/bin/install -o root -g root -m 0644 -- "$BUNDLED_RULE" "$RULE_PATH"
/usr/bin/sudo /usr/bin/bash "$KERNEL_INSTALLER"
/usr/bin/sudo /usr/bin/systemctl restart polkit.service

if ! "$HELPER_PATH" status || ! "$CONTROLLER_PATH" status || \
   [[ "$(/usr/bin/sha256sum "$BUNDLED_FAN" | /usr/bin/awk '{print $1}')" != \
      "$(/usr/bin/sha256sum "$FAN_PATH" | /usr/bin/awk '{print $1}')" ]]; then
  printf '%s\n' 'Installed helper verification failed.' >&2
  exit 7
fi
if /usr/bin/systemctl is-enabled --quiet legion-go-ogui-hid.service && \
   ! /usr/bin/systemctl is-active --quiet legion-go-ogui-hid.service; then
  printf '%s\n' 'The enabled HID service did not recover.' >&2
  exit 7
fi
OGUI_PID="$(/usr/bin/pgrep -u "$(/usr/bin/id -u)" -f 'opengamepad-ui\.x86_64' | /usr/bin/head -n 1 || true)"
if [[ -n "$OGUI_PID" ]]; then
  if ! /usr/bin/sudo /usr/bin/pkcheck \
      --action-id org.freedesktop.policykit.exec \
      --process "$OGUI_PID" \
      --detail program "$HELPER_PATH" || \
     ! /usr/bin/sudo /usr/bin/pkcheck \
      --action-id org.freedesktop.policykit.exec \
      --process "$OGUI_PID" \
      --detail program "$CONTROLLER_PATH" || \
     ! /usr/bin/sudo /usr/bin/pkcheck \
      --action-id org.freedesktop.policykit.exec \
      --process "$OGUI_PID" \
      --detail program "$FAN_PATH"; then
    printf '%s\n' 'Installed Polkit authorization verification failed.' >&2
    exit 8
  fi
else
  printf '%s\n' 'OGUI is not running. Polkit runtime verification is deferred.'
fi

printf '%s\n' "Installed $HELPER_PATH"
printf '%s\n' "Installed $CONTROLLER_PATH"
printf '%s\n' "Installed $FAN_PATH"
