# Validation

This document contains live-device procedures and test evidence.

## Live-Device Diagnostics

### Test record requirements

Record:

- date and test owner;
- exact Legion Go model and machine type;
- BIOS and EC versions;
- Bazzite image name and image digest;
- kernel version;
- OGUI, HHD, InputPlumber, and related service versions;
- controller attachment state and FPS-mode state;
- command, complete relevant output, expected result, and actual result;
- suspend, resume, reboot, and rollback results when relevant.

Remove user names, host names, serial numbers, network addresses, account data, and unrelated logs before committing output.

### Stage 1 — Read-only inventory

Run these commands on the Legion Go. They do not request a hardware write. Review the output for serial numbers before you share it.

```bash
printf '%s\n' '=== system ==='
uname -a
cat /etc/os-release
rpm-ostree status || bootc status || true

printf '%s\n' '=== DMI and firmware ==='
for f in sys_vendor product_name product_version product_sku board_name bios_vendor bios_version bios_date; do
  printf '%s=' "$f"
  cat "/sys/class/dmi/id/$f" 2>/dev/null || true
done
sudo dmidecode -t 0 -t 1 -t 2 2>/dev/null | sed -E '/Serial Number:|UUID:|Asset Tag:/d' || true

printf '%s\n' '=== packages and services ==='
rpm -q opengamepadui inputplumber hhd adjustor powerstation steamos-manager-powerstation 2>/dev/null || true
systemctl --no-pager --full status inputplumber hhd powerstation steamos-manager 2>/dev/null || true
busctl --system list | grep -Ei 'shadowblip|hhd|powerstation|inputplumber' || true

printf '%s\n' '=== modules ==='
lsmod | grep -Ei 'lenovo|hid|iio|acpi_call|hwmon' || true
modinfo hid-lenovo-go lenovo-wmi-other acpi_call 2>/dev/null || true
if test -r "/boot/config-$(uname -r)"; then
  grep -E 'CONFIG_(HID_LENOVO|LENOVO_WMI|ACPI_BATTERY|IIO|HWMON)' "/boot/config-$(uname -r)"
fi

printf '%s\n' '=== battery capabilities ==='
find -L /sys/class/power_supply -maxdepth 2 -type f \
  \( -name type -o -name status -o -name capacity -o -name charge_type \
  -o -name charge_types -o -name charge_control_end_threshold \
  -o -name charge_behaviour \) -print -exec sh -c 'cat "$1" 2>/dev/null' sh {} \;

printf '%s\n' '=== profiles and firmware attributes ==='
find -L /sys/class/platform-profile -maxdepth 2 -type f -print \
  -exec sh -c 'cat "$1" 2>/dev/null' sh {} \;
find -L /sys/class/firmware-attributes -maxdepth 5 -type f -print \
  -exec sh -c 'cat "$1" 2>/dev/null' sh {} \;

printf '%s\n' '=== hwmon ==='
for n in /sys/class/hwmon/hwmon*/name; do
  test -r "$n" || continue
  d=${n%/name}
  printf '%s: %s\n' "$d" "$(cat "$n")"
  find -L "$d" -maxdepth 1 -type f \
    \( -name 'fan*' -o -name 'pwm*' -o -name 'temp*_input' \) -print
 done

printf '%s\n' '=== HID and handle attributes ==='
find -L /sys/bus/hid/devices -maxdepth 3 -type f \
  \( -path '*/left_handle/*' -o -path '*/right_handle/*' \
  -o -name modalias -o -name uevent \) -print \
  -exec sh -c 'case "$1" in *calibrate_joystick|*calibrate_trigger|*calibrate_gyro|*/reset) : ;; *) cat "$1" 2>/dev/null ;; esac' sh {} \;

printf '%s\n' '=== input and IIO ==='
cat /proc/bus/input/devices
for d in /sys/bus/iio/devices/iio:device*; do
  test -d "$d" || continue
  printf '%s\n' "--- $d"
  grep -H . "$d"/name "$d"/in_*_scale "$d"/in_*_sampling_frequency "$d"/in_*_sampling_frequency_available 2>/dev/null || true
  test -r "$d"/in_mount_matrix && cat "$d"/in_mount_matrix || true
done

printf '%s\n' '=== udev properties for Lenovo input ==='
for d in /sys/class/input/event*/device; do
  props=$(udevadm info --query=property --path="$d" 2>/dev/null || true)
  if printf '%s\n' "$props" | grep -Eqi '17EF|LENOVO|Legion'; then
    printf '%s\n' "--- $d"
    printf '%s\n' "$props" | grep -Ev '^(ID_SERIAL|ID_SERIAL_SHORT|ID_USB_SERIAL|ID_USB_SERIAL_SHORT|ID_UUID)='
  fi
done
```

Notes:

- `sudo dmidecode` is read-only, but it can show identifying data. The command removes common serial and UUID lines.
- Do not read or share `/proc/acpi/call`.
- Do not write to `charge_types`, `profile`, firmware attributes, `pwm*`, `calibrate_*`, `reset`, or HID attributes during Stage 1.
- Save the output with the date and target image digest.

### Stage 2 — Passive event capture

After device identification:

1. Capture events from one physical control at a time.
2. Record the controller attachment and FPS-mode state.
3. Do not grab a device that the active desktop session needs unless a recovery input is available.
4. Test left and right gyro motion with a known device orientation.
5. Repeat after detach, reconnect, suspend, and resume.

### Stage 3 — Approved active tests

Run an active write only after the wiki records:

- the source for the interface;
- allowed values and units;
- expected read-back value;
- thermal or input safety limit;
- conflict owner shutdown or coordination method;
- rollback operation;
- an independent recovery method.

Test one subsystem at a time. Keep AC power and a second control method available for fan and controller tests.

### Data that will probably need a live device

- Confirmed charge-limit behavior above and below 80%.
- Actual fan-mode values and curve constraints for the installed BIOS/EC.
- Fan fallback after process failure, suspend, and reboot.
- Gyro identity, orientation, scale, rate, latency, and hotplug behavior.
- Raw left/right, Menu/View, and FPS-mode input events.
- Controller firmware or user-space calibration behavior.
- Coexistence with the exact Bazzite input stack.

### Stop conditions

Stop an active test if:

- fan speed does not react as expected;
- a temperature approaches the agreed safety limit;
- the hardware state cannot be read back;
- two services write the same interface;
- input loss removes the only recovery control;
- a write persists after its documented reset;
- the machine, BIOS, or EC identifier differs from the approved target.

## Test Record — Restricted Battery Backend

**Date:** 2026-07-30

**Target:** Original Lenovo Legion Go 8APU1, DMI `83E1`

### Verified results

- The Linux x86_64 Rust build passed nine unit tests.
- Unprivileged `status` reported Long Life mode and threshold 80.
- An unprivileged `enable` request returned the bounded privilege error and did not change the threshold.
- The OGUI store archive extracted the text-encoded helper payload and all setup files to the expected user plugin directory.
- The one-time scheduler created a fixed GNOME autostart entry in an isolated test home.
- Plugin version 0.2.1 added the `quick-bar` lifecycle tag. OGUI then initialized the enabled plugin automatically after restart.

### First privileged-request failure

The first Desktop installer copied the helper and Polkit rule. The plugin could run unprivileged status and showed the backend as ready. Its first privileged request did not execute the helper and returned no JSON. The UI therefore showed an invalid-response error. The old 15-second status poll then read the unchanged 80% hardware state and reset the toggle to Long Life mode.

This sequence did not make an unconfirmed battery write. The confirmed threshold remained 80.

### Corrections

Version 0.2.2:

- restarts Polkit after backend installation and removal;
- verifies the exact Polkit authorization during installation;
- keeps unprivileged status methods separate from root-required mutation methods;
- shows a distinct in-progress state during a request;
- preserves the failed-request result in a separate row;
- performs one immediate unprivileged status read after a failed request;
- changes periodic polling from 15 seconds to 60 seconds and polls only while the menu is visible;
- refreshes when the settings menu becomes visible;
- offers a repair or update setup action when the backend already exists.

### Direct version 0.2.2 backend update

At the project owner's request, the updated backend was installed directly with administrator access. The test confirmed:

- the installed helper and Polkit rule are root-owned;
- the installed helper hash matches the reviewed Linux build;
- Polkit restarted after rule installation;
- an authorization check for the active OGUI process and `/usr/local` helper alias returned `yes`;
- helper status reported Long Life mode at 80%;
- installation did not change the threshold.

### Plugin write verification

After the canonical-path correction, the project owner confirmed that the plugin control works. System logs recorded the exact root-owned helper operations in order:

1. `disable`, which requests and verifies 100% Standard mode;
2. `enable`, which requests and verifies 80% Long Life mode.

A final independent status read reported Long Life mode at 80%. The helper performs readback before it returns success, so this is a controlled `80 → 100 → 80` cycle. No SteamOS Manager, PowerStation, TDP, platform-profile, fan, or input operation was involved.

### Pending verification

- Confirm in-progress, success, failure, restart, visibility refresh, and 60-second polling behavior in OGUI.

### Canonical-path correction

The next live plugin request still failed authorization. Bazzite maps `/usr/local` to `/var/usrlocal`. The installed helper resolves to `/var/usrlocal/libexec/legion-go-ogui-helper`, and the effective pkexec path can use that canonical name. The first rule authorized only the `/usr/local` alias.

Version 0.2.3 calls the canonical path. The narrow rule permits only the `/usr/local` and `/var/usrlocal` aliases of this root-controlled helper. A Polkit check for the active OGUI process changed from `auth_admin` with the old rule to `yes` with the corrected rule. The threshold stayed at 80 during diagnosis and deployment.

## Test Record — SteamOS Manager Charge Limit

**Date:** 2026-07-30

**Target:** Original Lenovo Legion Go 8APU1, DMI `83E1`

**Baseline:** Bazzite testing 44, kernel 7.1.5, SteamOS Manager PowerStation package `0~20260727.git1a6e985-1.fc44`

### Purpose

Determine whether the existing SteamOS Manager service can expose the native SteamOS 80% charge-limit operation.

### Safety controls

- Read the initial kernel threshold before the call.
- Accept an initial value only in the range 50–100.
- Start a root-owned two-minute automatic rollback before the call.
- Request the same `80%` value that was already active.
- Read the kernel threshold after the call.
- Restore the initial value immediately if it changes unexpectedly.
- Cancel the rollback only after readback.

The test did not change fan, TDP, platform profile, controller, or gyro state.

### Result

Initial kernel threshold:

```text
80
```

SteamOS Manager returned:

```text
Call failed: No battery charge limit configured
```

Final kernel threshold:

```text
80
```

The rollback timer was inactive after the test.

### Source explanation

The live `legion-go-series.toml` has no `[battery_charge_limit]` section. Reviewed SteamOS Manager source returns `No battery charge limit configured` when this section is absent.

The existing `acpi_sb` method searches ACPI battery power-supply directories for `charge_control_end_threshold`. This is the same kernel attribute that exists on the live Legion Go.

The current `legion-go-series.toml` groups `83E1` with Legion Go 2 products `83N0` and `83N1`. A battery section at file scope would apply to all three products. The project must not claim untested Legion Go 2 support.

First isolate `83E1` in its own device configuration. It can then include:

```toml
[battery_charge_limit]
method = "acpi_sb"
```

### Temporary device-data test

The project copied the installed device-data directory to `/run`, applied the two-file split there, and bind-mounted it over the packaged directory. A five-minute systemd rollback was active before the mount. No package or image changed.

After both SteamOS Manager services restarted:

```text
device_model=legion_go / 83E1
public_battery_interface=present
public_limit_before=Max charge level: 80
public_limit_after=Max charge level: 80
kernel_threshold_after=80
```

The public `steamosctl set-max-charge-level 80` same-value operation succeeded. The first test harness reported failure only because it expected a bare `80` from the getter. The actual getter format is `Max charge level: 80`.

### Native Steam UI test

With the temporary interface active, Steam showed **Enable battery charging limit** in **Settings → Power**. The toggle was initially off even though both SteamOS Manager and the kernel reported 80.

The project owner enabled the toggle. Steam showed 80%, and readback stayed consistent:

```text
Steam UI: Enabled, 80%
SteamOS Manager: 80
Kernel threshold: 80
```

The project then removed the temporary mount without restarting Steam. Steam removed the battery control immediately while the Power page remained open. A second test added the interface without restarting Steam, and the project owner used the new control. This verifies dynamic interface addition and removal.

### Slider and disable test

Kernel source describes this Lenovo function as two charge types: Standard and Long Life at 80%. The second live test changed the continuous Steam slider with a 15-minute automatic rollback.

| Steam action and display | SteamOS Manager readback | Kernel readback | Result |
|---|---:|---:|---|
| Enable at 80% | 80 | 80 | Matched |
| Set 90% | 100 | 100 | Firmware normalized to Standard; Steam stayed at 90% |
| Set 70% | 80 | 80 | Firmware normalized to Long Life; Steam stayed at 70% |
| Disable toggle | 80 | 80 | Hardware stayed in Long Life while Steam showed Off |

No charge-related service error appeared. The native UI did not update from confirmed service or kernel state.

`SuggestedMinimumLimit = 80` can remove slider values below 80. It cannot describe the discrete allowed set `{80, 100}` and cannot prevent values from 81 through 99.

The cleanup removed the mount and temporary files, restored the initial threshold, restarted both SteamOS Manager services, and canceled the timer. Post-test verification showed:

```text
threshold=80
device_bind_mount=inactive
system_manager=active
user_manager=active
rollback_timer=inactive
public_battery_interface=absent
temporary_files=absent
```

### Conclusion

The current Bazzite image does not expose `BatteryChargeLimit1` for `83E1`. The plugin must not call the private root D-Bus interface directly.

The local test verifies that a SteamOS Manager device-data split can give `83E1` the public battery interface and use the existing kernel threshold. However, the current continuous Steam interface cannot truthfully represent the firmware's binary 80% and 100% modes. The test-only configuration must not be packaged as device support.

A complete native solution needs discrete supported-limit semantics and confirmed UI readback. The project later selected a global OGUI plugin toggle with a restricted binary helper instead. See DEC-010. This test record remains the evidence for rejecting the continuous native interface.

## Test Record — Fan and Controller Backends

**Date:** 2026-07-30

**Target:** Original Lenovo Legion Go 8APU1, DMI `83E1`, BIOS/EC 1.40

### Current fan revalidation — 2026-08-02

This section supersedes the old production-state and service-state statements below. The earlier sections remain as historical protocol and bounds evidence.

The project reduced the fan kernel ABI to RPM, independent Full Speed, and one complete ten-point curve. It removed kernel mode labels, duplicate point controls, `pwm1_enable`, and Automatic policy. The plugin owns named modes and complete tables. Curve submission does not change Full Speed.

The final source uses Lenovo Other Mode WMI feature methods for Full Speed and RPM. This matches the upstream `lenovo_wmi_other` route and works while that upstream driver remains bound. Curve read and submission use WMAB operations `0x05` and `0x06`. The exact DMI gate remains `LENOVO`, `83E1`, and `Legion Go 8APU1`. The driver skips redundant firmware mutations, confirms changed values by readback, blocks writers during removal, and restores the exact probe state only if a write made that state dirty.

Static verification passed:

- strict checkpatch with zero findings;
- external build against the target kernel with `W=1 KCFLAGS=-Werror`;
- standalone KUnit 5/5;
- source SHA-256 `4b87ba413744f679bd000b4db3b137a5ea05c885bea17570330c386cdb179805`;
- module SHA-256 `890c18008f0301c641af02a56fe1f2f01bae013512af6b5040d207f91fe3e66d`.

Packaging now uses immutable release directories, atomic `current`, ELF build-ID checks, a runtime lock, active and recovery markers, bounded systemd operations, exact uninstall, and a disabled-by-default service. Three activation and deactivation cycles passed. Each cycle read valid RPM, Full Speed `0`, and curve `44 44 55 60 71 87 100 100 100 100`. Idempotent sysfs submissions passed without a firmware mutation. Package update, uninstall, and reinstall also passed with the module absent and the service disabled after completion.

One controlled dirty-state test submitted safe curve `125 125 125 125 125 125 125 125 125 125`, confirmed it, enabled and confirmed Full Speed, and read `8837 RPM`. Deactivation restored both dirty values. A new activation confirmed the original curve and Full Speed `0`; immediate post-restore RPM was `8873` because fan speed had not settled. The test then deactivated the module. No kernel fault or persistent D-state task occurred.

The restricted Rust fan helper now exposes only `status`, `set-fullspeed 0|1`, and `set-curve` with exactly ten values. It reads only the three raw kernel attributes, confirms the requested field, and leaves the other field unchanged. The plugin now owns all named labels and complete curves and shows Full Speed separately. Backend tests pass 47/47. A Linux x86-64 release binary executed on the target and returned the expected driver-unavailable failure while the service was inactive. The backend installer now delegates to immutable fan packaging and does not directly stop, remove, start, or enable the fan module.

Release `16d2f7b7473ac44a83199f83aed27e9d53e101a152eff4d6ef28fa3cd120f2b9` is now installed as the immutable current release. It saves the probe state in root-only runtime files. Unload restores and confirms that state before `rmmod`; a failed confirmation leaves the module loaded and marks recovery incomplete. The raw helper with SHA-256 `950d71a24e9eb347bdebadd59712dd81721459d3015e7ce3a57d10f2e551cf4d` is also installed, with the prior helper retained in a root-owned hash-addressed backup.

A no-write activation captured curve `44 44 55 60 71 87 100 100 100 100` and Full Speed `0`; helper status reported `4178 RPM`. The fixed all-`125` plus Full Speed test reached `8837 RPM`. Unload used the added pre-restore path, and a new activation confirmed the exact original values. Immediate post-restore RPM was `8801` because fan speed had not settled. A bounded concurrent reader exited during unload without a fault, persistent D-state task, or incomplete recovery marker.

Final live state: release `16d2f7...f2b9` and the raw helper are installed. The service is disabled and inactive. The module is absent. InputPlumber is active. Five D-state samples were clear, and the current boot has no kernel fault. Suspend and resume and one controlled clean boot remain release gates.

### Controller backend

The separate `legion-go-ogui-controller` Rust binary passed 25 unit tests. Tests cover exact DMI and HID discovery, all fixed command names, root rejection, all twelve calibration path/value combinations, exact seven-byte swap payloads, partial-write failure, and requested-state persistence.

The Linux x86_64 binary was built on the target image. Unprivileged status found the single `0003:17EF:61EB` controller and read all six calibration interfaces. Each reported commands `start stop` and status `unknown`. The root-owned binary and narrow Polkit authorization were installed. An authorization check for the active OGUI process returned `yes`.

No calibration or swap mutation was sent during backend installation. Live project-owner testing later confirmed that firmware button swap works.

A plugin-triggered calibration `start` write returned success from sysfs, but no blue controller LED sequence started and every kernel result remained `unknown`. Source review then found that Linux `hid-lenovo-go` function `mcu_property_out()` converts a 50 ms timeout to `-EBUSY` but unconditionally returns `0`. It also completes its shared wait for any handled configuration report, without command correlation. Thus, the observed success was a kernel false-success path, not proof of firmware acceptance. Plugin version 0.5.2 removes these unconfirmed write actions from the visible UI. It supplies Lenovo's physical-button calibration guide and does not report a calibration trigger as complete. Static Legion Space protocol research continues.

### Fan module

The fan module is based on `honjow/lenovo-legion-go-wmi-fan` commit `60365f1204aa97aaa0604c27197530c2474c90cd`. It requires DMI values `LENOVO`, `83E1`, and `Legion Go 8APU1`.

The target built the module against kernel `7.1.5-ogc2.1.fc44.x86_64`. Secure Boot was disabled. Initial systemd loading failed because SELinux labeled the module `lib_t`. Relabeling it `modules_object_t` fixed loading. The installer now applies this label.

Probe read the firmware curve without a write:

```text
44 44 55 60 71 87 100 100 100 100
```

The module reported Automatic mode and `pwm1_enable=2`. Probe did not change the Linux platform profile.

### Controlled fan writes

The restricted `legion-go-ogui-fan` helper and module completed these tests:

1. Automatic → Full Speed → Automatic.
2. Automatic → Custom minimum curve → Automatic.

The atomic Custom test used:

```text
44 48 55 60 71 79 87 87 100 100
```

Each helper call returned matching mode and curve readback. Returning to Automatic restored the probe-time curve exactly. The Linux platform profile remained `performance` before and after both tests. The code does not call platform-profile, WMAA, or TDP methods.

The fan service is enabled and active. A controlled service restart unloaded and reloaded the module. Automatic mode and the exact probe-time curve matched before and after restart. The service loads only the module built for the exact running kernel. A kernel update without a matching module file fails closed.

### Tachometer and zero-valued curve research

The original `83E1` DSDT identifies fan tachometer bytes `FANL` and `FANH` at EC offsets `0x8B` and `0x8C`. Its fixed WMAE getter uses method `0x11`, device `0x04`, feature `0x03`, and type `0x0001`. The module now exposes this value as standard hwmon `fan1_input` and bounded `fan_rpm`. Live Full Speed read `9457 RPM`.

A guarded experimental module tested curve `0 0 0 0 0 0 100 100 100 100`. The firmware getter confirmed the exact zero-valued curve. A separate five-second systemd watchdog and explicit restoration protected the test. RPM started at `9457`, then decreased to `6514` before the script restored Full Speed because it crossed the `7000 RPM` abort threshold. The production module, original curve, Full Speed state, and `performance` platform profile were restored. RPM returned to `9457` after fan inertia. This proves that firmware accepts zero-valued points. It does not yet prove stable zero-RPM operation or the exact thermal breakpoint sensor.

A second guarded test compared Full Speed with an all-`100` Custom curve. Full Speed started at `9415 RPM`. Custom readback confirmed `100 100 100 100 100 100 100 100 100 100`. RPM decreased each second and reached `7619 RPM` after 12 seconds. Maximum measured temperature increased from `84.5 °C` to `85.9 °C`. The test then restored the original curve and Full Speed. RPM returned to `9415`, and the platform profile remained `performance`. This proves that firmware curve level `100` is the normal Windows custom-curve ceiling near `7500 RPM`, not 100% of the separate Full Speed override near `9400 RPM`.

An exact-kernel experimental module bounded curve input and readback at `125`. A guarded all-`110` test returned the exact values and settled near `8293 RPM`. A guarded all-`125` test returned the exact values and held between `9375` and `9457 RPM`, equal to the separate Full Speed override. Temperature did not exceed `86 °C`. Both tests restored the original curve, production module, Full Speed, and `performance` platform profile. Thus, original `83E1` firmware accepts values above `100`, and level `125` is the live-verified Full Speed ceiling. Values above `125` remain untested and unsupported.

Production version `0.7.4` accepts nondecreasing Custom values from `44` through `125`. It shows the current Lenovo per-point ranges as recommendations and requires confirmation outside them. Levels below `44` remain unavailable until a cool-device test proves safe stop and restart behavior.

The exact-kernel production module and backend were installed on kernel `7.1.5-ogc2.1.fc44.x86_64`. The first installer verification failed because systemd still considered the prior oneshot service active after the old module was removed. A service restart loaded the new module. The installer now stops an active service before it replaces the module. It also restores Full Speed when that mode was active before installation. A second verification defect used the installer shell instead of the active OGUI process for Polkit checks. The installer now checks the active OGUI process, or defers runtime verification when OGUI is not running. A direct test confirmed all three OGUI Polkit authorizations.

The backend reported `curve_min: 44` and `curve_max: 125`. An all-`125` Custom request returned the exact ten values and held `9375 RPM`. Full Speed restoration returned `9457 RPM`. An Automatic then Full Speed sequence restored the probe-time curve `44 44 55 60 71 87 100 100 100 100`. The platform profile stayed `performance`.

Plugin `0.7.0` exposed a GDScript parse error because the confirmation path referred to an undeclared `calibration_dialog`. Version `0.7.1` and later obtain OGUI's shared dialog by group, as the calibration guide does. OGUI initialized final version `0.7.4` without a parse or script error. The final live state was Full Speed at `9457 RPM`, the restored probe-time curve, and `performance` platform profile. The device temperature was approximately `92.5 °C`, so no low-speed test was permitted.

### Remaining fan scope

Full Speed, Automatic, and atomic ten-point Custom infrastructure are live-verified. At the time of this test, Quiet, Balanced, and Performance had not been traced. Later Windows disassembly proved that separate `SetFanMode` values `2`, `3`, and `4` select original-GO preset fan tables rather than `SetSmartFanMode`. The project owner also confirmed that fan and power profiles are independent in Legion Space. Later static analysis recovered the exact tables and confirmed the final `Fan_Set_Table` path. Controlled Linux validation remains pending.

## Test Record — OGUI and InputPlumber Gyro Path — 2026-07-30

### Scope

This test used read-only SSH inspection, D-Bus property reads, OGUI settings reads, and journal reads. It did not change translation, target devices, filters, profiles, services, or input state.

### Stack ownership

Bazzite 44 replaced HHD with OGUI and InputPlumber for this controller path:

```text
OGUI settings and UI
    |
    | InputPlumber D-Bus profile and target operations
    v
InputPlumber composite device
    |
    +--> Lenovo controller hidraw: controls and left/right motion
    +--> IIO gyro: center motion
    +--> virtual target: current deck-uhid controller
```

HHD is historical evidence only. It is not part of the target stack.

### Live OGUI state

The packaged OGUI launcher started the user-data update binary. The packaged version is `0.46.0-3.fc44`. The exact update-binary revision is not yet known.

Relevant live settings are:

```ini
[input]
gamepad_profile_target="ds5-edge"

[game.bin]
gamepad_profile_target="deck-uhid"
```

The per-game `game.bin` value overrides the global value for the current launch. The active InputPlumber target is therefore `deck-uhid`, with keyboard and mouse targets.

OGUI logs confirm that it:

1. loads the OpenGamepadUI default profile;
2. adds target-specific touchpad mapping;
3. requests `deck-uhid`, keyboard, and mouse through InputPlumber.

The current “translation disabled” UI state does not mean that InputPlumber releases the physical controller. InputPlumber still owns the source and supplies a virtual Steam Deck target.

### Gyro failure cause

The live InputPlumber composite detects:

```text
Gyroscope:Center
Gyroscope:Left
Gyroscope:Right
Accelerometer:Center
Accelerometer:Left
Accelerometer:Right
```

All six events are also present in the live `FilteredEvents` property. InputPlumber filters them at the source before generic target conversion. The current OGUI profile has no gyro mapping or filter override.

Both `deck-uhid` and `ds5` targets implement the generic `Gamepad:Gyro` capability in InputPlumber source. Therefore, changing only the target to DualSense 5 is not expected to fix gyro. The selected target receives no motion event while all source motion events remain filtered.

InputPlumber introduced `deck-uhid` in commit `aff30b08` and changed the Legion Go S profile from `deck` to `deck-uhid` in the same commit. The live `83E1` target records an OGUI selection. It does not prove native SteamOS support for the original Legion Go.

Issue #418 documents the intended owner split. InputPlumber prefers a Linux kernel driver when the kernel lacks a suitable HID or IIO device. InputPlumber then owns profile matching, physical-source capture, composite routing, and virtual targets.

Relevant sources:

- [Legion Go 2-compatible HID motion parser](https://github.com/ShadowBlip/InputPlumber/blob/082f67fba6aaff88441abdc482ae76b711ad2885/src/input/source/hidraw/legion_go2.rs#L164-L240)
- [IIO center motion parser](https://github.com/ShadowBlip/InputPlumber/blob/082f67fba6aaff88441abdc482ae76b711ad2885/src/input/source/iio/accel_gyro_3d.rs#L89-L138)
- [Controller-motion default filter](https://github.com/ShadowBlip/InputPlumber/blob/082f67fba6aaff88441abdc482ae76b711ad2885/src/drivers/lego/go2_driver.rs#L78-L106)
- [IIO-motion default filter](https://github.com/ShadowBlip/InputPlumber/blob/082f67fba6aaff88441abdc482ae76b711ad2885/src/drivers/iio_imu/driver.rs#L126-L168)
- [Generic source-to-target gyro conversion](https://github.com/ShadowBlip/InputPlumber/blob/082f67fba6aaff88441abdc482ae76b711ad2885/src/input/composite_device/mod.rs#L1088-L1127)
- [`deck-uhid` gyro capability](https://github.com/ShadowBlip/InputPlumber/blob/082f67fba6aaff88441abdc482ae76b711ad2885/src/input/target/steam_deck_uhid.rs#L782-L825)
- [`deck-uhid` introduction with the Legion Go S profile](https://github.com/ShadowBlip/InputPlumber/commit/aff30b08fb715361db143bec5e2d02f9368e46eb)
- [InputPlumber contributor and owner notes](https://github.com/ShadowBlip/InputPlumber/issues/418)
- [DualSense gyro capability](https://github.com/ShadowBlip/InputPlumber/blob/082f67fba6aaff88441abdc482ae76b711ad2885/src/input/target/dualsense.rs#L975-L1004)

### Why translation cannot be undone in the UI

OGUI stores target selection in `gamepad_profile_target`. Its current blank-target path does not request an empty InputPlumber target list. It loads a profile and can reuse the active target.

Even an empty target list would not restore native input. The InputPlumber composite still owns and hides the physical source. Physical input returns only when the composite releases its sources, such as during a controlled composite stop or InputPlumber restart.

Relevant sources:

- [OGUI launch target selection](https://github.com/ShadowBlip/OpenGamepadUI/blob/b149644f46b71e175a2ad223e84c18361596691e/core/global/launch_manager.gd#L467-L539)
- [OGUI gamepad target settings](https://github.com/ShadowBlip/OpenGamepadUI/blob/b149644f46b71e175a2ad223e84c18361596691e/core/ui/card_ui/gamepad/gamepad_settings.gd#L617-L692)
- [InputPlumber source release during composite stop](https://github.com/ShadowBlip/InputPlumber/blob/082f67fba6aaff88441abdc482ae76b711ad2885/src/input/composite_device/mod.rs#L590-L613)

The live InputPlumber journal also contains repeated `Device or resource busy` errors during one controller re-enumeration. This can contribute to failed runtime restoration, but it does not prove the primary cause.

### Active center-filter test

The project owner approved the runtime test. The test:

1. confirmed the original filter map;
2. kept `deck-uhid`, keyboard, and mouse targets unchanged;
3. removed only `Gyroscope:Center` from the requested center IIO filter;
4. scheduled an automatic 15-minute restoration timer.

The D-Bus property showed the requested test value, but InputPlumber logged:

```text
Failed to set filtered events: failed to send command to device
```

The test stopped before Steam validation because the runtime source state was not reliable. The original six-event filter map was restored, the rollback timer was canceled, and InputPlumber remained active. No reboot was necessary.

Source review explains the failure mode. InputPlumber 0.78 iterates all composite source clients when it sets `FilteredEvents`. It sends an empty filter to sources that are absent from the requested map and stops at the first closed source command channel. The live journal already showed source re-enumeration and stale or busy devices. A D-Bus property read can therefore show some updated sources even though the complete operation failed.

Relevant source:

- [InputPlumber `set_filtered_events`](https://github.com/ShadowBlip/InputPlumber/blob/082f67fba6aaff88441abdc482ae76b711ad2885/src/input/composite_device/mod.rs#L2169-L2198)
- [InputPlumber source command client](https://github.com/ShadowBlip/InputPlumber/blob/082f67fba6aaff88441abdc482ae76b711ad2885/src/input/source/client.rs#L124-L139)

#### Test conclusion

Do not use the current live `FilteredEvents` setter for interactive gyro control. This result does not by itself authorize an InputPlumber change. First, determine whether OGUI lifecycle, controller re-enumeration, or plugin call order created the stale source. A controlled InputPlumber restart could clear stale clients, but it is not necessary until the plugin test harness is safer.

### Result

**Read-only investigation passed. The active filter test failed safely and restored its baseline.**

The strongest current cause of missing Steam gyro is source filtering, not lack of gyro support in the virtual target. The live runtime filter setter is also unreliable after source re-enumeration. DualSense translation should remain disabled until these InputPlumber paths are corrected.

## Live Test Record — Read-Only Baseline — 2026-07-30

### Scope

This test used SSH to inspect the project owner's original Legion Go. It made no hardware, sysfs, D-Bus, service, configuration, or input-state changes. The repository does not contain the host address, password, hardware unique ID, battery serial, or raw diagnostic output.

### Target baseline

| Item | Observed value |
|---|---|
| Device | Lenovo Legion Go 8APU1 |
| DMI vendor | `LENOVO` |
| DMI product | `83E1` |
| Board | `LNVNB161216` |
| BIOS | `N3CN40WW`, release 1.40, dated 2025-09-04 |
| EC firmware release | 1.40 |
| Image | `bazzite-deck-gnome:testing` |
| Image version | `testing-44.20260730` |
| Image digest | `sha256:aa812015beae33d8d5a092529c0e55f0fc53c044561e67e35e0191751bda51cd` |
| Kernel | `7.1.5-ogc2.1.fc44.x86_64` |
| InputPlumber | `0.78.0-1.fc44`, active as a root system service |
| OGUI package | `0.46.0-3.fc44` |
| PowerStation | `0.8.1-1.fc44`, active as a root system service |
| SteamOS Manager PowerStation | `0~20260727.git1a6e985-1.fc44`, active |
| HHD | Not part of Bazzite 44; no installed package or active service |

### Target firmware inventory

A second read-only capture at `2026-07-30T20:02:52Z` used DMI sysfs, the bound `hid-lenovo-go` attributes, and `fwupdmgr get-devices --json`. It did not request an update or write a device attribute.

| Target component | Current version | Additional identity | Linux evidence |
|---|---|---|---|
| System BIOS | `N3CN40WW`; release `1.40`; dated 2025-09-04 | `fwupd` raw version `0x00000040` | DMI and `fwupd` |
| Embedded controller | `1.40` | No separate update device reported | DMI `ec_firmware_release` |
| Main controller/transmitter | `260422a` | Product `760115`; protocol `30000`; hardware `20000` | `hid-lenovo-go` root and `tx_dongle` attributes; `fwupd` reports parent version `260422A` |
| Left controller | `260310a` | Product `750100`; protocol `30000`; hardware `101a0` | `hid-lenovo-go` left-handle attributes; `fwupd` reports `260310A` |
| Right controller | `260310a` | Product `750100`; protocol `30000`; hardware `101a0` | `hid-lenovo-go` right-handle attributes; `fwupd` reports `260310A` |
| Ryzen Z1 Extreme CPU microcode | `0x0a70410a` | CPUID family 19, model 74, stepping 1 | `fwupd` CPU inventory |
| AMD secure processor | `00.2d.00.83` | Bootloader also `00.2d.00.83` | `fwupd` PSP inventory |
| AMD system management unit | `76.93.0` | APU program 0 | `fwupd` SMU inventory |
| AMD GPU firmware identity | `1` | `AMD_PHOENIX_GENERIC` | `fwupd` reports only this numeric value |

These controls do not expose an independent firmware version in the reviewed Linux interfaces:

- fan control and battery charging use system firmware interfaces; the record has only the system BIOS and EC releases;
- controller lighting, vibration, touchpad, handle gyro, and handle calibration are functions of the controller devices above;
- the center IMU has no separate firmware-version attribute;
- the internal display panel and audio devices have no firmware version in the current `fwupd` inventory.

Legion Space also reports `RxVersion` and `DllVersion`. The Linux main-controller and `tx_dongle` values are identical, but this record does not claim that `260422a` is exactly the Windows `RxVersion` without a field-level trace. `DllVersion` is a Windows software-library version, not hardware firmware.

The system had two OGUI processes. One used the packaged binary. One used an OGUI update binary from user data. The running update binary version still needs a direct check.

### Battery result

The battery exposes:

```text
/sys/class/power_supply/BATT/charge_control_end_threshold
/sys/class/power_supply/BATT/charge_behaviour
```

Observed values:

```text
charge_control_end_threshold: 80
charge_behaviour: [auto] inhibit-charge
```

Both files have root-owned `0644` permissions. The test did not write either file.

#### Conclusion

The current kernel gives this project a direct, standard power-supply interface for the 80% threshold. This is preferable to a raw Lenovo ACPI call. An active test must still confirm enable, disable, readback, behavior above 80%, reboot persistence, and external-change behavior.

### Fan and thermal result

Loaded modules include the Lenovo Other Mode and capability-data modules.

The kernel reported:

```text
fan reporting/tuning is unsupported on this device
```

No fan or PWM controls appeared in hwmon. The Lenovo firmware-attribute class exposed only these power-limit controls:

- `ppt_cpu_cl`;
- `ppt_pl1_spl`;
- `ppt_pl2_sppt`;
- `ppt_pl3_fppt`.

The system has two platform-profile devices:

- `amd-pmf`: `low-power`, `balanced`, and `performance`;
- the Lenovo thermal-profile interface: `low-power`, `balanced`, `performance`, and `custom`.

The Lenovo profile was `custom` during the test. This remains the separate `SetSmartFanMode` owner. Later Windows disassembly and project-owner testing showed that original-Go `SetFanMode` is independent and uses separate fan-profile state and preset tables.

#### Conclusion

The current mainline-style sysfs interfaces do not expose Legion Space Full Speed, Custom curve, or separate fan-profile preset-table controls. Later evidence identified Quiet, Balanced, and Performance as `SetFanMode` values `2`, `3`, and `4`, not Smart Fan values.

### Controller baseline

The live controller uses Lenovo vendor ID `0x17ef` and current XInput product ID `0x61eb`. The `hid-lenovo-go` driver is loaded and bound.

Observed controller firmware data:

| Part | Firmware | Product | Protocol | Hardware |
|---|---|---|---|---|
| Left handle | `260310a` | `750100` | `30000` | generation 1, version `101a0` |
| Right handle | `260310a` | `750100` | `30000` | generation 1, version `101a0` |
| Transmitter/dongle | `260422a` | `760115` | `30000` | `20000` |

The driver exposes separate left and right controls for:

- joystick calibration;
- trigger calibration;
- gyro calibration;
- calibration status;
- IMU enable;
- IMU bypass;
- controller reset;
- sleep and rumble settings.

Calibration command files are root-only write files. Their index files accept `start` and `stop`. All six calibration status files reported `unknown`. The test did not start calibration.

Observed IMU flags:

```text
left imu_enabled: true
left imu_bypass_enabled: false
right imu_enabled: false
right imu_bypass_enabled: false
```

The reviewed upstream driver has a suspected right-side IMU attribute error. Therefore, the observed right `false` value is not yet accepted as the physical sensor state.

### Gyro and InputPlumber result

InputPlumber owns the active Legion Go composite device. Its live composite reports these six motion capabilities:

```text
Gyroscope:Center
Gyroscope:Left
Gyroscope:Right
Accelerometer:Center
Accelerometer:Left
Accelerometer:Right
```

This confirms that the current stack recognizes all three requested gyro locations.

The active source paths are:

- one center IIO gyro source;
- one Lenovo controller hidraw source that supplies left and right controller motion.

The center IIO gyro reports:

```text
name: gyro_3d
angular-velocity sample rate: 200 Hz
angular-velocity scale: 0.000174532
```

InputPlumber currently filters all center, left, and right gyro and accelerometer events from the composite output. Its active target gamepad is a `deck-uhid` Valve Steam Deck Controller. Its target capability set supports one generic `Gamepad:Gyro` and one generic `Gamepad:Accelerometer`.

#### Architecture consequence

Bazzite 44 replaced HHD with the OGUI and InputPlumber stack. InputPlumber already parses center, left, and right motion data. It is the required owner for:

- selection of the main controller gyro;
- creation and removal of the three auxiliary motion-only devices;
- prevention of duplicate motion output.

The next research step is to inspect InputPlumber's current profile, event filtering, target-device creation, and DualSense target support. No second hidraw reader or virtualizer should be added.

### Problems and cautions

- A controller mode transition occurred during boot between product IDs `0x61ed` and `0x61eb`. Hotplug and mode-change tests are required.
- One boot-time controller query returned USB protocol error `-71` before the controller returned to `0x61eb`.
- The kernel says Lenovo fan reporting and tuning are unsupported on this device.
- The current kernel source and live right IMU state need comparison before right-side writes.
- The `testing` image tag is mutable. The digest in this record is the test identity.

### Result

**Pass for read-only baseline collection.**

The device, software stack, battery threshold interface, three gyro capabilities, and separate calibration paths are confirmed. Fan-only control remains the largest interface gap. No active feature is Verified yet.

## Test Record: HID Step 1 No-Write and KUnit

### Scope

This record covers the initial failure, root-cause correction, necessity audit,
exact-kernel compilation, focused KUnit execution, read-only reply correlation,
and stock-owner recovery. It does not cover calibration Start or Stop.

### Target

- DMI: `LENOVO`, `83E1`, `Legion Go 8APU1`
- Kernel: `7.1.5-ogc2.1.fc44.x86_64`
- Controller: `17ef:61eb`, left generation `1`, right generation `1`
- Stock module SHA-256:
  `bfc0e88318b532f444bc97727db532bf8f55f208b9cb4201816ec2e5c0bcd113`
- Lifecycle-tested audited owner SHA-256:
  `be649d280de57511b332e1905aead7415b18845feac8d9ab2383f9f69c8d9f7a`
- Final audited owner source SHA-256:
  `97ab3931ef65e30a273cf9ab9b04bc6571aeeb891aaa34f2748751721c0d72ec`
- Final standalone KUnit module SHA-256:
  `80a0236b04bfe38aa62762cec5a22902ee66d8e0e672054815b6c134697007a3`
- Extracted production-region SHA-256:
  `4a7c0c4d2757fba8a986a87c632c3b8656a50ee2783262d965199c50b1755dd3`
- Focused test-source SHA-256:
  `52a593f55d65590e54509421f9bb7cbdaea06c6889e953a720bfb730efaa308a`

### Live reply correction

The first transient owner timed out on generation reads. Stock-owner dynamic
debug proved:

```text
Request: 05 00 02 06 03 00 ... 00
Reply:   04 00 02 06 03 01 ... 00
```

The request report ID is `0x05`. The immediate-reply report ID is `0x04`. The
corrected owner then returned generation `1` for both controllers. Reading the
six calibration attributes returned `start stop`. No attribute was written.

### Initial unload failure

The first external KUnit design imported symbols from a patched live owner.
The initial load lacked the KUnit dependency. The next load used KUnit with its
default disabled state. Recovery then crashed and shutdown blocked. The user
restored the device with a physical power cycle.

The persistent kernel log proved the cause:

```text
BUG: kernel NULL pointer dereference
mutex_lock
mcu_property_out
hid_go_brightness_set
led_classdev_unregister
hid_unregister_driver
```

The owner had stopped HID and cleared driver data before devm LED cleanup.
LED unregister called `brightness_set()` after the required configuration
pointer was gone.

The final owner explicitly unregisters the devm LED before HID stop and
driver-data removal. It takes the command mutex before shutdown, so no command
can arm or send after shutdown starts.

### Necessity audit

The earlier five-patch design added a private header, KUnit-visible exports,
in-tree KUnit configuration, test-driven send/wait callbacks, raw diagnostic
state, and 12 overlapping tests.

The audit reduced it to three production patches that change only
`drivers/hid/hid-lenovo-go.c`. The final series has:

- no private test ABI;
- no production KUnit export;
- no Kconfig or Makefile change;
- no new kernel log message;
- no test-driven callback table;
- no unreachable `-EBUSY` branch;
- four focused test cases.

Firmware rejection and short HID writes now use `-EIO`, consistent with the
existing driver. Timeout remains `-ETIMEDOUT`. Interrupted waits and negative
HID write errors propagate unchanged.

### Static and build checks

All three final patches:

- apply cleanly to base `8ba098e6b6ff0db8edf28528d1552be261af30d4`;
- pass strict `checkpatch.pl` with zero errors, warnings, and checks;
- compile independently with `-Werror` against the running kernel build
  interface.

The only build notices were the target's known `pahole` version and missing
`vmlinux` BTF notices.

### Standalone KUnit

The final test module extracts the private command types and pure helpers from
the applied owner source. It appends the focused test source in one test-only
translation unit. It does not register or replace a HID owner.

Metadata checks proved:

- dependency: `kunit` only;
- HID and USB aliases: none;
- hardware registration symbols: none;
- vermagic: exact running kernel.

Result:

```text
# hid-lenovo-go: pass:4 fail:0 skip:0 total:4
# Totals: pass:4 fail:0 skip:0 total:4
ok 1 hid-lenovo-go
result=pass
```

The cases cover output-packet field order, exact and first-reply ownership,
wait-result cleanup, and shutdown. The runner unloaded both test modules and
confirmed that the original HID driver hash and binding map did not change.

### Final no-write lifecycle

The final audited owner completed this sequence:

1. Record the original HID driver, fan mode, battery limit, and binding map.
2. Stop InputPlumber.
3. Unload the original HID driver.
4. Load and bind the audited driver.
5. Read generation `1` from both controllers.
6. Unload the audited driver within 20 seconds.
7. Restore the original HID driver and binding map.
8. Restart InputPlumber.

The final prior and restored binding map was:

```text
0003:17EF:61EB.000A hid-multitouch
0003:17EF:61EB.000B hid-lenovo-go
0003:17EF:61EB.000C hid-lenovo-go
```

No kernel BUG, Oops, null dereference, protection fault, or hung-task message
occurred. No reboot was requested. The test preserved the pre-test fan mode
and battery limit. At the final post-check, fan mode was `full-speed`, battery
limit was `80`, InputPlumber was active, and no KUnit test module remained.
The lifecycle test did not request or change the fan mode.

### Result

- Necessity audit: **Pass for the current three-patch scope**
- Per-commit strict style: **Pass**
- Per-commit exact-kernel build: **Pass**
- Standalone real KUnit: **Pass, 4/4**
- Corrected read-only reply correlation: **Pass**
- Initial unload: **Fail; root cause proved**
- Final audited unload and exact stock restoration: **Pass**
- Calibration Start or Stop: **Not run**

This was the gate status at the end of this test. Later results in this document supersede it.

## Test Record: HID Full-Tree Build, Packaging, and Repeated Lifecycle

### Scope

This record covers the exact OGC source-tree build, out-of-tree package build,
install/update/uninstall behavior, and three consecutive no-write driver
replacement cycles. It does not cover physical controller disconnect,
suspend/resume, or calibration writes.

### Exact source-tree build

The target package reports source RPM
`kernel-core-7.1.5-ogc2.1.fc44.src.rpm`. The matching public sources are:

- OGC Linux release: `v7.1.5-ogc2`, commit
  `e5f0343e484d49258c70e9c128570cb93195ce21`;
- OGC package tag: `v7.1.5-ogc2`, commit
  `2686bd8936c416e62e994540e92e0666531d9cea`;
- downloaded source archive SHA-256:
  `b1b7bad037093aba0ef73ee060afb5b8669331f16b768df2fd8c0a8d7d109fd7`.

The OGC source contains the expected base driver SHA-256:

```text
a91a4458b576fdcd52e85ebfbb4aef019cdc538c2cfbc666d91db1dbe8cd8432
```

All three audited patches applied in order. The result was byte-identical to
the reviewed source:

```text
97ab3931ef65e30a273cf9ab9b04bc6571aeeb891aaa34f2748751721c0d72ec
```

The build used the installed kernel configuration and
`EXTRAVERSION=-ogc2.1.fc44.x86_64`. The resulting kernel release was exactly:

```text
7.1.5-ogc2.1.fc44.x86_64
```

`prepare`, `modules_prepare`, and the in-tree `hid-lenovo-go.ko` build passed
with `W=1` and `KCFLAGS=-Werror`. Module metadata reported the exact vermagic,
name `hid_lenovo_go`, and dependency `led-class-multicolor`.

The host lacks the build-time Rust and `pahole` tools used for unrelated target
options. `olddefconfig` disabled those unrelated options. The HID driver is C
and compiled with the target symbol table. This limitation does not change the
reviewed HID source or its module dependencies.

### Packaging design

The source is stored separately in `drivers/hid-lenovo-go/`. Bazzite packaging
is stored in `packaging/hid-lenovo-go/`.

The package does not write to `/usr/lib/modules`. It:

- installs immutable release directories under `/usr/local/lib`;
- changes an atomic `current` symlink only while the service is inactive;
- saves the exact stock module, SHA-256, build-ID note, and binding map;
- compares the loaded build-ID before removal;
- restores only the saved interface owners;
- gives the saved stock module the SELinux module-file type;
- uses 20-second bounded removal with a five-second kill bound;
- preserves recovery state after any incomplete restore;
- stops and restores InputPlumber outside the ordered systemd unit;
- does not request a reboot.

Three supervised script-review passes found and corrected:

1. an InputPlumber/systemd ordering deadlock;
2. missing post-removal recovery;
3. an update race against the stock module;
4. non-transactional release replacement;
5. incomplete-state deletion risks;
6. signal paths that bypassed recovery;
7. a saved project-path restriction that rejected the active immutable
   release;
8. missing SELinux labeling on the saved stock copy;
9. InputPlumber start-rate exhaustion during rapid repeated tests;
10. a missing installed uninstaller.

### Live repeated lifecycle

The final test ran three consecutive cycles:

1. Stop InputPlumber.
2. Verify and remove the stock driver.
3. Load the packaged project driver by absolute path.
4. Restore the exact prior HID binding map.
5. Read generation `1` from both controllers.
6. Restore InputPlumber.
7. Stop InputPlumber.
8. Verify and remove the project driver.
9. Load the exact saved stock driver.
10. Restore the exact prior HID binding map and InputPlumber.

The exact map before and after every transition was:

```text
0003:17EF:61EB.000E hid-multitouch
0003:17EF:61EB.000F hid-lenovo-go
0003:17EF:61EB.0010 hid-lenovo-go
```

Final successful run:

```text
stock_sha256=bfc0e88318b532f444bc97727db532bf8f55f208b9cb4201816ec2e5c0bcd113
project_sha256=d4d66c72d0aff8abf0320c8ba8c2586d0d37bebf01e936abe68391ff990b1fa5
fan_mode=full-speed
battery_limit=80
result=pass
```

The module hash contains the external build path in debug data. The source hash
is the stable identity. Kernel logs contained normal generic-HID and Lenovo-HID
rebinding messages only. They contained no BUG, Oops, null dereference,
protection fault, hung task, or use-after-free message.

The final uninstall test disabled and removed the service and all project HID
files. The unchanged stock driver, exact binding map, active InputPlumber,
Full Speed fan mode, and 80% battery limit remained. No KUnit or project HID
module remained loaded.

### Result

- Exact complete OGC source-tree build: **Pass**
- Exact-kernel package build: **Pass**
- Install and immutable update: **Pass**
- Repeated project/stock lifecycle: **Pass, 3/3**
- Exact binding restoration: **Pass**
- InputPlumber restoration: **Pass**
- Uninstall and stock-only final state: **Pass**
- Physical disconnect: **Not run**
- Suspend/resume: **Not run**
- Calibration Start or Stop: **Not run**

This was the gate status at the end of this test. The later OGC4 record shows
that physical disconnect, suspend, resume, and automatic clean boot pass. The
project service remains disabled after testing while calibration writes remain
blocked.

## Test Record: HID RGB Ownership, Disconnect, Suspend, and Boot

### Scope

This record covers the correction and validation of two live kernel-driver
failures:

1. the RGB `enabled` LED attribute treated an LED class device as a HID
   device and caused a null-pointer Oops during automatic boot;
2. physical controller detach blocked USB removal in `kernfs_drain` while
   LED child devres removed the RGB attribute group during LED unregister.

The tests used read-only RGB and generation requests. They sent no calibration
Start or Stop command.

### Corrected source

The four-patch series applies to Linux base
`8ba098e6b6ff0db8edf28528d1552be261af30d4`. Patch 4:

- splits the common feature operation from its HID-device sysfs wrapper;
- recovers configuration state from the LED class device for RGB `enabled`;
- gives the driver explicit ownership of the RGB attribute group;
- removes that group before LED unregister while the LED child and
  configuration state remain valid;
- removes the group on the delayed-work scheduling failure path.

It adds no state field, production test export, Kconfig entry, build rule, or
kernel message. Final source SHA-256:

```text
e57c15692c7459b017686e832485c14e276cf88ffc3f1d8c47d18b46a1c37193
```

An independent review found no blocker or required correction. The final
patch changes 59 lines by addition and 15 lines by deletion. Each line is
required for callback typing, shared feature behavior, explicit group
ownership, or symmetric cleanup.

### Static and build validation

Target kernel:

```text
7.1.5-ogc4.1.fc44.x86_64
```

The exact OGC archive and base driver SHA-256 values were:

```text
archive  a774ddfae05b2f2632aa8e243c0aa9e4c849e0d78655d71f8cccbb28ad637f8f
base     a91a4458b576fdcd52e85ebfbb4aef019cdc538c2cfbc666d91db1dbe8cd8432
```

All four patches applied cleanly. `git diff --check` passed. Strict
`checkpatch.pl --no-tree --strict` reported zero errors, warnings, and checks
for each patch.

The final driver passed:

- external build with `-Werror`;
- complete OGC source-tree build with `W=1`, `KCFLAGS=-Werror`, and exact
  release `7.1.5-ogc4.1.fc44.x86_64`;
- standalone KUnit build and execution.

Build identities:

```text
package module    ae3d71ca06267e30a197d6b8f5538237699c061c724b26e83b71ff717f09e384
full-tree module  87d336d821694780bec388d867b686ece5e54881c814962129027972c3739b1e
KUnit module      194bd96b3a1ec608292ae59afbc20e391a58d31b322f806618a3cd18b759a7ac
```

KUnit passed four of four transport cases. These tests do not replace the
hardware driver and do not add a production ABI. A dedicated kernel unit test
for LED sysfs device typing would require test-only exports or a large LED and
sysfs mock. The smaller sufficient regression test is the compiled typed
wrapper plus the live read and teardown tests below.

### Live RGB regression test

The packaged project driver loaded under supervision. One hundred consecutive
reads of:

```text
/sys/class/leds/go:rgb:joystick_rings/enabled
```

returned `false`. InputPlumber remained active. No Oops, null-pointer fault,
protection fault, or hung-task message occurred. The driver then unloaded and
restored the exact stock module and binding map.

Kernel-log SHA-256:

```text
a4855883e836c64bef4c5040764b522672043aecc24467c9e34fff120d08198b
```

### Physical disconnect without a command reader

With the project driver active, the left controller was detached for at least
10 seconds and attached again. The complete controller USB device changed:

```text
0x61eb -> 0x61ed -> 0x61eb
```

Each USB disconnect completed. The controller re-enumerated in less than one
second. No task remained in D state. No kernel fault or hung-task message
occurred. InputPlumber remained active. Package deactivation restored the
three exact stock bindings.

Evidence SHA-256 values:

```text
monitor  4998d6b90cef6e7631d5439ac7089f51231d6f1fa7134ff4302b2da621ce4547
kernel   c03d4106537b9d9f296c9474a323dc362c3b6438bf613f6ee719d557b27bd9a8
```

### Physical disconnect with a bounded reader

One bounded process read RGB `enabled` repeatedly while the same detach and
attach cycle ran. This intentionally exercised sysfs removal while an
attribute operation could be active.

At removal, reads returned `ENODEV`, an absent path, or one 125 ms transport
timeout. No read reached its two-second process bound. Reads resumed after
both `0x61ed` and `0x61eb` enumeration. No task remained in D state after the
test. No kernel fault or hung-task message occurred.

Evidence SHA-256 values:

```text
monitor  96d7b50707945d3c4cf30dfe31a66056174c1bd9e28cc6e644c6075ffc525f7c
reader   d1d213f98cf5a755557b38eec016a4d00af6126b0c0c2f48cd81ea314e80d79a
kernel   eef7fcf90da251557df5ae39d0270dca829ecd5c6987bdf1f84edc6d74857417
```

### Suspend and resume

The project driver was active during one `s2idle` cycle. The system suspended,
resumed, re-enumerated the controller, kept InputPlumber active, and returned
`false` from RGB `enabled` after resume. No task remained in D state. No
kernel fault or hung-task message occurred. Package deactivation restored the
stock driver and binding map.

Evidence SHA-256 values:

```text
test    3753c7a3fa640358f662fd39e84c2d6ed7a1835c3fffee305c2f40c3d6f7f2a5
kernel  99f3efebb7c9328ca9068df24e795da9e08e343bb3668977d8d2818596d912e9
```

### Automatic clean boot

The service was enabled for one user-initiated clean restart. New boot ID:

```text
e8261041-3df2-415e-bb04-94595118d1cf
```

The service loaded the exact packaged module and verified its build-ID note.
InputPlumber became active. RGB `enabled` returned `false`. The controller
interfaces were present and the kernel log contained no Oops, null-pointer
fault, protection fault, hung task, use-after-free, panic, or RCU stall.

Compressed current-boot kernel-log SHA-256:

```text
d94ca45d8c9f21bef45f1113cfd718fd0409815f355b685214df2ef8387ef329
```

The separate experimental fan service failed in this boot. That failure is
outside this HID test and remains a fan-driver validation item.

### Final state

After evidence capture, the package restored:

- stock module SHA-256
  `91924c67a480a5954783f367d452ab25895aa3d547a0d24254a30fb1ab49b190`;
- three `hid-lenovo-go` stock bindings;
- active InputPlumber;
- an inactive and disabled project HID service;
- no persistent D-state task;
- no current-boot kernel fault.

### Result

- RGB LED-device sysfs ownership regression: **Pass**
- RGB group teardown and probe cleanup review: **Pass**
- Exact external and complete-source-tree builds: **Pass**
- Strict style: **Pass**
- Standalone transport KUnit: **Pass, 4/4**
- Physical disconnect without a command reader: **Pass**
- Physical disconnect with a bounded reader: **Pass**
- Suspend and resume: **Pass**
- Automatic clean boot: **Pass**
- Exact stock rollback and InputPlumber recovery: **Pass**
- Calibration Start or Stop: **Not run**

## Test Record: HID Calibration Transport

### Scope

This record covers the first controlled calibration write, the reply-deadline correction, bounded left- and right-trigger tests, and the first left-joystick attempt. It does not prove final calibration completion or persistence.

### Target

- Host: DMI `LENOVO`, `83E1`, `Legion Go 8APU1`
- Image: `bazzite-deck-gnome:testing`, deployment `testing-44.20260801`
- Kernel: `7.1.5-ogc4.1.fc44.x86_64`
- Controller: `17ef:61eb`, left and right generation `1`
- Initial project module SHA-256: `ae3d71ca06267e30a197d6b8f5538237699c061c724b26e83b71ff717f09e384`
- Patch 5 project module SHA-256: `0dcec3ebb217677694acef80551f5b05e8437ae70f559bad509eeb0b35f1c880`
- Stock module SHA-256: `91924c67a480a5954783f367d452ab25895aa3d547a0d24254a30fb1ab49b190`

The loaded build ID matched the immutable project module before the write.
InputPlumber was active. The project driver had no current kernel fault or
persistent D-state task.

### Initial left-trigger sequence

The test used the left-trigger sysfs attribute only. Each write had a two-second
process bound. The driver has its own shorter command-reply deadline.

1. Send `stop` while no calibration was active.
2. Require the idle Stop write to return success before Start.
3. Schedule another `stop` 250 ms after Start begins.
4. Send `start` and record its result separately.
5. Do not press or move the trigger.
6. Stop after this one case and restore the stock driver.

### Result

The idle Stop write returned success in approximately 10 ms. The Start write
returned a sysfs `Connection timed out` error after approximately 55 ms. The
scheduled Stop write returned success approximately 269 ms after Start began.
All calibration status files remained `unknown`.

The user observed no controller LED change during the sequence.

The scheduled Stop success is not proof that firmware accepted that Stop. Start
and Stop use the same report ID, group, command, sub-command, and device
correlation tuple. The firmware reply has no sequence or action token. A late
Start reply can therefore satisfy a later Stop waiter. The earlier idle Stop is
not subject to this specific ambiguity.

The test sent no joystick or gyro calibration command. It sent no right-side
calibration command. Testing stopped after the first Start timeout.

### Patch 5 correction

Copied Lenovo code uses a 500 ms command-result deadline for calibration. Patch
5 adds eight lines and changes one line. It keeps the existing 50 ms deadline
for all non-calibration commands and selects 500 ms only for MCU trigger,
joystick, and gyro calibration commands. It adds no state, retry, helper,
callback, export, log message, or test path.

Patch 5 validation results:

- All five patches apply to the exact base and produce source SHA-256
  `e232b899fb03d89bd48b59c23d2117d5650942ef9ffe8c494df0be9c94476e8c`.
- `git diff --check` passes.
- Strict checkpatch reports zero errors, warnings, and checks for all five
  patches.
- The exact Bazzite testing external module builds with `W=1` and
  `KCFLAGS=-Werror`.
- The complete OGC4 source builds the targeted module with `W=1`,
  `KCFLAGS=-Werror`, exact release `7.1.5-ogc4.1.fc44.x86_64`, and module
  SHA-256 `85afec528f11649bbf1bdd764a18fc287db649264b4245aeea334fac018dcf8c`.
- Standalone KUnit passes 4/4 and leaves the original HID driver and bindings unchanged.
- A no-write project/stock lifecycle reads generation `1` on both sides and
  RGB `false`, then restores stock and InputPlumber without a kernel fault.

A direct in-tree single-`.ko` final link could not use the packaged target
symbol table because the source archive has no `vmlinux.o`. Building all HID
modules with `-Werror` reached an unrelated existing unused-variable warning in
`hid-asus-ally.c`. The targeted complete-source `M=drivers/hid
hid-lenovo-go.ko` build uses the target `Module.symvers` and passes. These build
method failures did not load a module or access hardware.

### Patch 5 controlled result

The corrected test again used only the left trigger. It enabled existing
dynamic-debug transport messages for this bounded sequence.

- Idle Stop returned success in approximately 8 ms.
- Start returned success in approximately 11 ms.
- Stop sent 750 ms after Start began returned success in approximately 7 ms.
- The firmware returned exact zero-result replies for each request:

```text
Stop:  05 00 0a 04 03 02 ... -> 04 00 0a 04 03 00 ...
Start: 05 00 0a 04 03 01 ... -> 04 00 0a 04 03 00 ...
Stop:  05 00 0a 04 03 02 ... -> 04 00 0a 04 03 00 ...
```

The Start reply completed before the later Stop request was armed. This result
is not subject to the prior late-Start-reply ambiguity. The user observed blue
calibration lights around the left joystick. The status file stayed `unknown`,
as expected for Step 1. No final-completion claim was made.

### Right-trigger controlled result

The next bounded case used only the right-trigger attribute. The exact project
module and generation `1` gate were confirmed before the write.

- Idle Stop returned success in approximately 7 ms.
- Start returned success in approximately 10 ms.
- Stop sent 750 ms after Start began returned success in approximately 7 ms.
- The firmware returned exact zero-result replies for each request:

```text
Stop:  05 00 0a 04 04 02 ... -> 04 00 0a 04 04 00 ...
Start: 05 00 0a 04 04 01 ... -> 04 00 0a 04 04 00 ...
Stop:  05 00 0a 04 04 02 ... -> 04 00 0a 04 04 00 ...
```

The Start reply completed before the later Stop request was armed. The user
observed blue calibration lights on the right side. The status file stayed
`unknown`. No detach or reconnect was required. Existing dynamic debug was
disabled after the bounded capture.

### Left-joystick controlled result

The next bounded case used only the left-joystick attribute.

- Idle Stop returned an exact zero-result reply in approximately 7 ms.
- Start returned `Connection timed out` after approximately 512 ms.
- No matching reply arrived during the 500 ms driver deadline.
- The user observed a brief calibration-light flash.
- The Stop sent 750 ms after Start began returned a zero-result reply in
  approximately 11 ms.

```text
Stop:  05 00 0c 04 03 02 ... -> 04 00 0c 04 03 00 ...
Start: 05 00 0c 04 03 01 ... -> no reply before deadline
Stop:  05 00 0c 04 03 02 ... -> 04 00 0c 04 03 00 ...
```

The later reply cannot prove Stop acceptance because Start and Stop have the
same reply tuple and firmware supplies no action or sequence token. The flash
suggests that firmware could have accepted Start without returning its
immediate reply. The test did not retry in that controller session and restored
the stock driver.

The user physically detached and reconnected the left controller. It
re-enumerated from HID instance `.0016` to `.0025`. Generation `1`,
InputPlumber, and kernel health passed before one controlled retry. The retry
produced the same result:

- Idle Stop received an exact zero-result reply in approximately 7 ms.
- Start received no reply and timed out after approximately 511 ms.
- Stop sent 750 ms after Start began received a zero-result reply in
  approximately 7 ms, but remained ambiguous.

The repeat on a new physical HID instance rules out a stale reply from the first
controller session. It proves a repeatable missing immediate reply for this
left-joystick Start path. No further joystick or gyro Start was sent. The stock
driver was restored. Another physical left-controller detach and reconnect is
required before future calibration work.

### Asynchronous transport correction

The 500 ms calibration deadline was rejected as application policy. The kernel
must remain a hardware interface. Revised Patch 5 sends one trigger, joystick,
or gyro calibration output report and returns the HID submission result. It
does not arm a calibration reply waiter, apply a calibration deadline, or
retry. Synchronous commands that require a reply retain the kernel driver's
existing 50 ms bound.

Static validation of the revised source passed:

- exact five-patch application and source reproduction;
- strict `checkpatch.pl --no-tree --strict` with zero findings;
- external module build against the target kernel with `W=1 KCFLAGS=-Werror`;
- standalone KUnit, 4/4.

The revised source SHA-256 is
`47e0bbd68f99c40cec6f22cb590a0c3ab3fdb7383f259ecdfc62e2e3b1fff1b4`.
The external module SHA-256 is
`9b5e9f1a3aa0411dc8fcb95e8856627ff5e98c1463b34740c6b479205b2433f4`.
The immutable package is installed but inactive. A retained complete-source
temporary tree lacked `vmlinux.o`, so its single-module MODPOST could not run.
That failed build did not load code or access hardware.

### Asynchronous left-joystick result

The user physically detached and reconnected the left controller again. Its
interfaces re-enumerated as `.002D` through `.002F`. InputPlumber was active,
the stock module was loaded, and the kernel log had no fault before testing.

The revised module first passed one no-write activation and exact stock
rollback. The controlled left-joystick sequence then produced:

- idle Stop: success in approximately 7 ms;
- Start: success in approximately 5 ms;
- later Stop: success in approximately 7 ms;
- exactly three dynamic-debug output reports: Stop, Start, Stop;
- calibration status: `unknown`;
- visible calibration light, as observed by the user.

The loaded module build ID exactly matched the packaged project build ID. No
calibration write timed out, and the kernel sent no retry. The package wrapper
restored the stock module and binding map. InputPlumber returned active, and
the project service returned disabled and inactive. The kernel log had no BUG,
Oops, panic, hung-task report, RCU stall, or protection fault. One sampled
D-state kworker was transient and was absent from the other bounded samples.

This result proves one-report submission and visible firmware reaction. It does
not by itself prove final joystick calibration completion, persistence, or
status-event mapping.

### Linux completion mapping

A subsequent controlled test opened the configuration interface hidraw node
before Start. The kernel sent exactly one left-joystick Start report:

```text
05 00 0c 04 03 01 00 ...
```

The user rotated the left joystick fully twice and released it to center. The
calibration light was visible. Linux captured these two 64-byte reports:

```text
Immediate:  04 00 0c 04 03 00 00 ...
Completion: 04 00 a0 02 03 02 01 00 00 ...
```

The completion report arrived approximately 5.37 seconds after the immediate
report. Its fields are device `3` for left, module `2` for joystick, result `1`
for success, and little-endian error `0x0000`. This proves that the Windows
handler buffer starts its raw Linux report at the previously traced offset
`0x19`. No Stop or retry was sent because the success report ended the
operation.

The package wrapper restored the stock driver. InputPlumber was active, the
project service was disabled and inactive, five bounded D-state samples were
clear, and the kernel log had no fault. This test proves successful completion
and the Linux raw-event mapping. It does not yet prove persistence, failure,
cancellation, or disconnect behavior.

### Completion parser validation

Patch 6 decodes only the exact 64-byte completion shape. It validates device,
module, and Boolean result, maps result to the existing status text, exposes the
raw little-endian 16-bit firmware error, and notifies both sysfs attributes. It
adds no calibration wait, deadline, retry, or workflow state.

Final static results:

- exact six-patch application and source reproduction;
- strict checkpatch with zero errors, warnings, or checks;
- external build against the target kernel with `W=1 KCFLAGS=-Werror`;
- standalone KUnit 7/7 after removal of one redundant decoder-length check.

Final source SHA-256 is
`53d58bf388725764169e460d2db55be7afe76bc2a6e9c9dae6564d43650e15e0`.
Final external module SHA-256 is
`aeb08e10bb78205a688488f7a4dde2b99a56dc1cf383de8a1c0420b5dc9d7c3a`.
All six error attributes first returned `0x0000` during no-write validation.

A second full left-joystick calibration validated the integrated parser:

- initial status `unknown` and error `0x0000`;
- one Start submission in approximately 12 ms;
- one status notification with `success` and `0x0000`;
- final status `success` and error `0x0000`;
- matching raw completion `04 00 a0 02 03 02 01 00 00 ...`;
- no Stop and no retry.

The package wrapper restored stock and InputPlumber. The project service was
disabled and inactive, five D-state samples were clear, and the kernel log had
no fault.

### Recovery and final state

The package wrapper restored the exact stock module and HID binding map.
InputPlumber returned active. The project service returned disabled and
inactive. The battery remained in 80% Long Life mode. The experimental fan
driver remained unavailable, as recorded before this calibration work.

No kernel BUG, Oops, panic, hung-task report, RCU stall, or persistent D-state
task was present after recovery. No reboot was requested.

### Decision

Immediate firmware reports differ by calibration command. Trigger Start
returned one on each side. Left-joystick Start did not return one in two
physical controller sessions, although firmware reacted visibly. Therefore, a
calibration sysfs write cannot use one synchronous acknowledgment contract.

The kernel sends one calibration report and reports only HID submission success
or failure. Firmware acknowledgment and final completion remain asynchronous.
The kernel does not implement retries or calibration deadlines. The revised
path passes report submission, successful left-joystick completion, status
notification, and zero-error readback. Keep automatic loading disabled until
persistence, failure, cancellation, and disconnect behavior pass.

## Test Record: Final HID Activation

### Scope

This record covers the final Original Legion Go HID module build,
KUnit run, package update, stock rollback, final activation, and clean boot on
the target system. It used safe status reads and did not send calibration or
reset commands.

### Build and tests

- Kernel: `7.1.5-ogc4.1.fc44.x86_64`
- Reviewed source SHA-256: `95903e6b4a0f3bec8437d2200ca3b71183f840a13590b0b157e8bc5a0b22c45c`
- Installed module SHA-256: `53ba7141b26db8df1379661fd2b22318a02c3ea43088942ec22f046a8d09fb91`
- Immutable release: `d157cb30cc679934918182d3b94d6df4de95087d7f2c55a2dd0530e132e967dc`
- External build: pass with `W=1 KCFLAGS=-Werror`
- Standalone KUnit: pass, 7/7

The build reported that target `vmlinux` was unavailable for BTF generation.
This did not affect module compilation or loading.

### Lifecycle and boot

The package installed with automatic loading disabled. The controlled sequence
then passed:

1. Activate the project module.
2. Confirm InputPlumber and both controller-generation reads.
3. Read all six calibration error attributes.
4. Deactivate and restore the stock module.
5. Reactivate the project module.
6. Enable the service.
7. Perform one clean reboot.
8. Confirm the loaded module build ID and current-boot kernel health.

Final state:

- HID service: enabled and active
- InputPlumber: active
- Left generation: `1`
- Right generation: `1`
- Three matched HID interfaces: owned by `hid-lenovo-go`
- Fan service: disabled and inactive
- Current-boot kernel fault scan: clear

### Result

**Pass.** The final Original Legion Go HID module is installed and loads
automatically. Stock rollback passed before final enablement.

## Final Fan Activation

The installed immutable fan release `16d2f7b7473ac44a83199f83aed27e9d53e101a152eff4d6ef28fa3cd120f2b9` completed a controlled `s2idle` suspend and automatic RTC resume. The module build ID, baseline curve `44 44 55 60 71 87 100 100 100 100`, and Full Speed state `0` remained unchanged. RPM was temporarily `0` immediately after resume and recovered to `2878` within the bounded 30-second check. The helper, HID service, and InputPlumber were available after resume. Controlled deactivation removed the module and cleared recovery state.

The fan service was then activated, enabled, and tested through a clean boot. After boot, the helper returned RPM `4520`, Full Speed `false`, and the unchanged baseline curve. A later plugin-update boot returned RPM `5272` with the same state. The fan and HID build IDs matched their installed releases, InputPlumber was active, and both current-boot kernel fault scans were clear.

**Result: Pass.** The final fan service is enabled and active.

## OGUI 0.7.10 Kernel Interface Update

The controller backend now reads all six asynchronous calibration error attributes in addition to result and action-list attributes. It accepts the kernel action text `start stop` while it continues to reject unsafe text. Backend tests pass 47/47. The installed controller helper SHA-256 is `8661f66c98256e64273d92ca44e67e5981c16dc65b844a18c6b7917d3ecf3103`.

The plugin now shows independent Left and Right hardware generations and formats each calibration result, raw firmware error, and available action list. Fan status continues to use only RPM, independent Full Speed, and the complete curve. The installed plugin ZIP is version `0.7.10`, SHA-256 `a59c157d5a190772c3e83f702973edc528804377b23bd91e7a1dd2dc2c9e72f7`. OGUI initialized the plugin after reboot without a script or parse error. Live helper status returned all six errors as `0x0000` and all six action lists as `start stop`.

The release ZIP no longer includes project READMEs, Rust source, Cargo metadata, or Git placeholder files. Runtime installers, reviewed binary payloads, the fan source, licenses, and required lifecycle scripts remain.

**Result: Pass.** The plugin and controller helper handle the final HID and fan interfaces.

## OGUI 0.8.0 Control-First Interface

User feedback identified that the prior interface exposed too many diagnostic rows and raw states such as `unknown`, `unavailable`, action lists, paths, and firmware errors. Version `0.8.0` replaces that layout with three user sections: Battery, Cooling, and Controllers. It uses a charge toggle, a fan-mode dropdown, an independent Full Speed toggle, two button-layout and calibration controls, short hardware summaries, and a custom fan editor that stays closed until requested. Inactive calibration results and technical InputPlumber inventory do not appear in the normal view.

A connected controller battery exposed Linux power-supply type `Battery` and caused the old charge helper to reject the system because it found two battery-class devices. The corrected helper selects exactly one battery that also exposes `charge_control_end_threshold`. It still rejects zero or multiple charge-limit batteries. Rust tests pass 47/47. The Linux x86-64 helper SHA-256 is `86a2f267aae68dfe4eee10c2c8d0eea5c2b7b4f951931fb4654727e0f07da9ac`. Live read-only status now returns Long Life mode and threshold `80` while the controller battery is connected.

An isolated OGUI runtime loaded the release archive, parsed the new menu, added it to the scene tree, and completed menu initialization without a plugin script error. The installed archive is version `0.8.0`, SHA-256 `974a38d0e6f43d9b51ee26b4ecdecdb9c183250f6efb1b84df77814d71fef35b`. The active OGUI process was not interrupted, so final visual and gamepad-focus checks require the next normal OGUI restart.

**Result: Implemented.** Static, backend, package, isolated-runtime, and live read-only checks pass. Final on-screen review remains.

## Kernel Update Revalidation and OGUI 0.9.0

After the user installed the next Bazzite update and restarted, the running kernel changed from OGC4 to `7.1.5-ogc5.1.fc44.x86_64`. OGUI loaded plugin `0.8.0` without a plugin script or parse error. Battery status remained Long Life at `80`, and InputPlumber remained active.

Both enabled project driver services failed safely because their immutable releases contained modules only for the prior kernel. The HID service reported that no module exists for OGC5. The fan service reported the same condition. The stock OGC5 `hid-lenovo-go` module bound the controller, while the fan helper correctly reported unavailable. The current-boot kernel scan showed no project-driver fault.

Version `0.9.0` changes the installer model. The release contains reviewed HID and fan source, build files, lifecycle packaging, and no `.ko` file. A package-extracted dry run built both modules as the unprivileged user with `W=1 KCFLAGS=-Werror` against the exact OGC5 kernel-devel tree. Both modules reported OGC5 vermagic. The dry run then stopped at the expected administrator-consent boundary because no interactive terminal was supplied. The new root orchestration preserves the prior enabled state, installs immutable exact-kernel releases, and activates only services that were enabled before the update. Full privileged installation remains pending user consent.

Before a calibration write, the controller helper now checks the selected side and control for all four required kernel attributes: the command file, readable status, readable firmware error, and the action-list file that contains the requested `start` or `stop` literal. Earlier driver revisions could expose a writable command file but could not report final asynchronous completion or its firmware error. The stock OGC5 driver has command, status, and `start stop` action-list attributes, but it has no calibration-error attributes. The helper therefore rejects calibration on that partial interface instead of starting an operation that the UI cannot track completely. This check does not change the calibration protocol or add another firmware write. Backend tests pass 48/48. The HID driver clears the selected prior result only after it accepts a new Start transport request and restores it if transport submission fails. The exact OGC5 HID build passes `W=1 KCFLAGS=-Werror`; its source SHA-256 is `16c2e2507878bbf5d252b0308fdaf1b95fe3a36438cc49030dbac8c59e6095bc` and test-build module SHA-256 is `3ab53a2cd9fd395baac93169d6db1a4f3e093c46e502575a18b477b2d8fbe181`.

The plugin now provides six separate calibration actions: Left and Right joystick, trigger, and gyro. Each action sends the applicable Start command, shows only its required physical steps, polls asynchronous completion, translates documented firmware failures, and exposes Stop as cancellation while active. The installed but not yet loaded archive is version `0.9.0`, SHA-256 `93dc9559b277641ceb485d7aa8cbc75b2faffa2b01ff591ed0373a96b67327e8`. An isolated OGUI runtime parsed and initialized the new menu without a plugin error.

### Standard LED route

Read-only live inspection found `go:rgb:joystick_rings`, and InputPlumber discovered it. The Legion Go profile did not match the LED source. The active virtual target was `deck-uhid`, not DualSense. InputPlumber 0.78 also classified a DualSense color report as `NotImplemented`, so no physical LED source could receive it.

The investigation showed that this feature requires an InputPlumber source or profile change. InputPlumber changes are outside the current project scope. The prototype was discarded, and no InputPlumber code, profile, binary, or live configuration change is retained. Standard controller LED integration is a deferred TODO.

**Result: Repair required.** Version 0.9.0 is installed in the plugin archive. OGC5 kernel modules are not yet active.

### First OGC5 restart and controller-path recovery

The next restart loaded and initialized plugin 0.9.0. The enabled project HID service failed before any module replacement because no OGC5 project module existed. The stock `hid-lenovo-go` driver remained loaded and owned all three controller HID interfaces. InputPlumber stayed active, attached the required hidraw and center-IIO sources, and created its `deck-uhid` gamepad target. Steam recorded the Legion Go controller.

At 09:53:46, the OGUI activation chord changed the composite runtime `InterceptMode` from `Pass` to `Always`. Physical button events continued, but InputPlumber cleared the target state and routed input to OGUI instead of Steam. An initial attempt to force `Pass` while OGUI was open removed OGUI controller input and was incorrect. The mode was restored to `Always` so the user could exit normally.

After exit, the mode incorrectly remained `Always`. Restoring `Pass` did not make Steam list the stale virtual target. A controlled InputPlumber restart released and recreated the target as a new `deck-uhid` device. Steam opened controller index 0, InputPlumber returned to `Pass`, all three physical interfaces remained on the stock HID driver, and the user confirmed that Steam controller input worked. The temporary credential wrapper was removed immediately.

**Result: Recovered.** The failed project HID service did not remove the stock controller. InputPlumber needed one restart after the OGUI interception and stale-target sequence. OGUI interception lifecycle remains a separate defect to reproduce before release.

## OGC5 HID diff necessity audit

The exact comparison uses OGC5 `hid-lenovo-go.c` SHA-256 `a91a4458b576fdcd52e85ebfbb4aef019cdc538c2cfbc666d91db1dbe8cd8432`. The project file has 824 added and 342 removed lines, with a net increase of 482 lines.

A follow-up scope check found that the live Original Go has three HID interfaces but only one configuration interface. Left and Right are firmware targets behind that one interface; they are not separate `hid_go_cfg` instances. PID or controller-mode changes re-enumerate the same controller instead of using concurrent configuration devices. The fixed LED class name also prevents the current per-device conversion from supplying complete multi-device support. Thus, converting approximately 197 global references is defensible as a general upstream architecture correction, but current product evidence does not prove that it is necessary. The minimal project driver must not retain that churn unless a smaller proved lifecycle fix cannot work.

The audit found changes that require correction:

- Keep the structurally correct Right reset selector because upstream already exposes the reset attribute and currently misroutes Right to Left. Do not expose factory reset in the plugin until a controlled test proves that the selected controller resets and returns to a usable input state. “Recovery” means post-reset re-enumeration and input availability, not undoing a factory reset.
- `hid_go_cmd_wants()` duplicates the locked match later done by `hid_go_cmd_consume()`. The split check can become stale and changes unsolicited-report handling. Use one ownership decision after decoding.
- Replace the local reduced `hid-ids.h` with the exact OGC5 upstream file. This was completed; both files now have SHA-256 `019fbf86d67dda1282f9445b5c0650fa40ecb9cb99fb9bec8ffe422cf8d7cc8a`, so the header content diff is zero.
- The repository volume does not preserve requested POSIX mode changes. Normalize kernel source and header modes in release staging so C and header files are not executable.
- The driver README records an obsolete source hash.

Rebuild the project source from exact OGC5 and apply only proved transport, calibration, bounded-input, selector, and RGB-lifecycle changes. Use the smallest per-probe context required by those fixes. Do not perform a complete state conversion only for theoretical multiple-device support.

**Result: Changes required.** Do not build or install the current project HID source.

### 2026-08-04 minimal reconstruction correction

The replacement source starts from exact OGC5 and does not retain the broad per-device conversion. A second necessity audit removed the calibration spinlock, pending mask, saved result, and transport-failure rollback. It follows the upstream lock-free calibration-state model with `READ_ONCE()` and `WRITE_ONCE()`. Start clears the selected stale status and error before one HID submission. A submission error is returned directly and leaves the result `unknown`; an asynchronous completion writes the final status and firmware error.

The final source SHA-256 is `a30828a77c14187661b299fadedd7570180bb1813518e53dc949fcdd2de5b996`. Its exact OGC5 diff is 417 additions and 136 deletions. The exact-kernel strict build, strict checkpatch, and standalone KUnit 7/7 passed. No project driver was installed or activated during this audit.

### 2026-08-04 secondary OGC and Windows-correlation review

A second independent review checked the minimal source against exact OGC5, Linux HID rules, and the proved Windows dispatcher and completion gates. The parent removed the test-driven output-packet helper and its redundant KUnit case, restored upstream packet construction and its suspend comment, fixed configuration-probe publication cleanup, and fixed the reply-versus-timeout transition so completion is published while command state remains locked. A reply that wins the state lock now remains authoritative even when the bounded wait concurrently reports timeout.

The review retained five-field Linux ownership. Windows proves command and sub-command as its minimum immediate gate. Prior Linux live evidence also proves the input report ID, group, and selected device in the complete reply header, and exact matching prevents unrelated MCU, OS-mode, or opposite-device reports from owning a waiter. It still cannot distinguish a late identical reply because firmware has no sequence token.

The revised source SHA-256 is `1acd4c46858f8ccc63907d6a4831bc018d80b91aac7bb752cf4a05a0c7bf478c`. Its exact OGC5 diff is 390 additions and 131 deletions. Strict checkpatch and strict local cross-kernel builds passed. The standalone KUnit module builds six focused cases, including the reply-at-timeout state outcome. Exact OGC5 build and execution remain pending because the target became unreachable before the final run. No project driver was installed or activated.

### 2026-08-04 Lenovo driver-behavior correction

The complete KZ dispatcher proves that synchronous ownership uses command and sub-command at bytes `2..3`. It does not include the device byte. Input report ID, byte-1 route, packet size, and active-interface checks are framing and dispatch checks, not waiter-key fields. The supplemental legacy path uses the same command and route ownership pattern, but its serializer and completion framing remain separate.

The implementation now follows that boundary. It removes the five-field tuple and keeps the spinlock only for pending-command, result, and timeout arbitration. The reply winner remains authoritative when completion races the 50 ms timeout. Calibration still sends one report and does not use the synchronous waiter.

Removal no longer publishes an artificial command-shutdown state. It cancels setup work, removes and drains sysfs and LED command sources, drains the bounded command mutex, clears the active configuration pointer, and then stops HID. A later command fails with `-ENODEV`. This sequence also avoids unsynchronized pointer publication.

A final textual-churn audit restored unchanged OGC5 declarations, switch structure, timeout local, condition style, blank separators, return value, diagnostic formatting, and attribute ordering. It retained all required behavior changes. The revised source SHA-256 is `0a943b88a6fabf254338bbe302b82144be2bc4e68dd4fa9f66db64ba7f120211`. Its exact OGC5 diff is 318 additions and 81 deletions. This removes 122 changed lines from the former 390-addition and 131-deletion revision. Strict checkpatch passed with zero findings. A strict `W=1 KCFLAGS=-Werror` Fedora Rawhide driver build passed. The extracted five-case KUnit module built without HID or USB registration symbols or aliases. The target was unreachable, so exact OGC5 build and KUnit execution remain pending. No driver was installed or activated, and no hardware write occurred.

## Fan source reconstruction and component move — 2026-08-04

The complete fan component moved from `fan-driver/` to `drivers/lenovo-legion-wmi-fan/`. Backend build, installation, uninstallation, documentation, and export paths now use the new location. Runtime state names remain unchanged for installed-package compatibility.

The declared source base is the external `honjow/lenovo-legion-go-wmi-fan` commit `60365f1204aa97aaa0604c27197530c2474c90cd`. OGC has no copy of this standalone curve driver. Its separate thermal-profile component owns SmartFan and platform-profile methods `43..45`; this project does not use them. OGC `wmi-other.c` is the Linux reference for Other Mode transport and RPM, but it does not provide WMAB curve operations `5` and `6`.

The source was reconstructed from the declared base. Unchanged comments, formatting, declarations, and control flow remain where the contract permits. The remaining diff replaces the PWM and per-point policy ABI with one complete curve, adds Other Mode RPM and independent Full Speed, and adds host bounds, readback, mutation avoidance, removal exclusion, and dirty-state restoration.

Static BIOS evidence corrected the curve capability gate. WMAB belongs to Lenovo Fan Method WMI GUID `92549549-4BDE-4F06-AC04-CE8BF898DBAA`, not the thermal-profile GUID. Other Mode operations require GUID `DC2A8805-3A8C-41BA-A6F7-092E0089CD3B`. Both GUIDs and the exact three-field DMI match must be present before the module exposes controls.

The final source has 778 lines. Its declared base has 682 lines. The standard diff is 358 additions and 262 deletions. Final source SHA-256 is `fa10f3808c2e0118f88a8a5a48ef682ecca223cfc2ac06429926a912d2163ab0`.

Strict checkpatch passed with zero findings after mode normalization. Shell syntax passed for all moved and changed scripts. The five-case standalone KUnit module built with warnings treated as errors and contains no hardware-registration symbol. A complete build against generic Fedora 7.1 and 7.2 kernel-devel did not start compilation because those trees removed the deprecated `wmi_evaluate_method()` and `wmi_has_guid()` declarations that OGC5 retains. The exact OGC5 target was unreachable, so the required exact-kernel driver build and KUnit execution remain pending.

No module was installed or loaded. No service or hardware state changed. Do not install or activate this reconstructed fan source before the exact OGC5 checks pass.

### Fan source comment correction — 2026-08-04

A later source-only correction removes a stale claim that WMAB uses the thermal-profile GUID. It also identifies the 44 curve bytes as the required prefix of the full 88-byte response; the driver intentionally ignores the sensor-table suffix. Behavior did not change. Strict checkpatch still passes with zero findings. The corrected source has 779 lines, differs from the declared base by 362 additions and 265 deletions, and has SHA-256 `791d1f86432626b8d0d5f117603328d227c23bb99e33e7b87aff2c34fbe62d43`. Exact OGC5 build and execution remain pending.

### HID calibration device-switch alignment — 2026-08-05

The calibration-result reference helper now preserves OGC5’s outer `LEFT_CONTROLLER` and `RIGHT_CONTROLLER` switch structure, with the calibration module switch inside each device case. The helper still returns the status pointer, separate `u16` firmware-error pointer, sysfs group, and attribute names required by completion events, Start-state clearing, and error reads. Behavior and the asynchronous ABI did not change.

This alignment reduces the exact OGC5 total changed-line count from 399 to 395. The new diff is 328 additions and 67 deletions. Source SHA-256 is `d35c3c46b5f96905e5a126881a0974ffc17422ed52cb040ce49939728c6100a8`.

Strict checkpatch passed with zero findings. A Fedora Rawhide 7.2 build passed with `W=1 KCFLAGS=-Werror`; module SHA-256 was `ecb1d4f43bd5e890209538d6c499593bdd4706417d617397cc836c2ac74bcb91`. This is not the exact OGC5 target build. No module was installed or loaded, and no hardware state changed.

### HID calibration decoder command-report alignment — 2026-08-05

The calibration completion decoder now accepts the existing packed `struct command_report` instead of a raw byte pointer. The named fields preserve the same proved layout: `device_type` is the controller, `data[0]` is the module, `data[1]` is firmware success or failure, and `data[2..3]` is the little-endian firmware error. The decoder still validates report ID, route, command, subcommand, controller, module, and firmware result before it normalizes the result.

The standalone tests now construct the same command-report type. The extraction wrapper supplies that existing production layout. Strict checkpatch passed with zero findings. The exact OGC5 diff is 331 additions and 67 deletions. Source SHA-256 is `75c91bdc99297de6c3f291eb9083a6e60a9f2578fc339027f4d3e2015e79247b`.

Fedora Rawhide 7.2 builds passed for the full driver and five-case standalone KUnit module with warnings treated as errors. Module SHA-256 values were `fe48edbca9629d74e8381f09356639eb9a5d6cb560a8d4bf0539afee9f59e033` and `b33236f9a5fde3e5790e45d005cc28d50ea826fada73a47caef2f523d86900fb`. The test module has no HID or USB registration symbol. These builds do not use the target kernel. No module was installed or loaded, and no hardware state changed.

## Live Test Record — Post-update Game Session Diagnosis — 2026-08-08

### Scope

This test used read-only SSH inspection of boot history, service state, process state, journal records, kernel messages, coredump metadata, and memory state. It made no system, service, configuration, input, package, driver, or hardware change.

### Target state

The new deployment booted successfully on kernel `7.1.6-ogc5.1.fc44.x86_64`. The prior boot ended uncleanly. The new boot has no kernel panic, Oops, GPU reset, OOM event, failed system unit, or active swap use.

### Game-session result

The user game-session service remained active, but its OGUI LaunchManager logged one persistent orphan window per second. It also logged a stale child-process check and a failed text read once per minute.

The journal shows that a Helium AppImage launched through Steam created this orphan window immediately. The earlier session recorded two Helium crashes with `SIGBUS`. The current Helium application remains active through Steam, and OGUI continues to identify its window as an orphan.

Decky Loader plugins and a custom CSS theme were active during the test. They are possible additional variables. The records do not identify them as the direct cause.

### Conclusion

The evidence identifies the Helium Steam application and its orphan window as the primary current cause of the Game Mode and Desktop Mode hang. It does not identify an OGC kernel, AMDGPU, InputPlumber, project HID, or project fan fault.

### Correction — retained boot and session-manager review

Only two full boot journals remain. Boot accounting shows two earlier same-kernel boots without normal shutdown records, but it cannot supply their detailed logs.

The retained prior boot disproves the earlier primary-cause conclusion. The user-session `steamos-manager` process made two explicit root-manager requests. At 11:09:03 it requested `gnome.desktop`. Gamescope stopped and GNOME started. At 11:09:19 it requested `gamescope-session-ogui-steam.desktop`. GNOME stopped and a new Gamescope session started.

GNOME did not crash during its 16-second session. No kernel panic, GPU reset, OOM event, or InputPlumber fault preceded the return to Game Mode. Helium still created an orphan window, but that fact does not explain the explicit session-manager request.

The current session-manager package is `steamos-manager-powerstation-0~20260807.gitb689b20-4.fc44`. It owns the immediate unwanted return. The retained logs do not identify its triggering event or rule. Two user `bwrap` processes also end with `SIGSYS` on each retained boot. Their owner and relation to this session change are unknown.

### Complete HID OGC5 minimality and performance audit — 2026-08-08

The complete project source was compared line by line with exact OGC5 source SHA-256 `a91a4458b576fdcd52e85ebfbb4aef019cdc538c2cfbc666d91db1dbe8cd8432`. Every diff hunk was classified for required behavior, safety, testability, or unnecessary churn. The audit retained command/subcommand reply ownership, one-report asynchronous calibration, six separate firmware-error values, selector corrections, explicit RGB teardown, delayed-work draining, probe rollback, and removal exclusion.

The audit restored the upstream `hid_go_device_status_event` boundary. It adds `hdev` only so notifications use the raw-event device rather than rereading a global pointer during teardown. The decoder still consumes the existing `command_report` and remains independently testable. The audit also removed a temporary calibration Boolean, an unnecessary reset parse-error branch, and an unreachable motor-index default that was not required by any registered attribute. It moved the active-configuration pointer test before USB endpoint lookup, so reports from other interfaces leave the path earlier.

The final exact OGC5 diff is 326 additions and 67 deletions, or 393 changed lines. This is six fewer changed lines than the 318-addition/81-deletion revision and five fewer than the immediately prior 331-addition/67-deletion revision. Final source SHA-256 is `1b4fdb2fc09837ba92873baffc1de3338db82a28c0a3679bf5371b4fbbfe5227`.

The performance audit found no measurable hot-path regression. Normal reports add only a report-ID comparison and an active-device pointer comparison. They perform no allocation, lock, wait, notification, or added logging. Nonconfiguration reports can now bypass endpoint lookup. The spinlock runs only for low-rate decoded configuration replies. Calibration avoids the inherited 50 ms synchronous wait. Notifications occur only on Start and valid completion. The existing one-allocation-per-output-command and `cfg_mutex` serialization remain unchanged.

Built with the same Fedora Rawhide 7.2 configuration, the current raw-event function was 1496 bytes versus 1556 bytes in OGC5. `mcu_property_out()` was 652 bytes versus 432 bytes because it now implements bounded writes, asynchronous calibration, correlated completion, interruption, timeout, and teardown errors. The complete module text/data/bss total was 38,205 bytes versus 36,809 bytes, a 1,396-byte increase. This static size increase is not on the normal input path and is not performance-significant.

Strict checkpatch passed with zero findings. Fedora Rawhide 7.2 full-driver and five-case standalone KUnit builds passed with `W=1 KCFLAGS=-Werror`. Module SHA-256 values were `800978cad2a3f646fe3fd262149bdba2ced242ad798ccdc9ab1a2c96db48d8f9` and `b33236f9a5fde3e5790e45d005cc28d50ea826fada73a47caef2f523d86900fb`. The test module has no HID or USB registration symbol.

The protocol still has no sequence token, so a late identical command/subcommand reply remains inherently ambiguous. Device is intentionally not part of Lenovo's proved waiter key. Calibration state remains lock-free by design and does not speculate about active or cancellation state. These are protocol boundaries, not performance defects.

This is not the exact OGC5 target build or a live latency measurement. No module was installed or loaded, and no hardware state changed.

### HID calibration command/action order correction — 2026-08-08

A focused selector review found that the restored OGC5 calibration macro passed the action subcommand before the calibration command. This made `calibrate_config_store()` receive trigger as `0x04/0x0a`, joystick as `0x04/0x0c`, and gyro as `0x06/0x0e`. Its command-to-module switch rejected each request before USB submission.

The macro now passes `_scmd` before `_name.index`. The resulting fixed request prefixes are trigger `05 00 0a 04`, joystick `05 00 0c 04`, and gyro `05 00 0e 06` for both controller sides. No other driver behavior changed.

The standalone KUnit build now checks the production macro argument order before extraction. A negative fixture with the arguments reversed stopped with the expected error. Strict checkpatch passed with zero findings. The full Fedora Rawhide 7.2 build passed with `W=1 KCFLAGS=-Werror`, and the updated standalone KUnit build passed. Source SHA-256 is `a7443ede054c02c34c94a30b58909c69259be43b8d92042b554becc4969e187c`. The exact OGC5 diff is 328 additions and 69 deletions. The full module SHA-256 is `25f586e678381471ba2757d37f95f2db88c4056320651227f328e96d059f48f0`; the unchanged KUnit module SHA-256 is `b33236f9a5fde3e5790e45d005cc28d50ea826fada73a47caef2f523d86900fb`.

No module was installed or loaded. Build and live-device checks remain pending.

### HID calibration selector clarity reduction — 2026-08-08

The calibration reference helper now assigns the status pointer, error pointer, status attribute name, and error attribute name together inside each left/right module case. The separate final module switch was removed. This duplicates the three name pairs across controller sides, but each accepted path now shows its complete state mapping in one place and evaluates only one module switch.

The source is five lines shorter. The exact OGC5 diff is 323 additions and 69 deletions, or 392 changed lines. In the same Rawhide build, text decreased by 64 bytes, data decreased by 8 bytes, and total text/data/bss decreased from 38,141 to 38,069 bytes. Source SHA-256 is `7406f5e45e52b599df36f3e7c280d25f4238a23f4c32a5794d99e5f7af2befaf`.

Strict checkpatch passed with zero findings. The Fedora Rawhide 7.2 full-driver build passed with `W=1 KCFLAGS=-Werror`. The standalone KUnit build passed, including the calibration command/action order gate. Full module SHA-256 is `ceada3e22c019e0f5f57a0b7ae747ce30f0cc9475b661d647e86fa237c8c77c0`; KUnit module SHA-256 remains `b33236f9a5fde3e5790e45d005cc28d50ea826fada73a47caef2f523d86900fb`. No module was installed or loaded.

### HID calibration notification and selector reduction — 2026-08-08

The calibration path no longer calls `sysfs_notify()`. The plugin reads completion state once per second and does not hold or poll sysfs file descriptors. OGC5 also stores calibration status without notifying sysfs. The removed calls had no project consumer.

`hid_go_calibration_ref` now contains only the status and error pointers. The group and attribute-name strings were removed. `hid_go_device_status_event()` again uses the upstream one-argument boundary. Completion still validates the full report before it writes the separate status and firmware error values.

`device_status_show()` now uses the same reference helper instead of repeating the left/right/module selector. This removed 33 source lines from that function revision. The compiler had already optimized both forms to identical text/data/bss size. Relative to the prior complete source, all notification and selector reductions removed 57 source lines.

The exact OGC5 diff is 302 additions and 105 deletions, or 407 changed lines. The changed-line count increased because the shorter `device_status_show()` replaces a large unchanged OGC5 block. Source SHA-256 is `b34f71f9b42a8298fdf781534016cb8cd2e10891d563701f34c0b9479789b30c`.

Strict checkpatch passed with zero findings. The Fedora Rawhide 7.2 full-driver build passed with `W=1 KCFLAGS=-Werror`. The standalone KUnit build and calibration command/action order gate passed. Full module SHA-256 is `554e617986859a21866c618c5cdc94231d502080ef6006541f1a98fc7a3fd373`; KUnit module SHA-256 is `2b378a27be5d94c41fcffb9d0ec128f513185734e063d693fe37036f47fa389f`. No module was installed or loaded.

### Clean-room structural comparison and production serializer — 2026-08-08

An independent implementation was created from exact OGC5 source and the static Lenovo driver map only. It received no project source, patches, tests, history, memory, validation records, or conversation context. Its full source built with strict compiler flags, but its disconnected KUnit packet test did not compile and several transport and lifecycle choices were not suitable for integration.

The independent structure still supplied two useful results. It independently reduced `device_status_show()` to one shared selector, which supports the active reference-based reduction. It also separated packet construction from waiting and exposed a current DPI layout error. Lenovo's fixed DPI setter is `05 00 08 02 <dpi-u32le>`; the inherited generic five-byte header placed an extra device byte before the DPI value.

The active driver now uses one production `hid_go_build_output_report()` helper. It clears all 64 bytes, retains the generic five-byte header for existing routes, places DPI data at byte 4 only for `SET_DPI_CFG/FPS_MODE_DPI`, rejects an oversized payload, and rejects a nonzero length with no data pointer. `mcu_property_out()` remains responsible for serialization, removal exclusion, submission, asynchronous calibration, and synchronous waiting.

The standalone KUnit extraction now uses the production packet helper. A sixth case checks every left/right trigger, joystick, and gyro Start/Stop report as a complete 64-byte report and checks the complete fixed DPI report. The existing source gate still checks the generated calibration macro command/action order. This closes the test gap that allowed the DPI offset and earlier calibration macro regression.

The comparison rejected the independent owner lock, calibration lock, shutdown state, split reply dispatcher, broad OS-mode rewrite, broad value conversions, and nonauthoritative timeout handling. Those changes add state, alter inherited Linux ABI conversions, or weaken the proved reply-versus-timeout behavior. The Windows 500 ms normal deadline remains documented but was not adopted over OGC5's existing 50 ms Linux deadline without target evidence.

Strict checkpatch passed with zero findings for the full exact-OGC5 patch and test source. Fedora Rawhide 7.2 full-driver and six-case standalone KUnit builds passed with `W=1 KCFLAGS=-Werror` for the driver. Source SHA-256 is `fb2713e78731da155c2e3ba83a43b62b7081aec7dbfd0ff2f1e01e3f181d1aaa`; exact OGC5 diff is 328 additions and 112 deletions. Full module SHA-256 is `50557c7a2adad3ad733b167b5c38d2019cd46fc04e27f895fdd34bd180705eed`; KUnit module SHA-256 is `a21a623d7fedbfc1506ab87a5557ad607a226e4cdbf35c7f52871db1ae5bd455`. The full module text/data/bss total is 38,981 bytes, 48 bytes smaller than the independent implementation.

No module was installed or loaded. Build, KUnit execution, and live DPI readback remain pending.

### OpenGamingCollective master fan build and current HID checks — 2026-08-09

The device ran `bazzite-deck-gnome` testing version `testing-44.20260808` on kernel `7.1.6-ogc5.1.fc44.x86_64`. DMI reported `LENOVO`, `83E1`, and `Legion Go 8APU1`.

The fan source uses OpenGamingCollective `master` commit `9c37615c0efca8ec4c7d461ef7ae2f4806951ace`. Base hashes, complete source staging, and whitespace checks pass.

The first native build used a separate Fan Method source file. It passed with `W=1 KCFLAGS=-Werror`, but that source layout is obsolete and the result does not validate the merged owner.

The current repository stores only modified `wmi-other.c`. Fan Method curve support extends the existing `lenovo_wmi_other` driver through its WMI ID table. No unchanged upstream source, fan patch, new driver source, or helper-header file remains.

The complete merged `wmi-other.c` built externally against the installed `7.1.6-ogc5.1.fc44.x86_64` headers with `W=1 KCFLAGS=-Werror`. Only the source and four required headers were transferred. No upstream tree was transferred. Source SHA-256 was `4a5ab2343d1df05fd5a85087068a9183b0fae736f65ba9f53e96b8529de4ed62`; module SHA-256 was `2ebcc84c6ea9d427141c56c1e50ec8f462d265516d03c0ecf3da3aff4baaeec4`. Module aliases contained exactly the Other Mode and Fan Method GUIDs. The module was not loaded.

The merged `wmi-other.c` pure helpers were also extracted from production source and built against the same kernel. The standalone module SHA-256 was `9c21f17ed5bf9641db5521acefa0c030c03c9df2088148b8627db196a82363a6`. All six tests passed. The module had no WMI, platform, or ACPI registration symbol.

A later Spark review found that this revision accepted only the first 44 bytes of the proved 88-byte getter reply and emitted 52 bytes of the proved 64-byte setter payload. The current source corrects both contracts. It sends getter selectors `1,1`, validates both table counts, and emits all fixed setter bytes and zero tail bytes. Production-connected tests now check null and short replies, the second count, and the exact 64-byte payload. That framing revision used source SHA-256 `157df5f5e11d2981704127fa54cfd0f734ee394fcf4c908d3903e65e507e4954`. The later minimality review reduced the source to SHA-256 `751d356e5f544e44fe7ee3692cbc273a1114fc2400df5d6123848c210bd87dab` without changing the framing behavior. Local source and test checks pass. The target rebuild could not start because the device became unreachable. The module and KUnit hashes above predate this correction.

The current HID source SHA-256 was `3b6a9d3c998612adf82cf04b35ddfeeb5b5550c4042a89000cfe4bbe1cbce38e`. It built on the running kernel with `W=1 KCFLAGS=-Werror`. The driver module SHA-256 was `20ebc877c5a0750e4e6d5fe919bfc75fa04ca0a57fac287c0d5f3a26299eb48b`.

The HID standalone KUnit module SHA-256 was `5aaac28fb33f64adb10876e00b432a7df178b29ba6fc7f906cb6f94e762465e1`. All six tests passed. The runner confirmed the active HID owner module hash and all controller bindings remained unchanged.

No project module was installed or activated. The tests sent no hardware command. InputPlumber and both existing project services remained active.

The running tagged OGC kernel does not expose `charge_types`. It still uses the earlier battery interface. Native categorical battery validation therefore requires a kernel that contains the selected OGC `master` implementation.

The installed standalone fan service remains a conflict that must be removed before the in-tree fan implementation can run. At the end of this read-only check, its current state was Full Speed `1` and curve `44 44 55 60 71 87 100 100 100 100`. This work did not change that state.

### All-zero fan curve and restart test — 2026-08-09

The device ran kernel `7.1.7-ogc1.1.fc44.x86_64`. DMI matched the original Legion Go. The initial temperature was `51 °C`, Full Speed was `1`, RPM was `8522`, and the curve was `44 44 55 60 71 87 100 100 100 100`.

The complete merged module could not load externally because this kernel does not make its internal capability-data and firmware-attribute symbols available to an external replacement. That attempt sent no fan command and restored stock ownership.

A temporary route tester contained only the proved Fan Method curve, Other Mode Full Speed, and RPM calls. It matched both exact WMI GUIDs and the three exact DMI fields. Its SHA-256 was `ff2ac0e6d03c44ccd788a5c9cabc03f00105fb45deefb7a26a98a22b67cd342b`. A first discovery attempt sent no write because Linux WMI device names include numeric instance suffixes.

The controlled write then disabled Full Speed and submitted `0 0 0 0 0 0 0 0 0 0`. Exact curve readback passed. RPM changed as follows:

```text
second 1: 8522
second 2: 3062
second 3: 1045
second 4: 601
second 5: 0
seconds 6 through 10: 0
```

Temperature changed from `51 °C` to `55 °C` during the ten-second sample. Full Speed was then set to `1` and read back as `1`, but RPM remained `0`. This proves that Full Speed does not restart the fan while the all-zero curve remains active.

The recovery monitor was delayed by a command-input error. When it started, temperature had reached `82 °C`, RPM was still `0`, and Full Speed still read `1`. The test immediately restored the baseline curve and wrote Full Speed `1` again. RPM recovered to `6738` after two seconds at `84 °C`, then reached `8455` while temperature fell to `65 °C`.

The temporary module was unloaded and stock `lenovo_wmi_other` was restored. The final observed temperature was `52 °C`. Stock HID bindings and InputPlumber were active, and the kernel fault scan was clear. The last direct fan readback before unload was the baseline curve with Full Speed `1`. All temporary device files were removed.

Result: an all-zero curve stops the fan, but Full Speed alone does not recover it. Recovery requires a nonzero curve. Levels `0..43` remain blocked.

The same test exposed a userspace discovery defect: WMI device directories are `<GUID>-<instance>`, not bare GUIDs. The backend now requires exactly one numeric instance for each exact GUID. Backend tests pass 48/48.

### Full Speed curve-point selection test — 2026-08-09

A follow-up test checked whether Full Speed treats any nonzero curve point as a global enable. Initial state was `48 °C`, `8590 RPM`, Full Speed `1`, and the baseline curve.

With curve `1 1 1 1 1 1 1 1 1 1`, RPM stayed between `8556` and `8625` for eight seconds. This proves that a selected value of `1` is sufficient for full fan speed.

The test then used `0 0 0 0 0 0 0 0 0 1`. Only the `100 °C` point was nonzero. At `48..50 °C`, RPM changed from `8556` through `3823`, `1334`, and `551` to `0` after five seconds. It remained `0` through ten seconds. Full Speed readback remained `1` throughout.

This disproves the global “any point is nonzero” model. At the tested temperature, Full Speed uses the curve value selected for that temperature. Zero disables the fan, and `1` enables full speed.

The test restored the baseline curve and Full Speed `1`. RPM recovered to `6436` after two seconds. The temporary module was unloaded, stock `lenovo_wmi_other` was restored, and all temporary files were removed. Final temperature was `51 °C`; InputPlumber remained active and the kernel fault scan was clear.

### Low-temperature curve range build — 2026-08-09

The kernel transport now accepts nondecreasing values from zero through each model maximum. The Original-Go restricted backend permits `0..125` at 10–70 °C. Custom curves require at least `79` at 80–90 °C and `100` at 100 °C. The exact verified Quiet and Balanced tables remain accepted as exceptions.

Backend tests passed 48/48. The merged source SHA-256 is `e57779137929a6dec980121c85d2763123a33c85723eb53e5c7da3796a98d15e`. It built on kernel `7.1.7-ogc1.1.fc44.x86_64` with `W=1 KCFLAGS=-Werror`; module SHA-256 is `7993ff32d3158f67d150124a40d41750c8a38e01d307f9476c2f9c40996e62fd`.

The hardware-free KUnit module SHA-256 is `84fa462834d4184241a9fea851bf96faf61609e09ce0cc99f98c6d36b6b8735e`. All six tests passed. The merged driver was not loaded, and no hardware write occurred. Temporary build files were removed. Stock `lenovo_wmi_other` remained active at `49 °C`.

### Full-screen OGUI menu checks — 2026-08-09

Plugin `0.10.0` replaces the long settings card with one Open button. Open pushes a plugin-owned state onto OGUI's menu state machine. The full-screen control uses native OGUI tabs for Battery, Cooling, Controllers, and Calibration.

The normal full-screen focus count is one control on Battery, two on Cooling, one on Controllers, and two on Calibration. Custom cooling adds one temperature selector, one level slider, and Apply. Hidden, disabled, and read-only controls are removed from focus. Routine status refreshes preserve active focus.

GDScript parsing and lint checks passed for the launcher, plugin entry point, and full-screen menu. An isolated OGUI run loaded the plugin without a plugin parse error. A direct menu construction reached the native tab-header resource.

The installed isolated OGUI executable then crashed during its FirstBoot startup after reporting compile errors in its own launch-menu dependencies. The deferred Open test did not run before that crash. Full-screen state transition, LB/RB behavior, Back behavior, and final visual review remain pending in the normal OGUI session.

No package was deployed. The tests sent no hardware write. InputPlumber remained active, stock `lenovo_wmi_other` remained loaded, and the kernel fault scan stayed clear.

### Fan curve warm-reboot persistence — 2026-08-09

A temporary Fan Method-only module tested firmware persistence independently from plugin and production-driver lifecycle behavior. It required exact Original-Go DMI identity, bound only GUID `92549549-4BDE-4F06-AC04-CE8BF898DBAA`, used the complete method `5/6` framing, and intentionally made no remove-time restoration write. It built for kernel `7.1.7-ogc1.1.fc44.x86_64` with `W=1 KCFLAGS=-Werror`. Module SHA-256 was `73c6af4123b568aa68a5c8742dab3c1a7a78767f61c6400042792d32ff4d9068`.

The baseline curve was `44 44 55 60 71 87 100 100 100 100`. The test submitted the safe distinctive curve `101 101 101 101 101 101 101 101 101 101` and confirmed exact readback before reboot. After a warm reboot, a newly built copy of the same reader returned the exact all-`101` curve before any post-boot write.

Result: the device firmware retained the complete custom curve through this warm reboot. The observed product reset is not an unavoidable firmware reset. Plugin `0.9.0` does not save its Custom editor table. The production driver's dirty-remove rollback can also restore its probe curve during driver removal. Persistence policy must stay in restricted userspace; the kernel rollback must remain safe for unload and failure recovery.

The test restored and confirmed the exact baseline, unloaded the temporary module, and removed all test and state files. Final state was active InputPlumber, loaded stock `lenovo_wmi_other`, unbound Fan Method GUID, `52 °C`, and zero current-boot kernel faults.

### Transport-only fan driver build — 2026-08-09

The fan curve persistence result changed the owner boundary. `wmi-other.c` now exposes current firmware state and sends bounded, serialized transport requests. It no longer saves probe fan state, skips matching requests, performs policy readback, marks state dirty, or restores a curve or Full Speed setting during removal. The restricted helper remains the readback owner.

The updated `wmi-other.c` SHA-256 is `6b5b380214d0706c0832db860f2c3376b557bb4c6ea1af2aff5b538f995139f5`. Selected OGC source files and installed headers built the merged module on kernel `7.1.7-ogc1.1.fc44.x86_64` with `W=1 KCFLAGS=-Werror`. Module SHA-256 was `1e921bccfdd7e03fa67d0cb5bf463304fced31ea67a4e5e2bcc1a0436da96d1b`.

The obsolete write-decision test was removed because it no longer exercised production behavior. The hardware-free KUnit module SHA-256 was `a996e6113cf4ba650f1b0ffa0f18b5e34385ec18c3cd19c1b7f531adb7a10366`. All five remaining production-helper tests passed. The first load attempt correctly failed while KUnit core symbols were absent. A core load with testing disabled produced no tests. Reloading KUnit with `enable=1` produced the final five-test pass.

The merged hardware module was not loaded, and this work sent no fan command. All temporary files and test modules were removed. Final state was active InputPlumber, loaded stock `lenovo_wmi_other`, unbound Fan Method GUID, `46 °C`, and zero current-boot kernel faults.

### Integrated Lenovo WMI no-write replacement — 2026-08-09

A clean external build used only selected OGC source files and the installed headers for kernel `7.1.7-ogc1.1.fc44.x86_64`. It completed with `W=1 KCFLAGS=-Werror` and without unresolved-symbol build warnings. The `lenovo-wmi-tuning.ko` SHA-256 was `10cbfe6707e1e7a647482df5e7ab3c99e1b4af1b5e7a626549f2fecc8c0e98e1`.

The first no-write replacement script compared the WMI driver name with the module name. Both old and new drivers intentionally use `lenovo_wmi_other` as the driver name, so this assertion failed and the cleanup trap immediately restored stock. The corrected check used each driver's module owner.

The corrected cycle unloaded stock `lenovo_wmi_other`, loaded `lenovo_wmi_tuning`, and confirmed that the new module owned both exact WMI GUIDs. Read-only results were curve `44 44 55 60 71 87 100 100 100 100`, Full Speed `1`, `8625 RPM`, and charge type `Standard [Long_Life]`. It then unloaded the project module and restored the exact stock module, whose SHA-256 was `df98aae448f3480d0a9cb0372abb7ba68f502d803a3ecd0c08e54d2c7af1d269`.

No fan or battery write occurred. This removes the earlier external-load blocker for a clean module built against the running kernel's current symbol versions. Packaging and repeated lifecycle checks remain required before activation.

### Immutable WMI package and plugin deployment — 2026-08-09

Added running-kernel immutable packaging for the integrated `lenovo_wmi_tuning` module. The package records kernel release, source hash, module hash, lifecycle-script hash, vermagic, project build ID, and exact stock path, hash, and build ID. It keeps the stock file unchanged and uses root-only lock, active, saved-stock, and recovery state. Install stays disabled. Activation replaces stock only after exact checks. Deactivation restores the saved stock module without a fan write.

The final module source SHA-256 is `6b5b380214d0706c0832db860f2c3376b557bb4c6ea1af2aff5b538f995139f5`. Running-kernel module SHA-256 is `070366a1550f34dff68c8f1e86429847df0cb862e8f923995f88b89ea5c5366f`. Final immutable release ID is `646efd2dac5e3efd068db3e5050fb422aa5928736cf41cf47123f9502eb06a85`; lifecycle-package SHA-256 is `f336ce82420987bd9139935c5b9c84b2ba3e48286f3f5b1d4617e2db07dc7a9f`. The preserved stock module SHA-256 is `df98aae448f3480d0a9cb0372abb7ba68f502d803a3ecd0c08e54d2c7af1d269`.

Three explicit no-write activate/deactivate cycles passed. Each project activation returned curve `44 44 55 60 71 87 100 100 100 100` and Full Speed `1`. Each deactivation restored stock ownership with Fan Method unbound and no recovery marker. The package then passed enabled boot activation twice, including the final immutable release. The firmware curve remained exact.

The first cycle harness used the previously installed fan helper. That older binary did not support numeric WMI instance paths and returned unavailable after the module activated correctly. Current backend tests passed 48/48. The corrected fan helper SHA-256 is `89333a0726015c2ac241301a9ea83a6b83192ca1bef3e56470f6c043369613cc`; its read-only status succeeds through the integrated module.

Plugin `0.10.0` archive SHA-256 is `1a8c105d22dda4e802c18e93b19b15c85d890f2a2e966afda3b005f651176e08`. OGUI extracted and initialized it after the final reboot. No plugin script error was logged. The full-screen Open, tab, focus, and Back checks still require direct controller interaction.

Final live state: final WMI release enabled and active, InputPlumber active, OGUI plugin `0.10.0` initialized, firmware curve unchanged, Full Speed `1`, fan approximately `8625 RPM`, boot temperature `67 °C`, no recovery marker, and zero current-boot kernel faults.

### OGUI Open crash and focus correction — 2026-08-09

The first direct controller test could not move focus from plugin metadata to Open. OGUI created its plugin FocusGroup before `settings_launcher.gd` added the button in `_ready()`. The launcher now creates the button in `_init()`, before OGUI configures focus, and explicitly uses `FOCUS_ALL`.

A later pointer click reached Open. The plugin then called `set_anchors_and_offsets_preset()` on the full-screen Control before adding it to OGUI's scene tree. OGUI logged `Parameter "data.tree" is null` and immediately received SIGSEGV. Because OGUI owns the Gamescope session command, its exit tore down that session and killed Steam. Steam did not produce the initiating crash.

The plugin now hides and connects the full-screen Control, adds it to OGUI's `main` node, and only then applies the full-rectangle layout preset. GDScript lint passed. Plugin `0.10.1` archive SHA-256 is `3aa51370390738e29134e6b208cbe26630391c446a9f0338c88b2c70801443d8`.

OGUI and Steam restarted, OGUI initialized `0.10.1` without a plugin script error, InputPlumber remained active, and the WMI service remained active. A second direct controller selection is required to confirm the fix. The current boot retains the one recorded OGUI userspace segfault from the failed `0.10.0` test.

The second direct test confirmed that controller focus reached the Open `CardButton`. It also disproved the first crash correction as complete. `settings_menu.gd` created its internal `VBoxContainer` and called `set_anchors_and_offsets_preset()` before adding that container to the scene tree. The same `data.tree` failure and OGUI SIGSEGV occurred when the full-screen menu entered `_ready()`.

Plugin `0.10.2` adds the internal layout to the full-screen Control before it applies the layout preset. A static audit found no other pre-tree layout preset call in the plugin path. GDScript lint, archive structure, and whitespace checks passed. The production `0.10.2` archive SHA-256 is `0749146e57b7c2b6b5d385a582384b305f6c58ead73af7ef0eeb69e5a8c87360`. Steam, OGUI, InputPlumber, and the WMI service are active. Direct Open confirmation remains required.

A third direct test again focused Open and produced the same immediate `data.tree` failure and OGUI SIGSEGV. Thus, neither layout-order correction identified the initiating caller. Plugin `0.10.3` temporarily disabled the Open action while the session recovered. Archive SHA-256 was `e325479fa6be1cfe506e4e887166dae6352b49e3a0e90ded57eaacc8d586b72b`.

At the owner's direction, plugin `0.10.4` continues the existing full-screen path. The attached launcher now supplies its valid `SceneTree` with the Open signal; `plugin.gd` no longer calls `get_tree()` to locate OGUI's main node during this transition. The three Dropdown controls now enter the tree before `clear()` and `add_item()` use their `@onready` child controls. Open is enabled. GDScript lint, archive checks, and whitespace checks passed. Archive SHA-256 is `8b422e9c7dfdbd9b3e4df279e20d0afa549e8014a69d395c402262a0d0d47b5f`.

The `0.10.4` runtime test did not crash. It created the hidden menu, but OGUI logged `MenuStateMachine: Invalid NULL state pushed` for each Open activation. The plugin's `_ready()` callback had not initialized `fullscreen_state` in this lifecycle. Plugin `0.10.5` creates and connects that state from both the proven `get_settings_menu()` path and the Open path. The direct runtime test confirmed that Open enters the full-screen state in Gamescope without a native fault.

Plugin `0.11.0` adds an opaque full-screen background, removes descendant component internals from focus, repairs invalid focus after asynchronous control discovery, combines calibration with Controllers, and replaces the calibration dropdown and Start control with six direct calibration buttons. GDScript lint and archive checks passed. Archive SHA-256 is `c52c199cac4ee92ef0bb407213b499cc462f67771af5bb2e76c853b7b9daecd3`.

Battery diagnosis found a stale installed helper. It reports the obsolete `charge-limit battery` discovery failure while the live battery exposes `Standard [Long_Life]` at `charge_types`. The current helper was built on Linux x86-64 and passed all 48 backend tests. Its SHA-256 is `3b27fb1d6e1e25126cd8c5fa9ca9eb3273952cc126939a24f360216d0e6f9d0b`; read-only live status returned Long Life and 80%. Plugin `0.11.0` contains this helper payload. Administrator installation is still required to replace the stale root-owned helper.

Plugin `0.12.0` changes an existing but stale backend action to Update backend and adds Remove backend through a fixed one-shot Desktop Mode uninstaller. The 80% control remains disabled until Update installs the current root-owned helper. Cooling now places Full Speed above compact Quiet, Balanced, Performance, and Custom mode controls. All ten curves remain visible; preset curves are read-only and Custom is editable. Exact Quiet and Balanced exceptions remain accepted. A separate read-only timer updates fan RPM every five seconds. Controllers now shows connected generations, identifies Menu/View as a saved request because firmware has no readback, uses a Calibrate heading and compact button flow, and renames Repair to Install calibration support. The latter is required because the HID service is enabled but failed: its immutable release does not contain a module for the running kernel, and calibration error attributes are absent.

GDScript lint, Bash syntax, archive checks, and whitespace checks passed. Plugin `0.12.0` archive SHA-256 is `f53296ce9353cb2e572a83aeb5c1160e19505cbe79d4b10a6f5f23f198978ea9`. Steam, OGUI, InputPlumber, and the WMI service are active. No plugin parse or script error was found after initialization.

## Source installation and current-kernel lifecycle — 2026-08-11

The live Original Legion Go ran Bazzite testing with kernel
`7.1.8-ogc1.1.fc44.x86_64`. The test started after a kernel update. The old HID
and WMI services were enabled but could not start because they had no module for
the new kernel.

A clean public clone exposed three installation faults. The source instructions
did not list Cargo, Rust, Godot, or current kernel headers. Backend preflight
required `charge_types` before it installed the WMI module that provides that
file. A first backend installation also returned success while both project
driver services remained disabled. Versions 0.12.8 through 0.12.12 corrected
these faults and removed repository-only files from the plugin package.

The final source build used Rust 1.87 or newer and Godot 4.7.1. It built the
OGUI native extension, the three restricted helpers, and plugin 0.12.12. The
plugin ZIP passed archive checks and contained the required helper payloads,
driver sources, and packaging scripts. It excluded repository documents, Git
files, tests, and annotated diffs. OGUI's GUT editor plugin reported a missing
first-run editor configuration during import. Export still completed, and the
installed plugin initialized without a plugin script or parse error.

The backend installer built both kernel modules with warnings treated as
errors, requested administrator approval, installed the helpers and Polkit
rule, replaced the stock driver owners, and enabled both services on a first
installation. An update with both services enabled rebuilt, replaced, and
reactivated both modules. An update with both services disabled rebuilt both
modules and kept both services disabled. Polkit checks passed for all three
helpers.

Removal restored the stock `hid_lenovo_go` and `lenovo_wmi_other` modules,
removed both project services and all three helpers, and left InputPlumber
active. A fresh reinstall from that stock state enabled and activated both
project modules. The device then completed a clean reboot with the project HID
and WMI services, InputPlumber, and OGUI active.

The battery helper completed `80 → 100 → 80` with readback and left Long Life
at 80%. The fan helper enabled and disabled Full Speed with readback. RPM rose
from about 3,700 to 8,325 while Full Speed was active. The curve remained
`0 0 0 0 50 75 90 115 125 125` before, during, and after the test.

An RTC wake test completed suspend and resume. HID, WMI, InputPlumber, battery
state, Full Speed off, and the complete fan curve remained available after
resume. The final clean boot and all lifecycle tests had no kernel fault match.

Final live state: plugin 0.12.12 is installed and initialized. InputPlumber,
the project HID service, and the project WMI service are enabled and active.
Battery mode is Long Life at 80%. Full Speed is off. The firmware curve is
`0 0 0 0 50 75 90 115 125 125`.
