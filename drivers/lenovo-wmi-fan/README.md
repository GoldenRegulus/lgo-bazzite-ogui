# Lenovo WMI fan source

This directory contains only the modified Lenovo WMI owner source. It contains no patch files or unchanged upstream sources.

## Source base

The base is OpenGamingCollective Linux `master` commit:

```text
9c37615c0efca8ec4c7d461ef7ae2f4806951ace
```

The existing `lenovo_wmi_other` driver owns both fan WMI objects:

- Other Mode methods `17` and `18` provide independent Full Speed.
- Other Mode keeps its native RPM path and adds a conditional `fan1_input` fallback.
- Fan Method GUID `92549549-4BDE-4F06-AC04-CE8BF898DBAA` provides curve methods `5` and `6`.
- One WMI ID table selects the probe path. One common first member selects the safe removal path.

The curve transport accepts ten nondecreasing levels from zero through the model maximum. The restricted backend enforces the higher minimums at 80–100 °C.

The driver exposes current firmware state and sends requested transport operations. It does not save, infer, confirm, restore, or persist fan policy. Confirmed readback and recovery belong to restricted userspace.

`wmi-other.c` keeps the OGC categorical battery interface. It does not change thermal profiles or `platform_profile`.

## Files

The complete modified owner source is `wmi-other.c`. See the
[kernel change record](CHANGES.md) and [annotated unified diff](ANNOTATED-DIFF.patch)
for each project edit and its rationale.

## Check the source

Use the pinned OGC checkout:

```bash
./scripts/check-source.sh /tmp/ogc-master-check
```

The check verifies the pinned base source, Bash syntax, and strict KUnit source style.

## Build

Use a clean checkout and a kernel configuration:

```bash
./scripts/verify.sh /path/to/linux /path/to/kernel.config
```

The script copies the Linux tree, stages `wmi-other.c`, and builds the Lenovo WMI directory with:

```text
W=1 KCFLAGS=-Werror
```

It does not change the input tree.

## KUnit

First stage the source in a disposable Linux tree. Then build and run the five helper tests:

```bash
./scripts/stage-source.sh /path/to/linux-copy
./tests/standalone-kunit/build.sh \
  /path/to/linux-copy \
  /usr/src/kernels/$(uname -r) \
  /tmp/lenovo-wmi-fan-kunit
sudo ./tests/standalone-kunit/run.sh \
  /tmp/lenovo-wmi-fan-kunit/lenovo-wmi-fan-kunit.ko
```

The build script extracts pure production helpers from `wmi-other.c`. The test module does not register a WMI, platform, or ACPI driver.

## Safety

Do not install these files over a running kernel tree. Integrate them when you build the selected OGC kernel.

Remove the former standalone fan service and module before you activate this in-tree implementation. Do not let both owners control the same firmware routes.
