# Standalone KUnit tests

This module runs six HID driver tests. It does not replace, unload, or disconnect the active `hid_lenovo_go` driver.

## Tests

The tests cover:

1. A successful calibration completion.
2. A failed calibration completion and its error code.
3. Invalid calibration completion data.
4. Exact calibration and DPI output report construction.
5. Lenovo command and sub-command reply ownership.
6. Reply errors, timeouts, and interrupted waits.

`build.sh` copies only packet, command, and reply code. The module does not register a HID or USB driver.

## Build

The first argument is a Linux source directory containing the modified driver at `drivers/hid/hid-lenovo-go.c`. The second is the Legion Go current-kernel build directory.

```sh
LINUX_SOURCE=/path/to/linux-source
KERNEL_BUILD=/usr/lib/modules/$(uname -r)/build
./build.sh "$LINUX_SOURCE" "$KERNEL_BUILD"
```

## Run

**Warning:** This loads a test module. Ensure `hid_lenovo_go` is active first.

```sh
sudo ./run.sh \
  /tmp/hid-lenovo-go-standalone-kunit/hid-lenovo-go-transport-test.ko
```

`run.sh` checks the kernel version signature, runs six KUnit tests, unloads test modules, and checks that the original HID driver and controller connections did not change. Fix cleanup failures before another test or driver change.

## Limits

These tests do not test USB communication, sysfs files, driver loading, or hardware writes.
