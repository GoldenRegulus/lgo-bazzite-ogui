# Lenovo Legion Go HID driver

## Supported controllers

The driver supports USB product IDs `0x61eb` through `0x61ee`.

The driver does not check the computer model. Install scripts require:

- Vendor: `LENOVO`
- Product name: `83E1`
- Product version: `Legion Go 8APU1`

## Status

This driver is released for the live-verified Original Legion Go. Install it through the backend workflow only.

Local build, code checks, and KUnit build pass. KUnit has not run on the Legion Go's current kernel.

See the [annotated unified diff](ANNOTATED-DIFF.patch).

## Build

Run from this directory:

```sh
make
```

The build stops on compiler warnings. The install script checks the module name, required modules, and kernel version.

## Test

See the [standalone KUnit instructions](tests/standalone-kunit/README.md). Tests do not replace or unload the active HID driver.

Read the [requirements](../../REQUIREMENTS.md) and [test results](../../wiki/Validation.md) before changing the driver on a Legion Go.

## Install and remove

Scripts: [`../../packaging/hid-lenovo-go/`](../../packaging/hid-lenovo-go/).

Run these commands only on the live-verified Original Legion Go:

```sh
sudo packaging/hid-lenovo-go/scripts/install.sh
```

The install script adds a disabled service. Use these scripts to load the driver, restore the original driver, or uninstall:

```sh
sudo /usr/local/lib/legion-go-ogui/hid/current/activate.sh
sudo /usr/local/lib/legion-go-ogui/hid/current/deactivate.sh
sudo /usr/local/lib/legion-go-ogui/hid/current/uninstall.sh
```

They stop InputPlumber before changing the driver and restart it after restoration. Do not run `load.sh` or `unload.sh` while InputPlumber is active.

## If a command fails

Stop after the first error. Do not force loading or unloading.

Run `deactivate.sh` to restore the original driver and restart InputPlumber. Confirm that the controller works before uninstalling. If restoration fails, keep the files and fix the problem before trying again.

See the [Technical Reference](../../wiki/Technical-Reference.md) and [Research](../../wiki/Research.md).
