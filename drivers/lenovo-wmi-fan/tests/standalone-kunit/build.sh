#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  printf '%s\n' "Usage: $0 LINUX_SOURCE KERNEL_BUILD [OUTPUT_DIR]" >&2
  exit 2
fi

source=$(realpath "$1")
build=$(realpath "$2")
output=$(realpath -m "${3:-/tmp/lenovo-wmi-fan-kunit}")
test_dir=$(dirname "$(realpath "$0")")
source_file="$source/drivers/platform/x86/lenovo/wmi-other.c"
test_file="$test_dir/lenovo-wmi-fan-kunit.c"

for file in "$source_file" "$test_file"; do
  [[ -r $file ]] || {
    printf 'Missing source file: %s\n' "$file" >&2
    exit 1
  }
done

rm -rf "$output"
mkdir -p "$output"

python3 - "$source_file" "$test_file" "$output" <<'PY'
from hashlib import sha256
from pathlib import Path
import sys

source_file = Path(sys.argv[1])
test_file = Path(sys.argv[2])
output = Path(sys.argv[3])
source = source_file.read_text()
test = test_file.read_text()
start_marker = "/* Lenovo Legion Go fan pure helper code. */"
end_marker = "/* End Lenovo Legion Go fan pure helper code. */"
test_marker = "static void lenovo_fan_dmi_test"

for marker in (start_marker, end_marker, test_marker):
    text = source if marker != test_marker else test
    if text.count(marker) != 1:
        raise SystemExit(f"Marker is not unique: {marker!r}")

start = source.index(start_marker)
end = source.index(end_marker, start) + len(end_marker)
production = source[start:end]
test_body = test[test.index(test_marker):]
wrapper = """// SPDX-License-Identifier: GPL-2.0-or-later
/* Generated from pure helper code in wmi-other.c. */

#include <kunit/test.h>
#include <linux/errno.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/string.h>
#include <linux/types.h>
#include <linux/unaligned.h>

"""
(output / "lenovo-wmi-fan-kunit.c").write_text(wrapper + production + "\n\n" + test_body)
(output / "production-region.sha256").write_text(
    f"{sha256(production.encode()).hexdigest()}  extracted production region\n"
)
(output / "test-source.sha256").write_text(
    f"{sha256(test.encode()).hexdigest()}  lenovo-wmi-fan-kunit.c\n"
)
PY

cat > "$output/Makefile" <<'EOF'
ccflags-y += -Werror
obj-m += lenovo-wmi-fan-kunit.o
EOF

make -C "$build" M="$output" clean
make -C "$build" M="$output" W=1 KCFLAGS=-Werror modules
module="$output/lenovo-wmi-fan-kunit.ko"
[[ $(modinfo -F depends "$module") == kunit ]]
[[ -z $(modinfo -F alias "$module") ]]
if nm "$module" | grep -Eq \
  'wmi_driver_register|platform_driver_register|acpi_evaluate_object'; then
  printf '%s\n' 'The standalone test contains a hardware registration symbol' >&2
  exit 1
fi
modinfo "$module" | grep -E '^(filename|depends|vermagic):'
printf '%s\n' "module=$module"
