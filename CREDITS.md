# Credits

OneOS-YAAP is built on top of **OneOS** and other open-source projects. This file lists the upstream authors, contributors, and libraries along with the terms under which their work is distributed. Own code in this repository is licensed under the Apache License 2.0 (`LICENSE`, `NOTICE`).

## Upstream OneOS, by Fahad Ali Javed

<https://github.com/fahadalijaved/OneOS> — Apache License 2.0, Copyright 2026 The OneOS Authors.

The complete OneOS Android application (`OneOS-source/app-android/`), guest container manager (`OneOS-source/app-android/guest/`), safety gates, `IInstalld` verification engine, and container switcher scripts (`OneOS-source/switcher/`) were created by **Fahad Ali Javed** (<https://github.com/fahadalijaved>) and the OneOS contributors.

## OneOS-YAAP (Galaxy A05 & Custom ROM / Cross-SDK Bridge), by Ahmet Baki

<https://github.com/AhmetBaki2131/OneOS-YAAP> — Apache License 2.0, Copyright 2026 Ahmet Baki.

Adaptation of OneOS for **Samsung Galaxy A05 (`SM-A055F` / `SM-A055M`, MediaTek Helio G85 `MT6768` / `MT6769V/CZ`)** and AOSP-based custom ROM hosts (YAAP, LineageOS, crDroid, EvolutionX, PixelOS, GSI):
- Runtime DEX bytecode patcher (`YaapInstalldDexPatcher.kt`) remapping `OneOSInstalldProxy` transaction codes and bridging Android 16 (SDK 36) `getAppSize` / `getUserSize` `Parcel` signatures to Android 17 (SDK 37) `installd`.
- Cross-SDK (`SDK 36` guest on `SDK 37` host) session property and `BOOTCLASSPATH` (`framework-virtualization.jar`) compatibility bridge.
- Universal custom ROM host verification (`CustomRom.kt`, `InstalldTable.kt`, `Gates.kt`) and automated GitHub Releases self-update pipeline (`update.json`).

## OneLineage, by WeWaffles

<https://github.com/WeWaffles/OneLineage>

The container hot-switch that OneOS is built on: staging a GSI on a rooted Samsung phone, pivoting into it with its own zygote and system_server, and handing the screen back to the host OS. `switcher/` began as an unmodified copy of OneLineage (`afa0fee`). OneOS's session scripts started from OneLineage's:

| OneOS | Started from (OneLineage) |
| --- | --- |
| `switcher/assets/guest_prepare.sh` | `master_prepare.sh` |
| `switcher/assets/guest_start.sh` | `master_inner.sh` |
| `switcher/assets/oneos_switch.sh` | `switch_to_lineage.sh` |
| `switcher/assets/return_to_oneui.sh` | `return_to_oneui.sh` |

`switcher/README.md` is OneLineage's own README, kept as its credit. `switcher/assets/zygote_exec` is OneOS's build of `switcher/native/zygote_launcher.c`. OneLineage's own Android app is not part of this repository.

OneLineage has no license file. WeWaffles gave written permission (2026-10-24) to publish OneOS on top of OneLineage with full credit, here and in the app's About screen. That permission covers this publication; it is not a license for third parties to reuse the OneLineage-derived files.

## Galaxy Z Fold8 support, by Josh Skinner

<https://github.com/thatjoshguy67>, [pull request #1](https://github.com/fahadalijaved/OneOS/pull/1) (Apache-2.0, as a contribution to upstream OneOS).

Josh brought OneOS to the Galaxy Z Fold8 (SM-F971B) and tested it there: the `n6-f8` set and `scripts/make-fold8-coloros.py` (cover display, Quick Settings, AOD, widgets, taskbar, Pocket Studio), the Google snapshot that became `switcher/assets/guest_google.sh`, `switcher/assets/fold8_coloros.sh`, and the hinge work: Samsung's folding-angle sensor relay (`switcher/patches/fold8-coloros/OneOSAngleRelay.java`), the half-open device state, the reveal and closing animations, and the Pixel side (`switcher/assets/fold8_pixel.sh`, `switcher/patches/fold8-pixel/`, `scripts/make-fold8-pixel.py`).

## Guest screen lock, fingerprint and face, by vdcoolok

<https://github.com/vdcoolok>, [pull request #152](https://github.com/fahadalijaved/OneOS/pull/152) (Apache-2.0, as a contribution to upstream OneOS).

The screen lock kept inside the guest (`switcher/patches/guest_local_lock.py`, `OneOSGuestLock.java`), the guest reaching the phone's fingerprint sensor through AIDL (`switcher/patches/guest_force_aidl_fingerprint.py`) and One UI's enrolment lists carried into the guest (`switcher/assets/guest_prepare.sh`, "Guest biometrics"). OneOS added the removal guard (`switcher/patches/guest_no_biometric_remove.py`) before shipping them.

## The OneOS website, by fouadd

<https://github.com/fouadd123>, [pull request #237](https://github.com/fahadalijaved/OneOS/pull/237)

fouadd designed and built the OneOS website, <https://fahadalijaved.github.io/OneOS/>: the systems catalog, the phone compatibility pages and the comparison, in one page served from the `gh-pages` branch. Credits to thatjoshguy67 (<https://github.com/thatjoshguy67>), the website styling is ported from tjg.gg with permission.

## MysticGSI

<https://github.com/MysticGSI/mysticgsi>, Apache License 2.0, Copyright 2024-2026 The MysticGSI Authors (Romashka, hpdevfox).

OneOS's guest images are built with MysticGSI. MysticGSI and the way OneOS drives it are not part of this repository; what is here is how OneOS patches a built image (`scripts/make-overlays.sh`, `switcher/patches/`). MysticGSI includes work from the TrebleDroid project by Pierre-Hugues Husson (phh) and contributors (<https://github.com/TrebleDroid>), credited by MysticGSI's NOTICE.

## The app's libraries

Used by `OneOS-source/app-android/` (versions in `OneOS-source/app-android/gradle/libs.versions.toml`):

| Library | License | Copyright / source |
| --- | --- | --- |
| SESL: `io.github.oneuiproject.sesl` core, appcompat, material, recyclerview, preference (and indexscroll, picker-basic and others they bring) | MIT | Copyright (c) 2022 Yanndroid & BlackMesa123; <https://github.com/OneUIProject>. Based on AndroidX and Material Components for Android (Apache-2.0) |
| `io.github.oneuiproject:design` (oneui-design) | MIT | Copyright (c) 2022 Yanndroid & BlackMesa123 |
| `io.github.oneuiproject:icons` (oneui-icons, the `ic_oui_*` icons) | MIT | Copyright (c) 2022 Yanndroid & BlackMesa123 |
| `com.android.tools.smali:smali-dexlib2` | BSD 3-Clause | Google LLC and Ben Gruver; <https://github.com/google/smali> |
| AndroidX (activity, annotation, lifecycle, transition, cardview, loader, ...) | Apache-2.0 | The Android Open Source Project |
| Kotlin standard library | Apache-2.0 | JetBrains s.r.o. and Kotlin contributors |
| Guava, failureaccess | Apache-2.0 | The Guava Authors |
| ZXing core | Apache-2.0 | ZXing authors |
| JSR 305 annotations | Apache-2.0 | <https://github.com/findbugsproject/findbugs> |
| Gradle Wrapper (`gradle/wrapper/gradle-wrapper.jar`) | Apache-2.0 | Gradle Inc. |
| JUnit 4 (tests only, not shipped) | EPL-1.0 | JUnit team |

The MIT License of the OneUIProject libraries:

```text
MIT License

Copyright (c) 2022 Yanndroid & BlackMesa123

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Works with (not bundled)

OneOS needs root on the phone and uses the root manager's own tools at run time; none of them is in this repository or in the app: [KernelSU](https://github.com/tiann/KernelSU) and KernelSU Next, [Magisk](https://github.com/topjohnwu/Magisk) and [APatch](https://github.com/bmax121/APatch) (all GPL-3.0).

## Trademarks and firmware

Not affiliated with Samsung, Google, OPPO or OnePlus. Galaxy and One UI are trademarks of Samsung Electronics; Android and Pixel of Google LLC; ColorOS of OPPO; OxygenOS of OnePlus. No system images, vendor firmware or patched vendor files are in this repository.
