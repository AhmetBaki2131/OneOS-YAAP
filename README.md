# OneOS-YAAP — Custom ROM & Android 15–17 Adaptation for Samsung Galaxy A05 (`SM-A055F` / `SM-A055M`)

OneOS-YAAP adapts the open-source [**OneOS**](https://github.com/fahadalijaved/OneOS) container hot-switch platform for **Samsung Galaxy A05 (`SM-A055F` / `SM-A055M`, codename `a05m`, MediaTek Helio G85 `MT6768` / `MT6769V/CZ`)** and AOSP-based custom ROM hosts (YAAP, LineageOS, crDroid, EvolutionX, PixelOS, GSI) across **Android 15 (API 35), Android 16 (API 36), and Android 17 (API 37)**.

- **License & Notice:** Licensed under the Apache License, Version 2.0 — see [`LICENSE`](LICENSE), [`NOTICE`](NOTICE), and [`CREDITS.md`](CREDITS.md).
- **Upstream Base:** [`fahadalijaved/OneOS`](https://github.com/fahadalijaved/OneOS) (`OneOS-source/` snapshot, updated to `v0.5.50` / `fcb9d27`).
- **Automated Releases & Self-Update:** Every push to `main` builds signed `OneOS-<version>.apk` and `OneOS-Probe-<version>.apk` via GitHub Actions and publishes a `Latest` GitHub Release with a validated `update.json` for seamless in-app auto-updates.

---

## Android 15 / 16 / 17 Host & Guest Compatibility Matrix

The GitHub Actions workflow applies:
1. `oneos_repo_patches/apply_yaap_patches.ps1` (Galaxy A05 `a05-f` / `a05-m` profiles, MediaTek `MT6769V/CZ -> MT6768` mapping, `YaapInstalldDexPatcher.kt`).
2. `oneos_repo_patches/apply_multirom_patches.py` (Multi-ROM guest profiles and hardware compatibility guards).
3. `oneos_repo_patches/apply_android15_16_17_compat.py` (Android 15–17 host evaluation, SDK 36-on-37 cross-SDK bridge, automatic in-app self-update).

| Host Android | Host API | SDK 37 Guest (ColorOS 17, PixelOS 17, LineageOS 24, Infinity-X 4.1, Nothing OS 5.0, HyperOS, One UI 9.5) | SDK 36 Guest (OxygenOS 16 `CPH2745`) |
| --- | --- | --- | --- |
| **Android 15** | 35 | Prepare-only; switch blocked (ABI mismatch) | Prepare-only; switch blocked |
| **Android 16** | 36 | Prepare-only; switch blocked (ABI mismatch) | Native SDK 36 switching supported |
| **Android 17** | 37 | Native SDK 37 switching supported (27 `ALLOWED` `IInstalld` methods verified) | **Bridged SDK 36-on-37 switching supported** (`YaapInstalldDexPatcher` + SDK/BOOTCLASSPATH bridge) |

> [!WARNING]
> **Experimental Container Switch:** OneOS hot-switches Android systems using root privileges, `/data` bind mounts, and a container `zygote`/`system_server` takeover. Always keep a full backup and set your host screen lock to **None** or **Swipe** before switching.

---

## Key Features & Technical Highlights

### 1. Universal Custom ROM Host & `IInstalld` Bytecode Bridge (`YaapInstalldDexPatcher.kt`)
- Evaluates AOSP-based custom ROM hosts by their actual `IInstalld.Stub` transaction table and hardware HALs rather than requiring `ro.build.version.oneui`.
- Dynamically patches `OneOSInstalldProxy` inside `services_patched.jar` on the device during preparation:
  - Remaps shifted transaction codes (e.g., `createFsveritySetupAuthToken` `53 -> 52` and `enableFsverity` `54 -> 53` on SDK 37, or 19 shifted methods `fixupAppData`..`getOdexVisibility` for SDK 36 guests on SDK 37 hosts).
  - Bridges Android 16 (SDK 36) `getAppSize` and `getUserSize` `Parcel` payloads to Android 17 (SDK 37) `installd` by compacting the `Parcel.obtain(IBinder)` prologue and serializing the extra Android 17 `int` / `int[]` argument in-place.
  - Refreshes `guards.txt` SHA-256 digests so all pre-flight and runtime integrity checks pass.

### 2. SDK 36 Guest (OxygenOS 16) on SDK 37 Host Bridge
- **`guest_props.sh`:** Sets session-scoped `ro.build.version.sdk_full=36.0`, `ro.*.build.version.sdk=36`, and `ro.*.build.version.release=16` while the guest runs, restoring host properties (`37` / `17`) automatically on in-place return.
- **`guest_start.sh`:** Appends `/apex/com.android.virt/javalib/framework-virtualization.jar` to the guest's derived `BOOTCLASSPATH` when the host's `com.android.virt` APEX tags it with `min_sdk_version=37`, preventing `SystemServiceRegistry` from throwing `NoClassDefFoundError: VirtualizationFrameworkInitializer` during `zygote64` preload.

### 3. Live Device Verification on Galaxy A05 (`SM-A055F` / YAAP 17)
- **Display & Cutout:** `720x1600 @ 300 dpi`, status bar `66 px`, center camera cutout `58 px`.
- **Camera & Sensors:** Preserves guest camera apps on custom ROM hosts (optional `ONEOS_GUEST_WINGCAM=1`); verified accelerometer, ambient light, and proximity sensors via AIDL/HIDL sensor service.
- **Charging & Thermal Safety:** Never forces PMIC voltage or current; mirrors kernel-negotiated PD/PPS/HVDCP fast-charging state to `sys.oneos.fast_charging`.
- **Telephony & Audio:** MediaTek RIL (`mt6768`), LTE-A (4.5G), and AIDL audio HAL (`vendor.audio-hal-aidl`) handover verified.

---

## Repository Structure

- [`OneOS-source/`](OneOS-source/) — Complete upstream OneOS source snapshot (`app-android/` and `switcher/`).
- [`oneos_repo_patches/`](oneos_repo_patches/)
  - [`apply_yaap_patches.ps1`](oneos_repo_patches/apply_yaap_patches.ps1) — Galaxy A05 (`a05-f` / `a05-m`) & MediaTek `MT6768` patches.
  - [`YaapInstalldDexPatcher.kt`](oneos_repo_patches/YaapInstalldDexPatcher.kt) — On-device DEX bytecode patcher for `OneOSInstalldProxy`.
  - [`apply_multirom_patches.py`](oneos_repo_patches/apply_multirom_patches.py) — Multi-ROM guest compatibility patches.
  - [`apply_android15_16_17_compat.py`](oneos_repo_patches/apply_android15_16_17_compat.py) — Android 15–17 host matrix, SDK 36-on-37 bridge, and automatic self-update patches.
  - [`AndroidHostMatrixTest.kt`](oneos_repo_patches/AndroidHostMatrixTest.kt) — Unit tests verifying Android 15/16/17 host and guest gate combinations.
- [`scripts/`](scripts/) — Read-only ADB hardware/installd probe scripts (`yaap_a05_probe.sh`, `run_yaap_probe.ps1`, `patch_guest_installd_yaap.py`).
- [`.github/workflows/build-oneos-yaap.yml`](.github/workflows/build-oneos-yaap.yml) — Automated signed APK builder, signature verifier, and GitHub Releases + `update.json` publisher.

---

## License & Credits

- **License:** [Apache License 2.0](LICENSE)
- **Notice:** [NOTICE](NOTICE)
- **Credits & Attributions:** [CREDITS.md](CREDITS.md) (Upstream OneOS by **Fahad Ali Javed**, OneLineage by **WeWaffles**, MysticGSI, TrebleDroid, OneUIProject SESL, and contributors).
