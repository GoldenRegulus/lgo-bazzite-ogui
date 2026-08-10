# Definition of Done

This file is the primary source for project scope and completion. Update it when the agreed scope changes.

## 1. Status rules

Use one status for each requirement:

- **Not researched:** No source-backed interface is known.
- **Researching:** Work is in progress, but key facts are not verified.
- **Blocked:** A named external dependency or missing device test prevents work.
- **Ready:** The interface, design, risks, and test method are known.
- **Source-backed:** The complete authoritative Lenovo path and owner implementation are proved, but target hardware is not available for live verification.
- **Implemented:** The code exists, but all acceptance evidence is not complete.
- **Verified:** All acceptance criteria pass on the target system.
- **Deferred:** The requirement is not in the current release, with a recorded reason.

A requirement is done only when it has **Verified** status. Record verification in the evidence table at the end of this file.

## 2. Product goal

Create an OGUI plugin for the original Lenovo Legion Go and Legion Go 2 that supplies all applicable in-scope Legion Space hardware controls on `bazzite-deck-gnome:testing`.

The hardware scope includes input control surfaces and a small set of controls exposed by each target's BIOS or firmware interfaces. This includes controller state indicators, calibration, selected fixed controller settings, native Steam/InputPlumber input integration, standard Steam/UHID LED integration, vibration and touchpad controls, fan control, battery charge mode, and power-button lighting states. Original host model `83E1` remains live-verified. Legion Go 2 support can be source-backed when the complete shipped Lenovo route, model selection, values, bounds, response handling, and owner interface are proved. Detachable-controller generation remains separate from host generation.

The current project does not change InputPlumber source, device profiles, or configuration. Features that require such a change remain deferred TODO items.

BIOS and controller firmware updates, device updates, and general display, audio, and graphics controls are outside scope. Version data can appear only in compatibility and test evidence needed to gate a control safely. The project excludes Lenovo accounts, stores, game downloads, web content, social features, Android emulation, and other content services. Legion Go S is excluded because SteamOS supports it natively. Other hardware is excluded.

The product must:

1. Use stable Linux kernel, sysfs, D-Bus, or supported daemon interfaces when they exist.
2. Keep privileged hardware access outside the OGUI user interface when practical.
3. Detect unsupported hardware and firmware before it permits writes.
4. Cooperate with the input and hardware services that Bazzite enables.
5. Keep safe firmware defaults when the plugin, daemon, controller, or user session fails.
6. Show the current hardware state, not only the last requested state.

## 3. Release gates

### BASE-01 — Target detection

**Status:** Researching

The software must identify supported Legion Go machine types and reject unsupported systems.

Acceptance criteria:

- [x] The support list records machine type, BIOS version, EC version, kernel, Bazzite image, OGUI version, and relevant daemon versions. See [Validation](wiki/Validation.md).
- [ ] An unsupported system gets a clear read-only or unavailable state.
- [ ] The controller owner detects left and right handle generation independently and gates generation-specific controls.
- [ ] A cross-generation controller claim records an identical serializer, packet, target selector, acknowledgment, result path, bounds, and errors.
- [ ] Each supported host generation has an exact DMI or equivalent authoritative machine gate before writes are enabled.
- [ ] Documentation labels each function as live-verified, source-backed, blocked, or unsupported for each host generation.
- [ ] A source-backed Legion Go 2 claim records the complete Lenovo model route, serializer or method call, values, bounds, response or readback, errors, and recovery behavior.
- [ ] No EC or firmware write occurs before target validation.

### BASE-02 — Interface ownership and conflict control

**Status:** Researching

The software must not race another service for fan, battery, gyro, or virtual-controller control.

Acceptance criteria:

- [ ] The wiki identifies the owner of each hardware interface.
- [ ] Startup detects incompatible owners or configurations.
- [ ] The user gets a specific conflict message and recovery instruction.
- [ ] Repeated start, stop, suspend, resume, logout, and controller reconnect tests pass.

### BASE-03 — Privilege boundary

**Status:** Researching

Privileged operations must use the smallest practical permission set.

Acceptance criteria:

- [ ] The OGUI process does not run as root.
- [ ] A documented service or policy controls each privileged operation.
- [ ] Inputs have allowlists, numeric bounds, and type checks.
- [ ] The design does not expose an unrestricted EC, file-write, or command-execution interface.

### BASE-04 — State, persistence, and recovery

**Status:** Researching

Acceptance criteria:

- [ ] The UI shows requested state and confirmed hardware state.
- [ ] Each setting documents whether it persists across plugin restart, user logout, reboot, suspend, BIOS update, and controller detach.
- [ ] Controller target or translation changes can return to the prior target without a reboot.
- [ ] A failed target change releases or restores the prior physical and virtual input path.
- [ ] Failed writes return a useful error and do not leave a partial unsafe state.
- [ ] The user can restore firmware or project defaults.
- [ ] Uninstall instructions restore changed system configuration.

### BASE-05 — Diagnostics and compatibility record

**Status:** Researching

Acceptance criteria:

- [ ] A diagnostic export removes personal data by default.
- [ ] Logs include component versions, detected capabilities, requested changes, confirmed results, and errors.
- [ ] Automated tests cover interface parsing, bounds, unavailable devices, and failures.
- [ ] A live-device test record exists for each supported release combination.

### BASE-06 — Plugin-first dependency rule

**Status:** Researching

The project must implement features in the OGUI plugin with existing supported interfaces when possible. Apply this order for each feature: prove that an external dependency change is necessary; use a released owner interface; search existing issues, pull requests, mailing-list patches, and downstream work; test or contribute to suitable work; create a project-owned implementation only when no suitable implementation exists. The project can retain ownership until a suitable external owner integrates equivalent support.

Acceptance criteria:

- [ ] InputPlumber, OGUI core, the kernel, and Bazzite remain unchanged unless a required feature cannot be implemented safely through their current interfaces.
- [ ] The project searches current owner work before it creates a dependency source change and records why existing work is not sufficient.
- [ ] The evidence record identifies all devices and capabilities matched by the changed code and proves shared behavior, adds a verified gate, excludes unverified devices, or blocks the change.
- [ ] A dependency change needs a controlled reproduction that identifies the dependency as the source of the problem.
- [ ] The wiki records why an OGUI plugin workaround is unsafe or insufficient.
- [ ] The dependency change is the smallest change that supplies the required interface or correction.
- [ ] Each dependency source change follows that upstream owner's source style, naming, architecture, documentation, tests, and contribution conventions.
- [ ] Source changes are separate by upstream owner. Owner code, project policy, and Bazzite packaging are separate layers.
- [ ] Owner-side interfaces use capability data and extensible match tables. Adding a later model or controller generation must normally add data or capabilities instead of replacing the architecture.
- [ ] Each project-owned hardware implementation has a long-term owner API, compatibility, lifecycle, and migration design. It is not only a local workaround for the current image.
- [ ] Each project-owned hardware implementation documents its protocol, capability gates, bounds, concurrency model, error handling, readback, suspend and resume behavior, installation, removal, rollback, and failure recovery.
- [ ] Owner source, tests, protocol evidence, and packaging are separate so a maintainer can review or integrate the implementation without plugin-specific policy.
- [ ] The plugin remains the user-facing product and contains all Legion-specific policy that does not belong in an existing owner.

### BASE-07 — Legion Space hardware parity

**Status:** Researching

The plugin must equal or safely exceed all Legion Space hardware controls that apply to the original Legion Go. Lenovo behavior is the required baseline, not the maximum. A superset must use verified owner interfaces, explicit bounds, confirmed readback, recovery behavior, and capability gates. An existing OGUI or Bazzite control can satisfy a feature when it has the same verified range, ownership, readback, persistence, and recovery behavior.

Acceptance criteria:

- [x] The wiki maps the current Legion Space hardware bridge methods, value domains, product gates, update flows, and error states.
- [x] These requirements map each original-model hardware feature to an existing Linux control, a required plugin control, a dependency change, or a documented hardware-specific block.
- [x] Each feature requirement separates the safe initial function from remaining parity work.
- [ ] Controller parity covers XInput, DInput, and FPS state, controller generation, native Steam/InputPlumber mapping behavior, Lenovo/Menu/View swap, DPI, standard LED integration, vibration, touchpad controls, sleep, calibration, and factory restore.
- [ ] BIOS-exposed control parity covers only charge optimization, fan modes and curves, fan RPM, and power-button lighting states.
- [ ] Each implemented mutation uses a typed, bounded owner interface with confirmed readback and recovery.
- [ ] The plugin excludes accounts, stores, downloads, web content, and other non-hardware Legion Space services.

## 4. Core features

### CTRL-01 — Controller state indicators

**Status:** Researching

The plugin shows owner-reported controller state without replacing Steam or InputPlumber controller management.

Acceptance criteria:

- [ ] The plugin shows XInput, DInput, and FPS state when the owner reports them.
- [ ] The plugin shows detected controller generation.
- [ ] Indicators update after mode change, controller re-enumeration, suspend, resume, and service restart.
- [ ] Stable identities are used. Event-device numbers are not identities.
- [ ] Unknown or unavailable state is not shown as a known controller mode.
- [ ] The plugin does not add connection, link, Bluetooth, or controller-battery indicators.

### BAT-01 — Global 80% charge-limit control

**Status:** Testing

The OGUI plugin must provide one global control for the firmware-supported battery modes. It must not store or apply this control through a per-game profile.

Acceptance criteria:

- [ ] The plugin has one clear control to enable 80% Long Life mode and restore 100% Standard mode.
- [ ] The control permits only the firmware-supported 80% and 100% states. It does not show an unconfirmed intermediate value.
- [ ] A restricted root-owned backend accepts only `status`, `enable`, and `disable`.
- [ ] `enable` writes and confirms 80. `disable` writes and confirms 100.
- [ ] The backend validates an exact supported host identity and its charge-mode capability before each operation. Original host `83E1` remains the live-verified path.
- [ ] The backend discovers exactly one battery by power-supply type. It does not depend on the name `BATT`.
- [ ] The plugin reads and shows actual hardware state after start, resume, write normalization, failed writes, and external change.
- [ ] The plugin explains expected behavior when charge is already above 80%.
- [ ] The control is global and independent of the active game and performance profile.
- [ ] State and persistence behavior are documented and tested.
- [ ] Unsupported firmware does not expose an enabled control and does not attempt a write.
- [ ] Backend installation requires explicit user action and never asks the plugin to collect an administrator password.

### FAN-01 — Fan-only modes

**Status:** Testing

The user can select Automatic, Quiet, Balanced, Performance, Full Speed, or Custom fan control. The plugin owns these labels and complete curves. The kernel and restricted helper expose only one complete curve, independent Full Speed, and RPM.

Acceptance criteria:

- [ ] Automatic submits the verified original-Go baseline curve `44 44 55 60 71 87 100 100 100 100`.
- [ ] Quiet submits Lenovo's value-`2` table `44 48 48 48 48 48 48 48 48 48`.
- [ ] Balanced submits Lenovo's value-`3` table `44 48 55 60 60 60 60 60 60 60`.
- [ ] Performance submits Lenovo's value-`4` table `44 48 55 60 71 79 87 87 100 100`.
- [x] Full Speed uses the verified independent Full Speed feature.
- [ ] Custom submits one complete verified fan curve.
- [ ] Enabling or disabling Full Speed does not change the selected curve. Disabling it reveals the previously selected curve.
- [ ] Fan settings do not change the separate Lenovo power or thermal profile, TDP, or power limits. Do not substitute `SetSmartFanMode` or Linux `platform_profile` for Legion Space's separate `SetFanMode` path.
- [ ] The plugin reads and shows the active firmware fan state. It does not replace it with a plugin preference after restart.
- [ ] The kernel interface serializes bounded transport calls. It does not save, infer, confirm, restore, or persist fan policy.
- [ ] Mode changes have bounded timeouts and confirmed results.
- [ ] AC-power, battery-power, firmware, and BIOS interactions are documented.
- [ ] Suspend, resume, reboot, daemon restart, and plugin crash tests do not leave an unsafe fan state.
- [ ] Full Speed has a clear noise and power warning.

### FAN-02 — Custom fan curve

**Status:** Testing

The user can edit each custom fan-curve control that the supported BIOS/EC interface exposes.

Acceptance criteria:

- [ ] The wiki records every verified curve point, unit, range, step, and ordering rule.
- [ ] Original-Go live tests verify levels `0..125`, not a firmware ceiling. The current project policy permits `0..125` at 10–70 °C, `79..125` at 80–90 °C, and `100..125` at 100 °C. The backend also accepts the exact verified Quiet and Balanced tables. The EC behavior above `125` is an open question.
- [ ] The best-effort Go 2 project policy is limited to `0..115` and accepts a recognized Go 2 product name or version after it rejects a partial Original-Go identity. This is not a firmware ceiling and remains source-backed until target validation.
- [ ] The UI shows Lenovo's per-point ranges as recommendations instead of hard limits.
- [ ] The UI requires confirmation before it applies a curve outside Lenovo's recommendations.
- [ ] The UI enforces required monotonic temperature and speed rules.
- [ ] A complete curve applies atomically, or restricted userspace rollback restores the prior curve after failure.
- [x] An exact custom curve remains in firmware through a warm reboot when no driver removes it with a restoration write.
- [ ] The plugin can read back and show the applied curve.
- [ ] The user can restore firmware defaults.
- [ ] Thermal load and sensor-failure tests confirm fail-safe fan behavior.

### FAN-03 — Fan tachometer

**Status:** Testing

The plugin shows actual fan RPM from each host generation's proved firmware interface. It does not estimate RPM from a percentage. Original host `83E1` remains live-verified; a Legion Go 2 route can be source-backed until target hardware is available.

Acceptance criteria:

- [x] The owner interface uses the fixed original-model Lenovo Other Mode WMI tachometer feature.
- [x] The owner parses the complete 32-bit response and rejects short data and the `0xffffffff` failure sentinel.
- [x] The kernel module exports standard hwmon `fan1_input` in RPM.
- [x] The restricted backend returns RPM without arbitrary EC or ACPI access.
- [x] The plugin labels the value as RPM and does not derive it from curve percentages.
- [ ] RPM readback is tested during Automatic, Full Speed, Custom, suspend, resume, and module reload.
- [ ] Missing or invalid tachometer data causes an unavailable state, not a stale or estimated value.

### GYRO-01 — Gyro inventory

**Status:** Researching

The software must find and identify each supported gyro without depending on unstable event-device numbers.

Acceptance criteria:

- [ ] The wiki records the verified gyro count, physical location, transport, identifiers, axes, units, orientation, rate, and ownership.
- [ ] Detach, reconnect, FPS mode, suspend, and resume update the inventory correctly.
- [ ] Device names clearly identify controller location or source.

### GYRO-02 — Independent emulator gyro outputs

**Status:** Deferred

**TODO:** The required source-identified motion export is not available in the installed InputPlumber release. InputPlumber source, profile, and configuration changes are outside the current project scope. Reconsider this feature only when a released owner interface can supply the required data without a project change to InputPlumber.

Acceptance criteria:

- [ ] The user can enable or disable Center, Left, and Right DSU outputs separately.
- [ ] A disabled or absent source reports its fixed DSU slot as disconnected and stops data packets.
- [ ] Disabling a DSU output does not remove motion from the main virtual controller when that gyro is the selected main source.
- [ ] Slots 1, 2, and 3 have stable source assignments and distinct stable identifiers.
- [ ] Dual Joy-Con mode can use Left and Right concurrently as Eden Motion 1 and Motion 2.
- [ ] Pro Controller and Handheld modes can select Center, Left, or Right as Eden Motion 1.
- [ ] Motion-only DSU packets keep buttons, sticks, triggers, and touch neutral. Eden's UDP-controller input option remains disabled unless separately required.
- [ ] The server binds to loopback only and uses one DSU protocol-version-1001 server for all slots.
- [ ] InputPlumber is the only physical controller and motion-source owner. The DSU backend does not open HID, IIO, evdev, or InputPlumber virtual gamepad devices directly.
- [ ] OGUI can start, stop, and query one unprivileged DSU backend instance without a root service.
- [ ] The backend accepts motion only from a source-identified InputPlumber owner interface and binds only to loopback.
- [ ] The plugin verifies each requested routing change and restores the prior state after a failure.
- [ ] The plugin detects a partial or stale-source result and does not report success.
- [ ] OGUI shows the actual InputPlumber source filter, main gyro, DSU slot state, and source presence.
- [ ] Axis orientation, scale, range, sample rate, latency, packet counter, and timestamp behavior pass recorded tests.
- [ ] The implementation prevents feedback loops and unintended duplicate input.
- [ ] Compatibility tests cover Eden Dual Joy-Con, Pro Controller, and Handheld motion mappings.
- [ ] A later non-Eden emulator requires its own compatibility evidence.

### GYRO-03 — Main-controller gyro selection

**Status:** Deferred

**TODO:** The installed InputPlumber release does not provide the required safe selection interface. InputPlumber changes are outside the current project scope. Reconsider this feature only through a released owner interface.

Acceptance criteria:

- [ ] OGUI lists only present and compatible center, left, and right gyro sources.
- [ ] The main virtual controller remains present and keeps motion input when the matching auxiliary motion device is disabled.
- [ ] Source changes do not require a reboot.
- [ ] The selected source remains stable across reconnect, suspend, resume, and service restart, or the UI explains why it cannot persist.
- [ ] Loss of the selected source causes a documented safe fallback or disables motion input.
- [ ] The UI shows the selected and active source separately when they differ.

## 5. Additional features

These items are part of the desired product. Core features take priority.

### CAL-01 — Separate joystick calibration

**Status:** Testing

- [ ] Start and stop the verified firmware calibration for the left or right joystick.
- [x] Submit one left-joystick Start report without a kernel deadline or retry, and report HID submission failure.
- [x] Report successful left-joystick completion and raw firmware error through the asynchronous hardware-status ABI.
- [ ] Test failure, cancellation, and all documented firmware errors.
- [ ] Test detach, reconnect, FPS mode, cancellation, and recovery.

### CAL-02 — Separate trigger calibration

**Status:** Implemented

- [ ] Start and stop the verified firmware calibration for the left or right trigger.
- [ ] Submit one report without a kernel deadline or retry, and report HID submission failure.
- [ ] Report asynchronous success, failure, cancellation, and firmware errors.

### CAL-03 — Separate gyro calibration

**Status:** Implemented

- [ ] Start and stop the verified firmware calibration for each supported controller gyro.
- [ ] Give the verified stillness and placement instructions.
- [ ] Submit one report without a kernel deadline or retry, and report HID submission failure.
- [ ] Report asynchronous success, failure, cancellation, and firmware errors.

### BTN-01 — Lenovo L/R and Menu/View swap

**Status:** Testing

- [ ] One setting switches the verified Lenovo L/R button events with Menu/View.
- [ ] The setting does not cause duplicate or missing events.
- [ ] The behavior is tested in the OGUI interface, Steam, and a game.
- [ ] The UI has a recovery method that does not depend on the remapped buttons.

### DPI-01 — Controller DPI

**Status:** Researching

- [ ] Use the existing controller owner for supported DPI values.
- [ ] Permit only the verified values `500`, `800`, `1200`, and `1800` unless authoritative evidence proves a different domain.
- [ ] Show actual hardware readback after a write.
- [ ] Keep DPI mapping in Steam/InputPlumber. Do not add a shortcut-assignment system.

### LED-01 — Standard controller LED integration

**Status:** Deferred

**TODO:** The installed InputPlumber release does not route this LED. InputPlumber source, profile, and configuration changes are outside the current project scope.

- [ ] Steam/UHID LED output reaches the Linux controller LED owner and the physical controller.
- [ ] InputPlumber remains the input and output routing owner.
- [ ] The plugin does not add lighting profiles, an RGB editor, effect controls, brightness controls, or speed controls that duplicate Steam.
- [ ] Disconnect, reconnect, suspend, resume, and owner restart do not leave stale LED ownership.

### VIB-01 — Controller vibration and touchpad controls

**Status:** Researching

- [ ] Use the standard force-feedback path when it supplies the required controller vibration behavior.
- [ ] Expose only missing hardware settings through a verified controller owner.
- [ ] A test-vibration operation permits side `3` or `4`, strength `0..255`, and duration `1..100` in `100 ms` units. It requires a proved firmware-expiry guarantee or a mandatory stop path.
- [ ] Touchpad enable, touchpad vibration, and controller auto-sleep use actual owner readback.
- [ ] Auto-sleep time uses minutes and supports the verified one-byte `0..255` domain. Legion Space presets do not restrict the plugin's user-facing range or require a separate off toggle.
- [ ] Go 2-only vibration modes remain behind the controller-generation gate.

### CTRL-02 — Controller factory restore

**Status:** Blocked

- [ ] The exact left, right, or both selector is known.
- [ ] The complete reset scope and persistence behavior are documented.
- [ ] The UI lists affected settings and requires confirmation.
- [ ] Recovery is tested after disconnect or failure.

### PWRLIGHT-01 — Power-button lighting states

**Status:** Researching

- [ ] Trace the power-button-light owner interface and exact selector for each supported host generation.
- [ ] Support only proved states, including on and sleep behavior when the interface distinguishes them.
- [ ] Show actual state readback.
- [ ] Do not expose arbitrary lighting or BIOS methods.
- [ ] Test boot, shutdown, suspend, resume, and external changes.

### FPS-01 — Native FPS-mode integration

**Status:** Researching

- [ ] Determine whether InputPlumber already exposes FPS mode correctly.
- [ ] Determine whether FPS mode must appear as a separate controller or source profile.
- [ ] Use native Steam/InputPlumber controller mappings. Do not add Legion template or remapping UI.
- [ ] Entering and leaving FPS mode does not leave stale devices or stuck input.

## 6. User interface quality

### UI-01 — OGUI integration

**Status:** Researching

- [ ] The plugin settings card contains one Open control. It opens a full-screen OGUI menu with Battery, Cooling, Controllers, and Calibration tabs.
- [ ] Tabs use controller shoulder navigation. Back returns to the prior OGUI state without changing InputPlumber interception.
- [ ] Controls use current OGUI plugin patterns and remain usable with a controller only.
- [ ] Controls show unavailable, pending, active, externally changed, and error states.
- [ ] Destructive or high-risk actions need confirmation.
- [ ] Text does not claim support that target detection has not confirmed.

### UI-02 — Accessibility and response

**Status:** Researching

- [ ] Every control has a clear label and focus order.
- [ ] State does not depend only on color.
- [ ] Routine state reads do not block OGUI.
- [ ] The UI remains responsive during hardware timeout and reconnect tests.

## 7. Documentation and release

### DOC-01 — Stand-alone project wiki

**Status:** Implemented

- [x] A local wiki structure exists.
- [ ] It records authoritative sources, community evidence, project discoveries, decisions, tests, and unresolved questions separately.
- [ ] Each hardware write has source evidence, bounds, risks, and recovery instructions.
- [ ] A new contributor can understand the current state without session history.

### REL-01 — Target installation and update

**Status:** Researching

- [ ] The OGUI plugin installs from the OGUI plugin store.
- [ ] The plugin can schedule a one-time backend installer for the next GNOME Desktop session only after explicit user action.
- [ ] Manual backend install and uninstall instructions work on an unmodified target image.
- [ ] The package or installation method respects Bazzite's immutable system model.
- [ ] The installer builds the HID and integrated OpenGamingCollective Lenovo WMI modules from reviewed source against the running host kernel. The plugin does not contain prebuilt kernel modules.
- [ ] A kernel update presents one explicit repair action. Rebuilding preserves each prior service-enabled state without replacing a stock kernel module on disk.
- [ ] Canceling privilege escalation causes no installation and no repeated automatic prompt.
- [ ] Updates preserve supported settings or perform a documented migration.
- [ ] Rollback restores the earlier working version.
- [ ] The release records source revisions and tested component versions.

## 8. Explicit non-goals for the first release

- Commercial distribution or Lenovo branding.
- Support for Windows.
- Support for Linux distributions other than the named Bazzite target.
- Support for Lenovo handheld models that are not in the declared per-function support matrix, including Legion Go S controls that SteamOS already owns natively.
- General audio, display, graphics-software, FPS-limiter, BIOS-management, firmware-version, BIOS-update, firmware-update, driver-installation, or device-update features.
- Unverified power-limit or overclock controls.
- Replacement of general Bazzite controller services when a safe extension point exists.
- Plugin-owned controller templates, remapping, multi-action combinations, right-menu actions, dead-zone or curve tuning, trigger-margin tuning, raw-input tests, gyro transforms, or custom controller-lighting profiles.

## 9. Verification evidence

Add one row for each verified requirement.

| Requirement | Hardware and firmware | Software versions | Test record | Date | Result |
|---|---|---|---|---|---|
| _None_ | | | | | |
