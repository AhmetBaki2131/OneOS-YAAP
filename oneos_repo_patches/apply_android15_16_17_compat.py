#!/usr/bin/env python3
"""OneOS host Android 15/16/17 preparation support, with fail-closed switching.

Apply after apply_yaap_patches.ps1 and apply_multirom_patches.py.
This does NOT convert a ColorOS 17 guest into an Android 15/16 guest.
"""
from pathlib import Path
import argparse

GATES = Path("app-android/core/model/src/main/kotlin/com/fahadali/oneos/core/model/Gates.kt")

def replace_once(content: str, old: str, new: str, label: str) -> str:
    if new in content:
        return content
    n = content.count(old)
    if n != 1:
        raise ValueError(f"{label}: expected one original anchor, got {n}")
    return content.replace(old, new, 1)

def patch_gates(source: str) -> str:
    source = replace_once(
        source,
        "out += Gate(android(f, image, profile, images))",
        "out += Gate(android(f, image, profile, images, switching))",
        "Android gate call",
    )
    source = replace_once(
        source,
        "out += Gate(installd(input, image))",
        "out += Gate(installd(input, image, switching))",
        "installd gate call",
    )
    source = replace_once(
        source,
        "private fun android(f: DeviceFacts, image: ImageRef?, profile: PhoneProfile?, images: List<ImageRef>): Finding {",
        "private fun android(f: DeviceFacts, image: ImageRef?, profile: PhoneProfile?, images: List<ImageRef>, switching: Boolean): Finding {",
        "Android gate signature",
    )
    source = replace_once(
        source,
        """        } else if (profile != null && offered.isNotEmpty() && f.sdk < offered.first()) {
            // No system of this phone runs next to its One UI: nothing to choose, One UI has to be updated.""",
        """        } else if (!switching && f.sdk in 35..37 && sdks.isNotEmpty()) {
            // SDK 35/36/37 hosts can inspect and prepare a signed image without pretending its
            // guest framework has been backported. The SWITCH gate below remains BLOCK.
            Finding(
                ID_ANDROID, Level.WARN, "Preparation only: Android SDK mismatch",
                "Host Android $have (SDK ${f.sdk}); selected image SDK ${sdks.joinToString()}. " +
                    "Preparing files is allowed for development, but switching requires a guest " +
                    "built for this Android version, matching IInstalld ABI and verified HALs.",
                R_ANDROID_DIFFERS,
            )
        } else if (profile != null && offered.isNotEmpty() && f.sdk < offered.first()) {
            // No system of this phone runs next to its One UI: nothing to choose, One UI has to be updated.""",
        "Android 15/16/17 preparation policy",
    )
    start = source.index("    private fun installd(input: GateInput, image: ImageRef? = null): Finding {")
    end = source.index("    private fun oldSwitcher(", start)
    old = source[start:end]
    new = """    private fun installd(input: GateInput, image: ImageRef? = null, switching: Boolean): Finding {
        // Check the HOST API, never the guest API. Treating a ColorOS 17 image as
        // Android 15/16 would send incompatible installd transaction codes.
        val hostSdk = input.facts.sdk
        val guestSdk = image?.sdk
        if (guestSdk != null && guestSdk != hostSdk) {
            return if (switching) {
                block(
                    ID_INSTALLD, "Host and guest ABI versions differ",
                    "Host SDK $hostSdk, image SDK $guestSdk. No verified cross-version " +
                        "IInstalld/ART/HAL bridge is available; switching is disabled.",
                    R_INSTALLD_DIFFERS,
                )
            } else {
                Finding(
                    ID_INSTALLD, Level.WARN, "Host and guest ABI differ (preparation only)",
                    "Host SDK $hostSdk, image SDK $guestSdk. File preparation is allowed, " +
                        "but the guest cannot be launched without an ABI-compatible build.",
                    R_INSTALLD_DIFFERS,
                )
            }
        }
        if (hostSdk == 35) {
            return if (switching) {
                block(
                    ID_INSTALLD, "Android 15 installd bridge not validated",
                    "This build has no verified SDK 35 guest proxy and host installd map. " +
                        "Create and validate an Android 15 guest set first.",
                    R_INSTALLD_DIFFERS,
                )
            } else {
                Finding(
                    ID_INSTALLD, Level.WARN, "Android 15 host (preparation only)",
                    "The SDK 35 installd proxy is not packaged in this build. " +
                        "Do not launch until the Android 15 guest and host ABI are validated.",
                    R_INSTALLD_DIFFERS,
                )
            }
        }
        val sdk = hostSdk
        val p = InstalldExpected.problems(
            input.installd,
            if (sdk == 36) input.expectedInstalldA16 else input.expectedInstalld,
            sdk,
            allowAospAllowedMatch = input.allowCustomAospHost,
        )
        return if (p.isEmpty()) {
            Finding(
                ID_INSTALLD, Level.OK, "installd interface matches the OneOS files",
                "${input.installd?.methods?.size} methods, the same table the guard jars carry.",
            )
        } else {
            block(
                ID_INSTALLD, "installd interface differs from the OneOS files",
                p.take(6).joinToString("; ") + ". The guard jars use specific installd " +
                    "transaction codes; switching needs a compatible, verified map.",
                R_INSTALLD_DIFFERS,
            )
        }
    }

"""
    if "allowAospAllowedMatch = input.allowCustomAospHost" not in old:
        raise ValueError("This patch must run after apply_yaap_patches.ps1")
    if "Host and guest ABI versions differ" in old:
        return source
    source = source[:start] + new + source[end:]
    return source

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--check", action="store_true", help="validate anchors only")
    args = ap.parse_args()
    path = args.root / GATES
    original = path.read_text(encoding="utf-8")
    updated = patch_gates(original)
    if updated == original:
        print("ALREADY PATCHED", GATES)
    elif args.check:
        print("CHECK OK", GATES)
    else:
        path.write_text(updated, encoding="utf-8", newline="\n")
        print("PATCHED", GATES)

if __name__ == "__main__":
    main()
