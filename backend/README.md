# Backend tools

These battery, controller, and fan tools support only the original Lenovo Legion Go. They require DMI vendor `LENOVO` and product name `83E1`. The fan tool also requires product version `Legion Go 8APU1`.

## Build and test

Run from this directory:

```sh
cargo build --release --locked
cargo test --locked
```

To build and install the plugin from source, run `make` in the repository root. It builds temporary local payloads and removes them after installation.

Use `Cargo.lock`. The scripts do not download files.

## Commands

Each tool prints one JSON object. Status commands do not need root. Setting commands need root.

| Tool | Commands |
| --- | --- |
| `legion-go-ogui-helper` | `status`, `enable`, `disable` |
| `legion-go-ogui-controller` | `status`, `swap-enable`, `swap-disable`, and `calibrate-<left|right>-<joystick|trigger|gyro>-<start|stop>` |
| `legion-go-ogui-fan` | `status`, `set-fullspeed 0|1`, and `set-curve` followed by ten nondecreasing values |

The battery tool writes only `Long_Life` or `Standard` to `charge_types`. It returns 80 or 100 after readback. The controller tool accepts only listed names. The fan tool reads `fan1_input`, Full Speed, and the curve from fixed Lenovo WMI owners. Curve values must not decrease. The current tool limits custom levels to `0..125` through 70 °C, at least `79` at 80–90 °C, and at least `100` at 100 °C. It does not establish an EC maximum. The exact Quiet and Balanced tables remain accepted.

The tools do not accept paths, raw HID reports, ACPI methods, shell commands, or other unrestricted input.

## Install

**Warning:** Installation changes `/usr/local` and `/etc`. Run it only on the supported device.

Install the plugin from source first. Then open its settings and select **Install backend**.

Do not use `sudo`. The installer asks for administrator access when needed. It builds and packages the HID and integrated Lenovo WMI modules for the running kernel. It installs these tools and the Polkit rule:

```text
/usr/local/libexec/legion-go-ogui-helper
/usr/local/libexec/legion-go-ogui-controller
/usr/local/libexec/legion-go-ogui-fan
/etc/polkit-1/rules.d/49-legion-go-ogui-helper.rules
```

Fan control uses the integrated Lenovo WMI owner. A first **Install backend** action builds, activates, and enables the HID and WMI modules after the exact-device check and administrator approval. A later update rebuilds both modules and preserves each service-enabled state.

## Install at the next login

```sh
./schedule-desktop-install.sh
```

The script creates `~/.config/autostart/legion-go-ogui-backend-install.desktop`. GNOME opens a terminal at the next login. The entry removes itself after use.

## Uninstall

```sh
./uninstall-backend.sh
```

It removes the tools, Polkit rule, and project HID package.

## Administrator access

The Polkit rule permits only the three tools, not a shell. Each tool checks its command and values after administrator access.

Bazzite uses a read-only system image. The installer uses writable locations under `/usr/local` and `/etc`.

## More information

- [Plugin status](../README.md)
- [HID driver](../drivers/hid-lenovo-go/README.md)
