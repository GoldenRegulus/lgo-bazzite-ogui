# Lenovo WMI tuning driver — immutable packaging

This package replaces the stock `lenovo_wmi_other` kernel module with a project module that builds from `drivers/lenovo-wmi-fan/wmi-other.c`. The project module exposes independent Full Speed, fan curves, RPM, and battery charge controls through the same WMI GUIDs.

## Requirements

- Exact DMI: `LENOVO`, `83E1`, `Legion Go 8APU1`
- Running kernel headers (`kernel-devel` for `uname -r`)
- Stock module: `lenovo_wmi_other`
- Supporting modules: `firmware_attributes_class`, `lenovo_wmi_capdata`, `lenovo_wmi_helpers`, `wmi`

## Files

- `Makefile` — external kernel module build
- `include/` — pinned OGC commit `9c37615c` headers
- `scripts/` — lifecycle management scripts
- `systemd/` — systemd service unit

## Scripts

### install
Build the external module, create an immutable release with exact hashes, install the service disabled. Does not activate.

Run as root:
```bash
./scripts/install.sh
```

### activate
Start the systemd service. The service locks, verifies the system, saves the stock module, unloads it, loads the project module, and checks WMI GUID ownership and interfaces.

Run as root:
```bash
./scripts/activate.sh
```

### deactivate
Stop the systemd service. The service unloads the project module and restores the exact stock module without writing fan state.

Run as root:
```bash
./scripts/deactivate.sh
```

### uninstall
Deactivate (if active), verify the stock module, and remove all project files.

Run as root:
```bash
./scripts/uninstall.sh
```

### validate-host
Check that the host DMI matches the Original Go.

### validate-lifecycle
Run as root. It performs read-only checks on the release, module hashes, active module, and sysfs interfaces. It makes no hardware write.

## Build

The external Makefile builds one `lenovo-wmi-tuning.ko` from `wmi-other.c` with:

```bash
make -C /lib/modules/$(uname -r)/build M=. W=1 KCFLAGS=-Werror
```

The module name is `lenovo_wmi_tuning`. It depends on the kernel's `firmware_attributes_class`, `lenovo_wmi_capdata`, `lenovo_wmi_helpers`, and `wmi` modules.

## Immutable release

Each release records:

- Running kernel release
- Source SHA-256 (includes all headers)
- Module SHA-256
- Lifecycle-script SHA-256
- Vermagic
- Build ID (GNU note)

The release also records the exact stock module path, hash, and build ID.

## Safety

- The install, activate, deactivate, uninstall, and validation scripts never write hardware values.
- The stock module file is never overwritten.
- If activation fails, the project module is unloaded and the stock module restored.
- A root-only recovery marker is created if exact restoration fails.
- The service is disabled by default.

## Deactivation

Deactivation unloads the project module and restores the stock module. It does not write fan state. The firmware fan curve stays unchanged.
