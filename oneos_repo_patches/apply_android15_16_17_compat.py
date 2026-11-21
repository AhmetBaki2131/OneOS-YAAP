#!/usr/bin/env python3
"""OneOS host Android 15/16/17 + universal custom ROM support, with fail-closed switching.

Apply after apply_yaap_patches.ps1 and apply_multirom_patches.py.
This does NOT convert a ColorOS 17 guest into an Android 15/16 guest.
"""
from pathlib import Path
import argparse

GATES = Path("app-android/core/model/src/main/kotlin/com/fahadali/oneos/core/model/Gates.kt")
CUSTOM_ROM = Path("app-android/core/model/src/main/kotlin/com/fahadali/oneos/core/model/CustomRom.kt")
PROFILES = Path("app-android/core/model/src/main/kotlin/com/fahadali/oneos/core/model/Profiles.kt")
INSTALLD_TABLE = Path("app-android/core/model/src/main/kotlin/com/fahadali/oneos/core/model/InstalldTable.kt")
APP_ASSETS = Path("app-android/app/src/full/kotlin/com/fahadali/oneos/session/AppAssets.kt")
PREPARE_JOB = Path("app-android/app/src/full/kotlin/com/fahadali/oneos/session/PrepareJob.kt")
ROOT_SH = Path("app-android/app/src/full/assets/root/oneos_root.sh")


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
        if (hostSdk == 35 && guestSdk != 35) {
            val a15Ok = input.installd != null && InstalldExpected.allowedSubsetCompatible(input.installd, 35)
            val abiNote = " Android 15 host IInstalld 27-method ABI: ${if (a15Ok) "compatible" else "incompatible"}."
            return if (switching) {
                block(
                    ID_INSTALLD, "Android 15 guest image required",
                    "This build has no validated Android 15 (SDK 35) guest image/set; switching is disabled.$abiNote",
                    R_INSTALLD_DIFFERS,
                )
            } else {
                Finding(
                    ID_INSTALLD, Level.WARN, "Android 15 host (preparation only)",
                    "No Android 15 (SDK 35) guest image is staged yet; preparation is allowed for development.$abiNote",
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
                "${input.installd?.methods?.size} methods verified for SDK $sdk.",
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
    if "Host and guest ABI versions differ" not in old:
        source = source[:start] + new + source[end:]
    return source


def patch_custom_rom(source: str) -> str:
    source = replace_once(
        source,
        """        if (port) {
            return finding(""",
        """        if (port) {
            if (allowCustomAospHost) {
                return Finding(
                    ID, Level.WARN, "Custom ROM / One UI port host (experimental)",
                    "This phone reports ${s.model.ifBlank { "?" }} on bootloader ${s.bootloader.ifBlank { "?" }}" +
                        (if (s.vendorModel.isNotBlank()) " / vendor ${s.vendorModel}" else "") +
                        ". Switching uses hardware detection and requires a verified host installd table.",
                    R_PORT,
                )
            }
            return finding(""",
        "CustomRom port opt-in",
    )
    source = replace_once(
        source,
        "        if (!oneUi && sameModel) {",
        "        if (!oneUi && (sameModel || (allowCustomAospHost && samsungHardware))) {",
        "CustomRom spoofed model samsungHardware check",
    )
    source = replace_once(
        source,
        '"This ${s.model} runs an AOSP-based ROM without ro.build.version.oneui. Switching requires a verified host installd table and compatible camera, sensor and graphics HALs."',
        '"This ${s.model} runs a custom ROM without ro.build.version.oneui (LineageOS, crDroid, EvolutionX, PixelOS, YAAP, GSI, etc.). Switching requires a verified host installd table and compatible camera, sensor and graphics HALs."',
        "CustomRom universal wording",
    )
    return source


def patch_profiles(source: str) -> str:
    source = replace_once(
        source,
        "        choices = listOf(X9U_IN_1105_CHOICE, INFINITYX_CHOICE, LINEAGE_CHOICE, HYPEROS_CHOICE, NOTHING_A_CHOICE),",
        "        choices = listOf(X9U_IN_1105_CHOICE, OXYGEN16_CHOICE, INFINITYX_CHOICE, LINEAGE_CHOICE, HYPEROS_CHOICE, HYPEROS_HK_CHOICE, NOTHING_A_CHOICE, ONEUI95_CHOICE),",
        "Profiles A05 choices incl Android 16",
    )
    source = replace_once(
        source,
        """    fun resolve(f: DeviceFacts, profiles: List<PhoneProfile> = BUILT_IN): ProfileResolution =
        resolve(f.model, f.device, f.soc.model, profiles)""",
        """    fun resolve(f: DeviceFacts, profiles: List<PhoneProfile> = BUILT_IN): ProfileResolution {
        val primary = resolve(f.model, f.device, f.soc.model, profiles)
        if (primary.profile != null) return primary
        val vModel = f.vendorModel.trim()
        if (vModel.isNotEmpty()) {
            val byVendor = resolve(vModel, f.device, f.soc.model, profiles)
            if (byVendor.profile != null) return byVendor
        }
        val bl = f.bootloader.trim().uppercase(Locale.ROOT)
        if (CustomRomRule.samsungBootloader(bl) && bl.length >= 5) {
            val byBl = resolve("SM-${bl.take(5)}", f.device, f.soc.model, profiles)
            if (byBl.profile != null) return byBl
        }
        return primary
    }""",
        "Profiles vendorModel/bootloader fallback",
    )
    return source


def patch_installd_table(source: str) -> str:
    anchor_after_37 = """    val ALLOWED_YAAP_FSVERITY_37: Map<String, Pair<Int, String>> = mapOf(
        "createFsveritySetupAuthToken" to (52 to "(Landroid/os/ParcelFileDescriptor;I)Landroid/os/IInstalld\\$IFsveritySetupAuthToken;"),
        "enableFsverity" to (53 to "(Landroid/os/IInstalld\\$IFsveritySetupAuthToken;Ljava/lang/String;Ljava/lang/String;)I"),
    )"""
    allowed_36_35 = """    val ALLOWED_YAAP_FSVERITY_37: Map<String, Pair<Int, String>> = mapOf(
        "createFsveritySetupAuthToken" to (52 to "(Landroid/os/ParcelFileDescriptor;I)Landroid/os/IInstalld\\$IFsveritySetupAuthToken;"),
        "enableFsverity" to (53 to "(Landroid/os/IInstalld\\$IFsveritySetupAuthToken;Ljava/lang/String;Ljava/lang/String;)I"),
    )

    /** Exact 27 ALLOWED methods from switcher/patches/host_installd_a16.txt (Android 16 / SDK 36). */
    val ALLOWED_AOSP_36: Map<String, Pair<Int, String>> = mapOf(
        "createUserData" to (1 to "(Ljava/lang/String;III)V"),
        "setFirstBoot" to (3 to "()V"),
        "createAppData" to (4 to "(Landroid/os/CreateAppDataArgs;)Landroid/os/CreateAppDataResult;"),
        "createAppDataBatched" to (5 to "([Landroid/os/CreateAppDataArgs;)[Landroid/os/CreateAppDataResult;"),
        "restoreconAppData" to (7 to "(Ljava/lang/String;Ljava/lang/String;IIILjava/lang/String;)V"),
        "fixupAppData" to (11 to "(Ljava/lang/String;I)V"),
        "getAppSize" to (12 to "(Ljava/lang/String;[Ljava/lang/String;III[J[Ljava/lang/String;)[J"),
        "getUserSize" to (13 to "(Ljava/lang/String;II[I)[J"),
        "getExternalSize" to (14 to "(Ljava/lang/String;II[I)[J"),
        "getAppCrates" to (15 to "(Ljava/lang/String;[Ljava/lang/String;I)[Landroid/os/storage/CrateMetadata;"),
        "getUserCrates" to (16 to "(Ljava/lang/String;I)[Landroid/os/storage/CrateMetadata;"),
        "controlDexOptBlocking" to (20 to "(Z)V"),
        "mergeProfiles" to (22 to "(ILjava/lang/String;Ljava/lang/String;)I"),
        "dumpProfiles" to (23 to "(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Z)Z"),
        "copySystemProfile" to (24 to "(Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;)Z"),
        "createProfileSnapshot" to (28 to "(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;)Z"),
        "linkNativeLibraryDirectory" to (32 to "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;I)V"),
        "createOatDirs" to (33 to "(Ljava/lang/String;Ljava/lang/String;Ljava/util/List;)V"),
        "linkFile" to (34 to "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V"),
        "hashSecondaryDexFile" to (38 to "(Ljava/lang/String;Ljava/lang/String;ILjava/lang/String;I)[B"),
        "invalidateMounts" to (39 to "()V"),
        "isQuotaSupported" to (40 to "(Ljava/lang/String;)Z"),
        "prepareAppProfile" to (41 to "(Ljava/lang/String;IILjava/lang/String;Ljava/lang/String;Ljava/lang/String;)Z"),
        "tryMountDataMirror" to (46 to "(Ljava/lang/String;)V"),
        "getOdexVisibility" to (50 to "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I"),
        "createFsveritySetupAuthToken" to (52 to "(Landroid/os/ParcelFileDescriptor;I)Landroid/os/IInstalld\\$IFsveritySetupAuthToken;"),
        "enableFsverity" to (53 to "(Landroid/os/IInstalld\\$IFsveritySetupAuthToken;Ljava/lang/String;Ljava/lang/String;)I"),
    )

    /** Android 15 (SDK 35) AOSP IInstalld signatures for the 27 ALLOWED methods. */
    val ALLOWED_AOSP_35: Map<String, Pair<Int, String>> = ALLOWED_AOSP_36

    fun allowedMapForSdk(sdk: Int): Map<String, Pair<Int, String>>? = when (sdk) {
        37 -> ALLOWED_AOSP_37
        36 -> ALLOWED_AOSP_36
        35 -> ALLOWED_AOSP_35
        else -> null
    }"""
    source = replace_once(source, anchor_after_37, allowed_36_35, "InstalldTable ALLOWED_AOSP_36/35")

    old_helpers = """    fun allowedSubsetCompatible(derived: InstalldDerivation): Boolean {
        if (!derived.ok) return false
        val byName = derived.methods.associateBy { it.name }
        if (byName.size != derived.methods.size) return false
        if (derived.methods.map { it.code }.toSet().size != derived.methods.size) return false
        val exact = ALLOWED_AOSP_37.all { (name, want) ->
            val got = byName[name] ?: return@all false
            got.code == want.first && got.signature == want.second
        }
        if (exact) return true
        return ALLOWED_AOSP_37.all { (name, want) ->
            val got = byName[name] ?: return@all false
            val yaapShift = ALLOWED_YAAP_FSVERITY_37[name]
            got.signature == want.second && got.code == (yaapShift?.first ?: want.first)
        }
    }

    fun needsYaapFsverityPatch(derived: InstalldDerivation?): Boolean {
        if (derived == null || !allowedSubsetCompatible(derived)) return false
        val byName = derived.methods.associateBy { it.name }
        return byName["createFsveritySetupAuthToken"]?.code == 52 && byName["enableFsverity"]?.code == 53
    }"""
    new_helpers = """    fun allowedSubsetCompatible(derived: InstalldDerivation, sdk: Int = 37): Boolean {
        if (!derived.ok) return false
        val expected = allowedMapForSdk(sdk) ?: return false
        val byName = derived.methods.associateBy { it.name }
        if (byName.size != derived.methods.size) return false
        if (derived.methods.map { it.code }.toSet().size != derived.methods.size) return false
        return expected.all { (name, want) ->
            val got = byName[name]
            if (got == null) sdk == 35 && name == "createOatDirs"
            else got.signature == want.second && got.code in 1..InstalldTableFormat.MAX_METHODS
        }
    }

    fun hostTableHash(derived: InstalldDerivation?): String? {
        if (derived == null || !derived.ok) return null
        return Hashes.sha256(methodLines(derived.methods))
    }

    fun customRomCodeRemap(derived: InstalldDerivation?, sdk: Int): Map<String, Pair<Int, Int>> {
        if (derived == null || !derived.ok) return emptyMap()
        val expected = allowedMapForSdk(sdk) ?: return emptyMap()
        val byName = derived.methods.associateBy { it.name }
        val remap = linkedMapOf<String, Pair<Int, Int>>()
        for ((name, want) in expected) {
            val got = byName[name] ?: continue
            if (got.signature == want.second && got.code != want.first) {
                remap[name] = want.first to got.code
            }
        }
        return remap
    }

    fun needsCustomRomRemap(derived: InstalldDerivation?, sdk: Int = 37): Boolean {
        if (derived == null || !allowedSubsetCompatible(derived, sdk)) return false
        val hash = hostTableHash(derived) ?: return false
        return hash !in accepted(sdk)
    }

    fun needsYaapFsverityPatch(derived: InstalldDerivation?): Boolean = needsCustomRomRemap(derived, 37)"""
    source = replace_once(source, old_helpers, new_helpers, "InstalldTable universal allowedSubsetCompatible")

    source = replace_once(
        source,
        """        val compatible = Hashes.sha256(got) in accepted(sdk) ||
            (allowAospAllowedMatch && sdk == 37 && allowedSubsetCompatible(derived))""",
        """        val compatible = Hashes.sha256(got) in accepted(sdk) ||
            (allowAospAllowedMatch && sdk in 35..37 && allowedSubsetCompatible(derived, sdk))""",
        "InstalldTable problems sdk 35..37",
    )
    return source


def patch_app_assets(source: str) -> str:
    old = """        if (!InstalldExpected.needsYaapFsverityPatch(derivation)) return base
        val origSha = base["services_patched.jar"] ?: return base
        val yaap = YaapInstalldDexPatcher.cachedMeta(ctx, origSha) ?: return base
        val out = base.toMutableMap()
        out["services_patched.jar"] = yaap.sha256
        val origGuards = base["guards.txt"]
        if (origGuards != null) {
            YaapInstalldDexPatcher.cachedGuardsMeta(ctx, origGuards, origSha)?.let {
                out["guards.txt"] = it.sha256
            }
        }"""
    new = """        val setSdk = Images.byId(set.imageId)?.sdk ?: 37
        if (!InstalldExpected.needsCustomRomRemap(derivation, setSdk)) return base
        val hostKey = InstalldExpected.hostTableHash(derivation)?.take(16) ?: return base
        val origSha = base["services_patched.jar"] ?: return base
        val yaap = YaapInstalldDexPatcher.cachedMeta(ctx, origSha, hostKey) ?: return base
        val out = base.toMutableMap()
        out["services_patched.jar"] = yaap.sha256
        val origGuards = base["guards.txt"]
        if (origGuards != null) {
            YaapInstalldDexPatcher.cachedGuardsMeta(ctx, origGuards, origSha, hostKey)?.let {
                out["guards.txt"] = it.sha256
            }
        }"""
    return replace_once(source, old, new, "AppAssets expectedStageHashes hostKey")


def patch_prepare_job(source: str) -> str:
    return replace_once(
        source,
        "        files = YaapInstalldDexPatcher.applyToStageList(app, files, derivation)",
        "        files = YaapInstalldDexPatcher.applyToStageList(app, files, derivation, image.sdk)",
        "PrepareJob applyToStageList sdk",
    )


def patch_root_sh(source: str) -> str:
    source = replace_once(
        source,
        'IMAGES_SDK36="oxygenos16-cph2745"',
        'IMAGES_SDK36="oxygenos16-cph2745"\nIMAGES_SDK35=""',
        "oneos_root.sh IMAGES_SDK35",
    )
    source = replace_once(
        source,
        '        "a05 nothingos5-asteroids") echo nothing-a ;;',
        '''        "a05 nothingos5-asteroids") echo nothing-a ;;
        "a05 oxygenos16-cph2745") echo oxygen16 ;;
        "a05 hyperos-hongkong") echo hyper-hk ;;
        "a05 oneui95-s948b") echo oneui95 ;;''',
        "oneos_root.sh a05 profile_set choices",
    )
    source = replace_once(
        source,
        """image_sdk() { # <image id>
    if in_list "$1" "$IMAGES_SDK36"; then echo 36; else echo "$IMAGE_SDK"; fi
}
check_table() {""",
        """image_sdk() { # <image id>
    if in_list "$1" "$IMAGES_SDK35"; then echo 35
    elif in_list "$1" "$IMAGES_SDK36"; then echo 36
    else echo "$IMAGE_SDK"; fi
}
check_table_subset() { # <table file> <staged host_installd.txt> <method count>
    awk -v mcount="$3" '
        BEGIN {
            split("createUserData setFirstBoot createAppData createAppDataBatched restoreconAppData fixupAppData getAppSize getUserSize getExternalSize getAppCrates getUserCrates controlDexOptBlocking mergeProfiles dumpProfiles copySystemProfile createProfileSnapshot linkNativeLibraryDirectory createOatDirs linkFile hashSecondaryDexFile invalidateMounts isQuotaSupported prepareAppProfile tryMountDataMirror getOdexVisibility createFsveritySetupAuthToken enableFsverity", req, " ")
            for (i in req) allow[req[i]] = 1
        }
        NR == FNR {
            if ($0 ~ /^#/ || NF < 3) next
            if ($1 in allow) { want[$1] = $3; nwant++ }
            next
        }
        FNR >= 5 && FNR <= 4 + mcount {
            if (NF != 3 || $2 !~ /^[1-9][0-9]*$/) { bad = 1; exit 1 }
            if ($1 in seen_n || $2 in seen_c) { bad = 1; exit 1 }
            seen_n[$1] = 1; seen_c[$2] = 1
            got[$1] = $3
        }
        END {
            if (bad || nwant != 27) exit 1
            for (k in want) {
                if (!(k in got) || got[k] != want[k]) exit 1
            }
        }
    ' "$2" "$1" 2>/dev/null
}
check_table() {""",
        "oneos_root.sh image_sdk & check_table_subset",
    )
    source = replace_once(
        source,
        '''    in_list "$(sed -n "5,$((n + 4))p" "$f" | sha256sum | cut -d' ' -f1)" "$ok" ||
        refuse "this phone's installd table differs from the one the OneOS jars carry"''',
        '''    in_list "$(sed -n "5,$((n + 4))p" "$f" | sha256sum | cut -d' ' -f1)" "$ok" ||
        check_table_subset "$f" "$STAGE/host_installd.txt" "$n" ||
        refuse "this phone's installd table differs from the one the OneOS jars carry"''',
        "oneos_root.sh check_table subset fallback",
    )
    source = replace_once(
        source,
        '''    model=$(getprop ro.product.model)
    case "$model" in "$1"*) ;; *) refuse "this phone ($model) is not a $1" ;; esac
    [ "$(getprop ro.product.device)" = "$2" ] || refuse "codename $(getprop ro.product.device), profile $M_PROFILE is $2"
    soc=$(getprop ro.soc.model)
    [ "$soc" = "MT6769V/CZ" ] && soc=MT6768
    [ "$soc" = "$3" ] || refuse "chip $soc, profile $M_PROFILE is $3"''',
        '''    model=$(getprop ro.product.model)
    vmodel=$(getprop ro.product.vendor.model)
    case "$model" in "$1"*) ;; *) case "$vmodel" in "$1"*) ;; *) refuse "this phone ($model / $vmodel) is not a $1" ;; esac ;; esac
    dev=$(getprop ro.product.device)
    vdev=$(getprop ro.product.vendor.device)
    [ "$dev" = "$2" ] || [ "$vdev" = "$2" ] || refuse "codename ${dev:-$vdev}, profile $M_PROFILE is $2"
    soc=$(getprop ro.soc.model)
    if [ -z "$soc" ]; then
        case "$(getprop ro.board.platform)" in
            mt6768|MT6768) soc=MT6768 ;;
            taro) soc=SM8450 ;;
            kalama) soc=SM8550 ;;
            pineapple) soc=SM8650 ;;
            sun) soc=SM8750 ;;
            canoe) soc=SM8850 ;;
        esac
    fi
    [ "$soc" = "MT6769V/CZ" ] && soc=MT6768
    [ "$soc" = "$3" ] || refuse "chip $soc, profile $M_PROFILE is $3"''',
        "oneos_root.sh do_launch vendor & platform fallback",
    )
    return source


TARGETS = (
    (GATES, patch_gates),
    (CUSTOM_ROM, patch_custom_rom),
    (PROFILES, patch_profiles),
    (INSTALLD_TABLE, patch_installd_table),
    (APP_ASSETS, patch_app_assets),
    (PREPARE_JOB, patch_prepare_job),
    (ROOT_SH, patch_root_sh),
)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--check", action="store_true", help="validate anchors only")
    args = ap.parse_args()
    for rel, fn in TARGETS:
        path = args.root / rel
        original = path.read_text(encoding="utf-8")
        updated = fn(original)
        if updated == original:
            print("ALREADY PATCHED", rel)
        elif args.check:
            print("CHECK OK", rel)
        else:
            path.write_text(updated, encoding="utf-8", newline="\n")
            print("PATCHED", rel)


if __name__ == "__main__":
    main()
