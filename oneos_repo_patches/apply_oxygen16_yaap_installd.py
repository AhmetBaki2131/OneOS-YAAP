#!/usr/bin/env python3
"""Allow the verified A05 YAAP installd ABI for Android 16 guests.

The guest proxy reads transaction codes from the verified runtime table.  The
old gate nevertheless limited the A05 YAAP table to SDK 37 guests, so preparing
OxygenOS 16 stopped at "Get app installs ready".  Keep the SHA-pinned/root
checks and extend the accepted table to SDK 36.
"""
from pathlib import Path
import argparse

YAAP_SHA = "1f1b94c0353fb2e69862a0f0411d70576a2bc8609e10c6788b425e0bdc41b874"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    if text.count(old) != 1:
        raise SystemExit(f"{path}: expected one patch anchor, found {text.count(old)}")
    path.write_text(text.replace(old, new), encoding="utf-8", newline="\n")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, type=Path)
    args = ap.parse_args()
    root = args.root.resolve()

    model = root / "app-android/core/model/src/main/kotlin/com/fahadali/oneos/core/model/InstalldTable.kt"
    replace_once(
        model,
        '    fun accepted(sdk: Int): Set<String> = when (sdk) { 37 -> setOf(SHA256, SHA256_95); 36 -> setOf(SHA256_A16, SHA256_A16_ONEUI80); else -> emptySet() }',
        f'''    /** Verified SM-A055F/M YAAP table; runtime-code guests resolve matching signatures safely. */
    const val SHA256_YAAP = "{YAAP_SHA}"

    fun accepted(sdk: Int): Set<String> = when (sdk) {{
        37 -> setOf(SHA256, SHA256_95, SHA256_YAAP)
        36 -> setOf(SHA256_A16, SHA256_A16_ONEUI80, SHA256_YAAP)
        else -> emptySet()
    }}''',
    )

    root_script = root / "app-android/app/src/full/assets/root/oneos_root.sh"
    replace_once(
        root_script,
        '    if [ "$(image_sdk "$2")" = 36 ]; then carried=$INSTALLD_SHA_36 ok=$INSTALLD_OK_36',
        '    if [ "$(image_sdk "$2")" = 36 ]; then carried=$INSTALLD_SHA_36 ok="$INSTALLD_OK_36 $INSTALLD_SHA_YAAP"',
    )

    build = root / "app-android/app/build.gradle.kts"
    replace_once(build, '        versionCode = 175\n        versionName = "0.5.32"',
                 '        versionCode = 176\n        versionName = "0.5.33"')

    print("OxygenOS 16 on verified A05 YAAP installd: enabled (OneOS 0.5.33/176)")


if __name__ == "__main__":
    main()

