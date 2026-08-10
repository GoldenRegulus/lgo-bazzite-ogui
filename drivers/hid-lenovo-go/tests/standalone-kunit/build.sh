#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Usage: $0 OWNER_TREE KERNEL_BUILD [OUTPUT_DIR]" >&2
  exit 2
fi

owner_tree=$(realpath "$1")
kernel_build=$(realpath "$2")
output_dir=$(realpath -m "${3:-/tmp/hid-lenovo-go-standalone-kunit}")
script_dir=$(dirname "$(realpath "$0")")
source_file="$owner_tree/drivers/hid/hid-lenovo-go.c"
test_file="$script_dir/hid-lenovo-go-test.c"

for file in "$source_file" "$test_file"; do
  if [ ! -r "$file" ]; then
    echo "Missing source file: $file" >&2
    exit 1
  fi
done

rm -rf "$output_dir"
mkdir -p "$output_dir"

python3 - "$source_file" "$test_file" "$output_dir" <<'PY'
from hashlib import sha256
from pathlib import Path
import sys

source_file = Path(sys.argv[1])
test_file = Path(sys.argv[2])
output_dir = Path(sys.argv[3])
source = source_file.read_text()
test = test_file.read_text()
type_start_marker = "/*\n * Lenovo identifies a synchronous reply"
type_end_marker = "static struct hid_go_cfg {"
helper_start_marker = "static int hid_go_decode_calibration_completion"
helper_end_marker = "static int hid_go_send_output_report"
cal_macro_start_marker = "#define LEGO_CAL_DEVICE_ATTR"
cal_macro_end_marker = "#define LEGO_DEVICE_STATUS_ATTR"

for marker in (type_start_marker, type_end_marker,
               helper_start_marker, helper_end_marker,
               cal_macro_start_marker, cal_macro_end_marker):
  if source.count(marker) != 1:
    raise SystemExit(f"Source marker is not unique: {marker!r}")

type_start = source.index(type_start_marker)
type_end = source.index(type_end_marker, type_start)
helper_start = source.index(helper_start_marker)
helper_end = source.index(helper_end_marker, helper_start)
cal_macro_start = source.index(cal_macro_start_marker)
cal_macro_end = source.index(cal_macro_end_marker, cal_macro_start)
cal_macro = source[cal_macro_start:cal_macro_end]
cal_call = cal_macro[cal_macro.index("return calibrate_config_store"):]
if cal_call.index("_scmd") > cal_call.index("_name.index"):
    raise SystemExit("Calibration command/action arguments are reversed")
production = source[type_start:type_end] + source[helper_start:helper_end]
wrapper = """// SPDX-License-Identifier: GPL-2.0-or-later
/* Generated from private command-transport code in hid-lenovo-go.c. */

#include <linux/completion.h>
#include <linux/errno.h>
#include <linux/spinlock.h>
#include <linux/string.h>
#include <linux/types.h>
#include <linux/unaligned.h>

#define GO_PACKET_SIZE 64
#define GO_INPUT_REPORT_ID 0x04
#define GO_OUTPUT_REPORT_ID 0x05
#define MCU_CONFIG_DATA 0x00
#define GET_DEVICE_STATUS 0xa0
#define GET_CAL_STATUS 0x02
#define SET_DPI_CFG 0x08
#define SET_TRIGGER_CFG 0x0a
#define SET_JOYSTICK_CFG 0x0c
#define SET_GYRO_CFG 0x0e
#define FPS_MODE_DPI 0x02
#define CALDEV_GYROSCOPE 0x01
#define CALDEV_TRIGGER 0x03
#define CAL_STAT_SUCCESS 0x01
#define CAL_STAT_FAILURE 0x02

enum dev_type {
	UNSPECIFIED,
	USB_MCU,
	TX_DONGLE,
	LEFT_CONTROLLER,
	RIGHT_CONTROLLER,
};

struct command_report {
\tu8 report_id;
\tu8 id;
\tu8 cmd;
\tu8 sub_cmd;
\tu8 device_type;
\tu8 data[59];
} __packed;

"""
generated = wrapper + production + "\n" + test
(output_dir / "hid-lenovo-go-transport-test.c").write_text(generated)
(output_dir / "production-region.sha256").write_text(
  f"{sha256(production.encode()).hexdigest()}  extracted production regions\n"
)
(output_dir / "test-source.sha256").write_text(
  f"{sha256(test.encode()).hexdigest()}  hid-lenovo-go-test.c\n"
)
PY

cat > "$output_dir/Makefile" <<'EOF'
ccflags-y += -Werror
obj-m += hid-lenovo-go-transport-test.o
EOF

make -C "$kernel_build" M="$output_dir" clean
make -C "$kernel_build" M="$output_dir" modules

module="$output_dir/hid-lenovo-go-transport-test.ko"
[ "$(modinfo -F depends "$module")" = kunit ]
[ -z "$(modinfo -F alias "$module")" ]
symbols=$(nm "$module")
if grep -Eq \
  'hid_register_driver|__hid_register_driver|usb_register|module_hid_driver' \
  <<<"$symbols"; then
  echo "The standalone test contains a hardware registration symbol" >&2
  exit 1
fi

modinfo "$module" | grep -E \
  '^(filename|description|license|depends|vermagic):'
sha256sum "$module" "$output_dir/hid-lenovo-go-transport-test.c"
