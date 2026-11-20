param(
    [string]$OneOsRoot = "c:\Users\Baki\Desktop\New folder\OneOS",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Replace-Exact {
    param([string]$RelPath, [string]$Old, [string]$New, [string]$Label)
    $relNorm = $RelPath -replace '\\', [System.IO.Path]::DirectorySeparatorChar
    $path = Join-Path $OneOsRoot $relNorm
    if (-not (Test-Path $path)) { throw "Missing target file: $path" }
    $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    $useCrlf = $raw.Contains("`r`n")
    $oldNorm = ($Old -replace "`r`n", "`n")
    $newNorm = ($New -replace "`r`n", "`n")
    if ($useCrlf) {
        $oldNorm = $oldNorm -replace "`n", "`r`n"
        $newNorm = $newNorm -replace "`n", "`r`n"
    }
    if ($raw.Contains($newNorm)) {
        Write-Host "[SKIP] $Label (already applied)"
        return
    }
    if (-not $raw.Contains($oldNorm)) {
        throw "[FAIL] ${Label}: expected anchor not found in $RelPath"
    }
    $updated = $raw.Replace($oldNorm, $newNorm)
    if ($DryRun) {
        Write-Host "[DRY-RUN OK] $Label -> $RelPath"
    } else {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($path, $updated, $utf8NoBom)
        Write-Host "[APPLIED] $Label -> $RelPath"
    }
}

# 1. Soc.kt: normalize MediaTek MT6769V/CZ -> MT6768 and map mt6768 -> MT6768 (Helio G85)
Replace-Exact "app-android\core\model\src\main\kotlin\com\fahadali\oneos\core\model\Soc.kt" `
@"
    private val PLATFORM_MODEL = mapOf(
        "taro" to "SM8450",
        "kalama" to "SM8550",
        "pineapple" to "SM8650",
        "sun" to "SM8750",
        "canoe" to "SM8850",
    )

    private val MARKETING = mapOf(
        "SM8450" to "Snapdragon 8 Gen 1",
        "SM8475" to "Snapdragon 8+ Gen 1",
        "SM8550" to "Snapdragon 8 Gen 2",
        "SM8650" to "Snapdragon 8 Gen 3",
        "SM8750" to "Snapdragon 8 Elite",
        "SM8850" to "Snapdragon 8 Elite Gen 5",
        "S5E9925" to "Exynos 2200",
        "S5E9945" to "Exynos 2400",
        "S5E9955" to "Exynos 2500",
    )
"@ `
@"
    private val MODEL_ALIAS = mapOf(
        "MT6769V/CZ" to "MT6768",
    )

    private val PLATFORM_MODEL = mapOf(
        "taro" to "SM8450",
        "kalama" to "SM8550",
        "pineapple" to "SM8650",
        "sun" to "SM8750",
        "canoe" to "SM8850",
        "mt6768" to "MT6768",
    )

    private val MARKETING = mapOf(
        "SM8450" to "Snapdragon 8 Gen 1",
        "SM8475" to "Snapdragon 8+ Gen 1",
        "SM8550" to "Snapdragon 8 Gen 2",
        "SM8650" to "Snapdragon 8 Gen 3",
        "SM8750" to "Snapdragon 8 Elite",
        "SM8850" to "Snapdragon 8 Elite Gen 5",
        "S5E9925" to "Exynos 2200",
        "S5E9945" to "Exynos 2400",
        "S5E9955" to "Exynos 2500",
        "MT6768" to "MediaTek Helio G85",
    )
"@ "Soc.kt MT6768 maps"

Replace-Exact "app-android\core\model\src\main\kotlin\com\fahadali\oneos\core\model\Soc.kt" `
@"
        val platform = p.platform.trim()
        val model = p.model.trim().ifEmpty {
            PLATFORM_MODEL[platform.lowercase(Locale.ROOT)].orEmpty()
        }
"@ `
@"
        val platform = p.platform.trim()
        val rawModel = p.model.trim()
        val model = MODEL_ALIAS[rawModel.uppercase(Locale.ROOT)] ?: rawModel.ifEmpty {
            PLATFORM_MODEL[platform.lowercase(Locale.ROOT)].orEmpty()
        }
"@ "Soc.kt resolve MT6769V/CZ alias"

# 2. CustomRom.kt: allow YAAP/AOSP Android 17 Samsung-hardware host when allowCustomAospHost=true
Replace-Exact "app-android\core\model\src\main\kotlin\com\fahadali\oneos\core\model\CustomRom.kt" `
@'
    fun check(s: Signals): Finding? {
        val oneUi = s.oneUiRaw.isNotBlank()
'@ `
@'
    fun check(s: Signals, allowCustomAospHost: Boolean = false): Finding? {
        val oneUi = s.oneUiRaw.isNotBlank()
'@ "CustomRom.kt signature"

Replace-Exact "app-android\core\model\src\main\kotlin\com\fahadali\oneos\core\model\CustomRom.kt" `
@'
        val sameModel = modelCode.isNotEmpty() && ((blSamsung && bootloaderOf(bl, modelFamily)) || vendorFamily == modelFamily)
        if (!oneUi && sameModel) {
            return finding(
                R_NOT_ONE_UI, "Custom ROM: not One UI",
                "This ${s.model} runs a system without One UI (no ro.build.version.oneui). OneOS runs next to stock " +
                    "One UI only, so it does not switch or send reports here.",
            )
        }
'@ `
@'
        val sameModel = modelCode.isNotEmpty() && ((blSamsung && bootloaderOf(bl, modelFamily)) || vendorFamily == modelFamily)
        if (!oneUi && sameModel) {
            if (allowCustomAospHost) {
                return Finding(
                    ID, Level.WARN, "Custom AOSP host (experimental YAAP mode)",
                    "This ${s.model} runs an AOSP-based ROM without ro.build.version.oneui. Switching requires YAAP-matched host_installd and HAL checks.",
                    R_NOT_ONE_UI,
                )
            }
            return finding(
                R_NOT_ONE_UI, "Custom ROM: not One UI",
                "This ${s.model} runs a system without One UI (no ro.build.version.oneui). OneOS runs next to stock " +
                    "One UI only, so it does not switch or send reports here.",
            )
        }
'@ "CustomRom.kt YAAP opt-in"

# 3. Profiles.kt: add Galaxy A05 (SM-A055 / a05m / MT6768)
Replace-Exact "app-android\core\model\src\main\kotlin\com\fahadali\oneos\core\model\Profiles.kt" `
@'
    const val ID_M35 = "m35"
    const val ID_A15_5G = "a15-5g"
'@ `
@'
    const val ID_M35 = "m35"
    const val ID_A15_5G = "a15-5g"
    const val ID_A05 = "a05"
'@ "Profiles.kt ID_A05"

Replace-Exact "app-android\core\model\src\main\kotlin\com\fahadali\oneos\core\model\Profiles.kt" `
@'
    val S_PLUS_8650 = S_8650.copy(id = ID_S_PLUS_8650, label = "Galaxy S24+", modelPrefix = "SM-S926", codename = "e2q")

    val BUILT_IN: List<PhoneProfile> = listOf(
'@ `
@'
    val S_PLUS_8650 = S_8650.copy(id = ID_S_PLUS_8650, label = "Galaxy S24+", modelPrefix = "SM-S926", codename = "e2q")

    /**
     * Galaxy A05 (SM-A055F, codename a05m, MediaTek MT6769V/CZ -> MT6768 Helio G85,
     * verified 2026-11-18: YAAP Android 17, vendor API 34, kernel 6.6.144, composer3 AIDL,
     * /sys/class/leds/lcd-backlight, KernelSU, installd 55 methods: 25/27 match + fsverity 52/53).
     */
    val A05 = PhoneProfile(
        id = ID_A05,
        label = "Galaxy A05",
        modelPrefix = "SM-A055",
        codename = "a05m",
        socModel = "MT6768",
        form = FormFactor.BAR,
        choices = listOf(X9U_IN_1105_CHOICE, INFINITYX_CHOICE, LINEAGE_CHOICE, HYPEROS_CHOICE, NOTHING_A_CHOICE),
        notes = listOf(MEDIATEK, olderVendor("34 (Android 14)", "6.6")),
    )

    val BUILT_IN: List<PhoneProfile> = listOf(
'@ "Profiles.kt A05 definition"

Replace-Exact "app-android\core\model\src\main\kotlin\com\fahadali\oneos\core\model\Profiles.kt" `
@'
        A55, S25_FE, S_8450, M55S, S_ULTRA_8450_JP, S_PLUS_9945, S_ULTRA_8550_JP, S_9925, A16_MTK, S_8550_JP, M35, A15_5G, S_PLUS_8650,
    )
'@ `
@'
        A55, S25_FE, S_8450, M55S, S_ULTRA_8450_JP, S_PLUS_9945, S_ULTRA_8550_JP, S_9925, A16_MTK, S_8550_JP, M35, A15_5G, S_PLUS_8650, A05,
    )
'@ "Profiles.kt BUILT_IN list"

# 4. ApkSeries.kt: register ID_A05 in S25 series
Replace-Exact "app-android\core\model\src\main\kotlin\com\fahadali\oneos\core\model\ApkSeries.kt" `
@'
            // 0.4.95: the Galaxy M35 5G (One UI 9) and the Galaxy A15 5G with MediaTek (One UI 8.5).
            Profiles.ID_M35, Profiles.ID_A15_5G,
        ),
'@ `
@'
            // 0.4.95: the Galaxy M35 5G (One UI 9) and the Galaxy A15 5G with MediaTek (One UI 8.5).
            Profiles.ID_M35, Profiles.ID_A15_5G,
            Profiles.ID_A05,
        ),
'@ "ApkSeries.kt A05"

# 5. InstalldTable.kt: semantic 27 ALLOWED-method verifier for AOSP/YAAP 17 hosts
Replace-Exact "app-android\core\model\src\main\kotlin\com\fahadali\oneos\core\model\InstalldTable.kt" `
@'
    fun problems(derived: InstalldDerivation?, expectedText: String? = null, sdk: Int = 37): List<String> {
        if (derived == null) return listOf("installd table not derived on this phone")
        if (!derived.ok) return listOf("installd table not derived: ${derived.error ?: "no methods"}")
        val p = mutableListOf<String>()
        val expected = expectedText?.let(::nonCommentLines)
        if (expected != null && Hashes.sha256(expected) != carried(sdk)) p += "the app's host_installd.txt is not the pinned table"
        val got = methodLines(derived.methods)
        val compatible = Hashes.sha256(got) in accepted(sdk)
        if (!compatible) p += "this phone's installd table differs from the one the OneOS files carry"
        if (expected != null && got != expected && !compatible) {
            val want = expected.removeSuffix("\n").split('\n').toSet()
            val have = got.removeSuffix("\n").split('\n').toSet()
            (have - want).take(5).forEach { p += "phone has: $it" }
            (want - have).take(5).forEach { p += "files expect: $it" }
        }
        return p.distinct()
    }
'@ `
@'
    /** The exact 27 AOSP methods routed by guest_installd_abi.py (slots 1..54 in host_installd.txt). */
    val ALLOWED_AOSP_37: Map<String, Pair<Int, String>> = mapOf(
        "createUserData" to (1 to "(Ljava/lang/String;III)V"),
        "setFirstBoot" to (3 to "()V"),
        "createAppData" to (4 to "(Landroid/os/CreateAppDataArgs;)Landroid/os/CreateAppDataResult;"),
        "createAppDataBatched" to (5 to "([Landroid/os/CreateAppDataArgs;)[Landroid/os/CreateAppDataResult;"),
        "restoreconAppData" to (7 to "(Ljava/lang/String;Ljava/lang/String;IIILjava/lang/String;)V"),
        "fixupAppData" to (12 to "(Ljava/lang/String;I)V"),
        "getAppSize" to (13 to "(Ljava/lang/String;[Ljava/lang/String;IIII[J[Ljava/lang/String;)[J"),
        "getUserSize" to (14 to "(Ljava/lang/String;II[I[I)[J"),
        "getExternalSize" to (15 to "(Ljava/lang/String;II[I)[J"),
        "getAppCrates" to (16 to "(Ljava/lang/String;[Ljava/lang/String;I)[Landroid/os/storage/CrateMetadata;"),
        "getUserCrates" to (17 to "(Ljava/lang/String;I)[Landroid/os/storage/CrateMetadata;"),
        "controlDexOptBlocking" to (21 to "(Z)V"),
        "mergeProfiles" to (23 to "(ILjava/lang/String;Ljava/lang/String;)I"),
        "dumpProfiles" to (24 to "(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Z)Z"),
        "copySystemProfile" to (25 to "(Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;)Z"),
        "createProfileSnapshot" to (29 to "(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;)Z"),
        "linkNativeLibraryDirectory" to (33 to "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;I)V"),
        "createOatDirs" to (34 to "(Ljava/lang/String;Ljava/lang/String;Ljava/util/List;)V"),
        "linkFile" to (35 to "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V"),
        "hashSecondaryDexFile" to (39 to "(Ljava/lang/String;Ljava/lang/String;ILjava/lang/String;I)[B"),
        "invalidateMounts" to (40 to "()V"),
        "isQuotaSupported" to (41 to "(Ljava/lang/String;)Z"),
        "prepareAppProfile" to (42 to "(Ljava/lang/String;IILjava/lang/String;Ljava/lang/String;Ljava/lang/String;)Z"),
        "tryMountDataMirror" to (47 to "(Ljava/lang/String;)V"),
        "getOdexVisibility" to (51 to "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I"),
        "createFsveritySetupAuthToken" to (53 to "(Landroid/os/ParcelFileDescriptor;I)Landroid/os/IInstalld\$IFsveritySetupAuthToken;"),
        "enableFsverity" to (54 to "(Landroid/os/IInstalld\$IFsveritySetupAuthToken;Ljava/lang/String;Ljava/lang/String;)I"),
    )

    /**
     * YAAP 17 (SM-A055F, 55-method IInstalld) matches slots 1..51 (25 methods) byte-for-byte
     * and shifts only createFsveritySetupAuthToken (52 vs 53) & enableFsverity (53 vs 54).
     * Requires patching those 2 const/16 codes in guest services_patched.jar (patch_guest_installd_yaap.py).
     */
    val ALLOWED_YAAP_FSVERITY_37: Map<String, Pair<Int, String>> = mapOf(
        "createFsveritySetupAuthToken" to (52 to "(Landroid/os/ParcelFileDescriptor;I)Landroid/os/IInstalld\$IFsveritySetupAuthToken;"),
        "enableFsverity" to (53 to "(Landroid/os/IInstalld\$IFsveritySetupAuthToken;Ljava/lang/String;Ljava/lang/String;)I"),
    )

    fun allowedSubsetCompatible(derived: InstalldDerivation): Boolean {
        val byName = derived.methods.associateBy { it.name }
        val exact = ALLOWED_AOSP_37.all { (name, want) ->
            val got = byName[name] ?: return@all false
            got.code == want.first && got.signature == want.second
        }
        if (exact) return true
        return ALLOWED_AOSP_37.all { (name, want) ->
            val got = byName[name] ?: return@all false
            val yaapShift = ALLOWED_YAAP_FSVERITY_37[name]
            got.signature == want.second && (got.code == want.first || (yaapShift != null && got.code == yaapShift.first))
        }
    }

    fun needsYaapFsverityPatch(derived: InstalldDerivation?): Boolean {
        if (derived == null || !derived.ok) return false
        val byName = derived.methods.associateBy { it.name }
        return byName["createFsveritySetupAuthToken"]?.code == 52 && byName["enableFsverity"]?.code == 53
    }

    fun problems(
        derived: InstalldDerivation?,
        expectedText: String? = null,
        sdk: Int = 37,
        allowAospAllowedMatch: Boolean = false,
    ): List<String> {
        if (derived == null) return listOf("installd table not derived on this phone")
        if (!derived.ok) return listOf("installd table not derived: ${derived.error ?: "no methods"}")
        val p = mutableListOf<String>()
        val expected = expectedText?.let(::nonCommentLines)
        if (expected != null && Hashes.sha256(expected) != carried(sdk)) p += "the app's host_installd.txt is not the pinned table"
        val got = methodLines(derived.methods)
        val compatible = Hashes.sha256(got) in accepted(sdk) ||
            (allowAospAllowedMatch && sdk == 37 && allowedSubsetCompatible(derived))
        if (!compatible) p += "this phone's installd table differs from the one the OneOS files carry"
        if (expected != null && got != expected && !compatible) {
            val want = expected.removeSuffix("\n").split('\n').toSet()
            val have = got.removeSuffix("\n").split('\n').toSet()
            (have - want).take(5).forEach { p += "phone has: $it" }
            (want - have).take(5).forEach { p += "files expect: $it" }
        }
        return p.distinct()
    }
'@ "InstalldTable.kt AOSP allowed equivalence"

# 6. Gates.kt: plumb allowCustomAospHost cleanly
Replace-Exact "app-android\core\model\src\main\kotlin\com\fahadali\oneos\core\model\Gates.kt" `
@'
    val allowScreenLock: Boolean = false,
)
'@ `
@'
    val allowScreenLock: Boolean = false,
    val allowCustomAospHost: Boolean = false,
)
'@ "Gates.kt GateInput field"

Replace-Exact "app-android\core\model\src\main\kotlin\com\fahadali\oneos\core\model\Gates.kt" `
@'
        // 0.4.74: no switching on a custom ROM ([CustomRomRule]).
        f.customRom?.let { out += Gate(it) }
'@ `
@'
        // 0.4.74: no switching on a custom ROM unless experimental YAAP/AOSP host mode is enabled.
        CustomRomRule.check(
            CustomRomRule.Signals(f.model, f.bootloader, f.vendorModel, f.oneUiRaw),
            allowCustomAospHost = input.allowCustomAospHost,
        )?.let { out += Gate(it) }
'@ "Gates.kt CustomRomRule check"

Replace-Exact "app-android\core\model\src\main\kotlin\com\fahadali\oneos\core\model\Gates.kt" `
@'
        val p = InstalldExpected.problems(input.installd, if (sdk == 36) input.expectedInstalldA16 else input.expectedInstalld, sdk)
'@ `
@'
        val p = InstalldExpected.problems(
            input.installd,
            if (sdk == 36) input.expectedInstalldA16 else input.expectedInstalld,
            sdk,
            allowAospAllowedMatch = input.allowCustomAospHost,
        )
'@ "Gates.kt InstalldExpected call"

# 7. switcher/assets/oneos_switch.sh: skip Samsung imsd loop on non-OneUI hosts + locale fallback
Replace-Exact "switcher\assets\oneos_switch.sh" `
@'
if ! pidof imsd >/dev/null 2>&1; then
    setprop ctl.start imsd 2>/dev/null || true
fi
'@ `
@'
HAS_IMSD=0
if [ -n "$(getprop init.svc.imsd 2>/dev/null)" ] || [ -x /vendor/bin/imsd ] || [ -x /system/bin/imsd ]; then
    HAS_IMSD=1
    if ! pidof imsd >/dev/null 2>&1; then
        setprop ctl.start imsd 2>/dev/null || true
    fi
fi
'@ "oneos_switch.sh imsd guard"

Replace-Exact "switcher\assets\oneos_switch.sh" `
@'
if ! ps -ef 2>/dev/null | grep -v grep | grep -q "ims_watchdog.sh"; then
'@ `
@'
if [ "$HAS_IMSD" = 1 ] && ! ps -ef 2>/dev/null | grep -v grep | grep -q "ims_watchdog.sh"; then
'@ "oneos_switch.sh ims_watchdog guard"

Replace-Exact "switcher\assets\oneos_switch.sh" `
@'
if [ -z "$GL" ]; then
    GL=$(settings get system system_locales 2>/dev/null | head -n 1 | cut -d, -f1) GLW="One UI's language"
    case "$GL" in ''|null|-*|*[!A-Za-z0-9-]*) GL="" ;; esac
fi
'@ `
@'
if [ -z "$GL" ]; then
    GL=$(settings get system system_locales 2>/dev/null | head -n 1 | cut -d, -f1) GLW="Host language"
    case "$GL" in ''|null|-*|*[!A-Za-z0-9-]*) GL="" ;; esac
fi
if [ -z "$GL" ]; then
    GL=$(getprop ro.product.locale 2>/dev/null) GLW="Host ro.product.locale"
    case "$GL" in ''|null|-*|*[!A-Za-z0-9-]*) GL="" ;; esac
fi
'@ "oneos_switch.sh locale fallback"

# 8. switcher/assets/guest_start.sh: stop composer check wait quickly if host uses HIDL composer@2.x
Replace-Exact "switcher\assets\guest_start.sh" `
@'
    while [ $n -lt 15 ] && ! service check android.hardware.graphics.composer3.IComposer/default 2>/dev/null | grep -q ': found'; do
        n=$((n + 1)); sleep 0.1
    done
'@ `
@'
    while [ $n -lt 15 ] && \
          ! service check android.hardware.graphics.composer3.IComposer/default 2>/dev/null | grep -q ': found' && \
          ! lshal list -i 2>/dev/null | grep -qE 'android\.hardware\.graphics\.composer@[0-9.]+::IComposer/'; do
        n=$((n + 1)); sleep 0.1
    done
'@ "guest_start.sh HIDL composer wait"

# 9. YaapInstalldDexPatcher.kt: copy runtime DEX remapper for YAAP 52/53 fsverity shift
$patcherSrc = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "YaapInstalldDexPatcher.kt"
$patcherRel = "app-android/app/src/full/kotlin/com/fahadali/oneos/session/YaapInstalldDexPatcher.kt" -replace '/', [System.IO.Path]::DirectorySeparatorChar
$patcherDst = Join-Path $OneOsRoot $patcherRel
if (-not (Test-Path $patcherSrc)) { throw "Missing $patcherSrc" }
if ($DryRun) {
    Write-Host "[DRY-RUN OK] Copy YaapInstalldDexPatcher.kt -> app-android\app\src\full\kotlin\com\fahadali\oneos\session\YaapInstalldDexPatcher.kt"
} else {
    Copy-Item -Force $patcherSrc $patcherDst
    Write-Host "[APPLIED] Copied YaapInstalldDexPatcher.kt"
}

# 10. AppAssets.kt: use YAAP-remapped services_patched.jar from cache when fsverity is shifted
Replace-Exact "app-android\app\src\full\kotlin\com\fahadali\oneos\session\AppAssets.kt" `
@'
    /** Compare the stage with the selected channel snapshot, including its exact payload hashes. */
    fun expectedStageHashes(ctx: Context, set: PackageSet, profile: String): Map<String, String> =
        files(ctx, set, profile).associate { it.name to it.sha256 } + ("bin/oneos_root.sh" to BuildConfig.ROOT_SCRIPT_SHA256)
'@ `
@'
    /** Compare the stage with the selected channel snapshot, including its exact payload hashes (and YAAP fsverity remap). */
    fun expectedStageHashes(
        ctx: Context,
        set: PackageSet,
        profile: String,
        derivation: com.fahadali.oneos.core.model.InstalldDerivation? = null,
    ): Map<String, String> {
        val base = files(ctx, set, profile).associate { it.name to it.sha256 } + ("bin/oneos_root.sh" to BuildConfig.ROOT_SCRIPT_SHA256)
        if (!InstalldExpected.needsYaapFsverityPatch(derivation)) return base
        val origSha = base["services_patched.jar"] ?: return base
        val yaap = YaapInstalldDexPatcher.cachedMeta(ctx, origSha) ?: return base
        val out = base.toMutableMap()
        out["services_patched.jar"] = yaap.sha256
        val origGuards = base["guards.txt"]
        if (origGuards != null) {
            YaapInstalldDexPatcher.cachedGuardsMeta(ctx, origGuards, origSha)?.let {
                out["guards.txt"] = it.sha256
            }
        }
        return out
    }
'@ "AppAssets.kt expectedStageHashes YAAP"

Replace-Exact "app-android\app\src\full\kotlin\com\fahadali\oneos\session\AppAssets.kt" `
@'
    /** From the APK when it carries the file, else from the downloads ([SetDownloader]). */
    fun open(ctx: Context, f: Staged): InputStream {
        if (f.sha256 in packed(ctx)) return ctx.applicationContext.assets.open("oneos/files/${f.sha256}")
        val file = SetDownloader.cached(ctx, f) ?: throw Broken("${f.name} is not downloaded")
        return file.inputStream()
    }
'@ `
@'
    /** From the APK when it carries the file, YAAP cache, else downloads ([SetDownloader]). */
    fun open(ctx: Context, f: Staged): InputStream {
        if (f.sha256 in packed(ctx)) return ctx.applicationContext.assets.open("oneos/files/${f.sha256}")
        YaapInstalldDexPatcher.cachedFile(ctx, f.sha256, f.bytes)?.let { return it.inputStream() }
        val file = SetDownloader.cached(ctx, f) ?: throw Broken("${f.name} is not downloaded")
        return file.inputStream()
    }
'@ "AppAssets.kt open YAAP cache"

# 11. PrepareJob.kt: remap services_patched.jar after download when host YAAP fsverity is 52/53
Replace-Exact "app-android\app\src\full\kotlin\com\fahadali\oneos\session\PrepareJob.kt" `
@'
        val files = AppAssets.files(app, set, profile.id)
        val code = BuildConfig.VERSION_CODE.toString()
        val filesBytes = files.sumOf { it.bytes }
'@ `
@'
        var files = AppAssets.files(app, set, profile.id)
        val code = BuildConfig.VERSION_CODE.toString()
        var filesBytes = files.sumOf { it.bytes }
'@ "PrepareJob.kt mutable files/filesBytes"

Replace-Exact "app-android\app\src\full\kotlin\com\fahadali\oneos\session\PrepareJob.kt" `
@'
        // 3. begin.
        step(Step.BEGIN, "Making the stage OneOS's…")
'@ `
@'
        files = YaapInstalldDexPatcher.applyToStageList(app, files, derivation)
        filesBytes = files.sumOf { it.bytes }

        // 3. begin.
        step(Step.BEGIN, "Making the stage OneOS's…")
'@ "PrepareJob.kt applyToStageList"

# 12. StageCheck.kt: enable allowCustomAospHost and pass derivation into expectedStageHashes
Replace-Exact "app-android\app\src\full\kotlin\com\fahadali\oneos\session\StageCheck.kt" `
@'
        val expectedResult = runCatching {
            st.staged(profile)?.second?.let { AppAssets.expectedStageHashes(app, it, profile!!.id) }.orEmpty()
        }
        val expected = expectedResult.getOrDefault(emptyMap())
        val input = GateInput(
            facts = facts,
            screenLockSet = screenLock,
            allowScreenLock = SessionPrefs.allowScreenLock(app),
'@ `
@'
        val expectedResult = runCatching {
            st.staged(profile)?.second?.let { AppAssets.expectedStageHashes(app, it, profile!!.id, r.installd) }.orEmpty()
        }
        val expected = expectedResult.getOrDefault(emptyMap())
        val input = GateInput(
            facts = facts,
            screenLockSet = screenLock,
            allowScreenLock = SessionPrefs.allowScreenLock(app),
            allowCustomAospHost = true,
'@ "StageCheck.kt YAAP GateInput"

# 13. oneos_root.sh: add a05 profile_info/profile_set and YAAP 55-method installd table SHA
Replace-Exact "app-android\app\src\full\assets\root\oneos_root.sh" `
@'
INSTALLD_SHA=791e52c441b62944f88244a2610b9433c869c9c3916a49f43d14552de82280f2
'@ `
@'
INSTALLD_SHA=791e52c441b62944f88244a2610b9433c869c9c3916a49f43d14552de82280f2
INSTALLD_SHA_YAAP=1f1b94c0353fb2e69862a0f0411d70576a2bc8609e10c6788b425e0bdc41b874
'@ "oneos_root.sh INSTALLD_SHA_YAAP"

Replace-Exact "app-android\app\src\full\assets\root\oneos_root.sh" `
@'
        m35) echo "SM-M356 m35x s5e8835 bar" ;;
        a15-5g) echo "SM-A156 a15x MT6835 bar" ;;
        *) return 1 ;;
'@ `
@'
        m35) echo "SM-M356 m35x s5e8835 bar" ;;
        a15-5g) echo "SM-A156 a15x MT6835 bar" ;;
        a05) echo "SM-A055 a05m MT6768 bar" ;;
        *) return 1 ;;
'@ "oneos_root.sh profile_info a05"

Replace-Exact "app-android\app\src\full\assets\root\oneos_root.sh" `
@'
        "a15-5g oxygenos16-cph2745") echo oxygen16 ;;
        *) return 1 ;;
'@ `
@'
        "a15-5g oxygenos16-cph2745") echo oxygen16 ;;
        "a05 coloros17-findx9u-in-1105") echo x9u-in-1105-sultra ;;
        "a05 infinityx41-findx9u") echo infinityx ;;
        "a05 lineage24-infiniti") echo lineage ;;
        "a05 hyperos-lhasa") echo hyper-f8u ;;
        "a05 nothingos5-asteroids") echo nothing-a ;;
        *) return 1 ;;
'@ "oneos_root.sh profile_set a05"

Replace-Exact "app-android\app\src\full\assets\root\oneos_root.sh" `
@'
    if [ "$(image_sdk "$2")" = 36 ]; then carried=$INSTALLD_SHA_36 ok=$INSTALLD_OK_36
    else carried=$INSTALLD_SHA ok=$INSTALLD_SHA; fi
'@ `
@'
    if [ "$(image_sdk "$2")" = 36 ]; then carried=$INSTALLD_SHA_36 ok=$INSTALLD_OK_36
    else carried=$INSTALLD_SHA ok="$INSTALLD_SHA $INSTALLD_SHA_YAAP"; fi
'@ "oneos_root.sh check_table YAAP ok"

Replace-Exact "app-android\app\src\full\assets\root\oneos_root.sh" `
@'
    [ "$(getprop ro.soc.model)" = "$3" ] || refuse "chip $(getprop ro.soc.model), profile $M_PROFILE is $3"
'@ `
@'
    soc=$(getprop ro.soc.model)
    [ "$soc" = "MT6769V/CZ" ] && soc=MT6768
    [ "$soc" = "$3" ] || refuse "chip $soc, profile $M_PROFILE is $3"
'@ "oneos_root.sh do_launch MT6769V/CZ alias"

# 14. switcher/assets/guest_prepare.sh: fallback to AOSP NetworkStack & CaptivePortalLogin on non-OneUI hosts
# On YAAP/AOSP hosts, /apex/com.android.tethering and /apex/com.android.cellbroadcast are signed with the host's
# networkstack key, while host APKs live under /system/priv-app/NetworkStack and /system/app/CaptivePortalLogin
# (not *Google). Without binding the host's NetworkStack over the guest's, PackageManagerService crashes
# system_server on first scan with Signature mismatch for sharedUserId android.uid.networkstack (UID 1073).
Replace-Exact "switcher\assets\guest_prepare.sh" `
@'
bind_host_app /system/priv-app/NetworkStackGoogle "$ROOTFS/system/priv-app/NetworkStack" com.google.android.networkstack
bind_host_app /system/app/CaptivePortalLoginGoogle "$ROOTFS/system/app/CaptivePortalLogin" com.google.android.captiveportallogin
'@ `
@'
HOST_NS=/system/priv-app/NetworkStackGoogle
HOST_NS_PKG=com.google.android.networkstack
if [ ! -d "$HOST_NS" ] && [ -d /system/priv-app/NetworkStack ]; then
    HOST_NS=/system/priv-app/NetworkStack
    HOST_NS_PKG=com.android.networkstack
fi
HOST_CP=/system/app/CaptivePortalLoginGoogle
HOST_CP_PKG=com.google.android.captiveportallogin
if [ ! -d "$HOST_CP" ] && [ -d /system/app/CaptivePortalLogin ]; then
    HOST_CP=/system/app/CaptivePortalLogin
    HOST_CP_PKG=com.android.captiveportallogin
fi
GUEST_NS="$ROOTFS/system/priv-app/NetworkStack"
[ ! -d "$GUEST_NS" ] && [ -d "$ROOTFS/system/priv-app/NetworkStackGoogle" ] && GUEST_NS="$ROOTFS/system/priv-app/NetworkStackGoogle"
GUEST_CP="$ROOTFS/system/app/CaptivePortalLogin"
[ ! -d "$GUEST_CP" ] && [ -d "$ROOTFS/system/app/CaptivePortalLoginGoogle" ] && GUEST_CP="$ROOTFS/system/app/CaptivePortalLoginGoogle"
bind_host_app "$HOST_NS" "$GUEST_NS" "$HOST_NS_PKG"
bind_host_app "$HOST_CP" "$GUEST_CP" "$HOST_CP_PKG"
'@ "guest_prepare.sh AOSP NetworkStack/CaptivePortalLogin fallback"

# 15. switcher/assets/return_to_oneui.sh: AOSP Android 17 audioserver registers media.audio_policy after zygote/activity
Replace-Exact "switcher\assets\return_to_oneui.sh" `
@'
setprop ctl.start audioserver
wait_found media.audio_policy 20 || failsafe "One UI's audioserver did not register"
'@ `
@'
setprop ctl.start audioserver
DEFER_HOST_AUDIO=0
if [ ! -f /system/priv-app/imsservice/imsservice.apk ]; then
    if ! wait_found media.audio_policy 5; then
        [ "$(getprop init.svc.audioserver)" = running ] || failsafe "Host audioserver did not start"
        DEFER_HOST_AUDIO=1
        say "audio: AOSP host audioserver running; waiting for media.audio_policy after framework start"
    fi
else
    wait_found media.audio_policy 20 || failsafe "One UI's audioserver did not register"
fi
'@ "return_to_oneui.sh AOSP deferred audioserver start check"

Replace-Exact "switcher\assets\return_to_oneui.sh" `
@'
for name in vold SurfaceFlinger media.audio_policy media.audio_flinger installd; do
    wait_found "$name" 5 || failsafe "$name is not registered"
done
'@ `
@'
GATE_B_SVCS="vold SurfaceFlinger media.audio_policy media.audio_flinger installd"
[ "$DEFER_HOST_AUDIO" = 1 ] && GATE_B_SVCS="vold SurfaceFlinger installd"
for name in $GATE_B_SVCS; do
    wait_found "$name" 5 || failsafe "$name is not registered"
done
'@ "return_to_oneui.sh Gate B AOSP audio defer"

Replace-Exact "switcher\assets\return_to_oneui.sh" `
@'
    [ $up -gt 0 ] && [ $t -ge $((up + 30)) ] && break
    [ $up = 0 ] && [ $t -ge 180 ] && failsafe "user 0 not unlocked within 180 s"
done
'@ `
@'
    [ $up -gt 0 ] && [ $t -ge $((up + 30)) ] && break
    [ $up = 0 ] && [ $t -ge 180 ] && failsafe "user 0 not unlocked within 180 s"
done
if [ "$DEFER_HOST_AUDIO" = 1 ]; then
    for name in media.audio_policy media.audio_flinger; do
        wait_found "$name" 15 || failsafe "$name did not register after AOSP host framework start"
    done
    say "audio: AOSP host media.audio_policy and media.audio_flinger registered"
fi
'@ "return_to_oneui.sh post-framework AOSP audio verify"

# 16. switcher/assets/boot_status.sh & oneos_switch.sh: disable OneOSBootStatus z=2000000000 overlay and composer SIGSTOP on AOSP/MTK hosts
# On YAAP/AOSP hosts:
#  (a) SurfaceControl.getPhysicalDisplayIds() does not exist, so OneOSBootStatus crashes until guest DisplayManagerService
#      starts, and then draws an opaque "Launching into <OS>" layer at z=2,000,000,000 over the booted guest screen.
#  (b) logcat -b events does not emit boot_progress_enable_screen to the host reader, so OneOSBootStatus never auto-stops.
#  (c) SIGSTOP on MediaTek vendor.hwcomposer in oneos_boot_hold_display deadlocks return_to_oneui.sh teardown.
# GapSplashActivity already covers the pre-SurfaceFlinger transition cleanly.
Replace-Exact "switcher\assets\boot_status.sh" `
@'
oneos_boot_hold_display() {
    oneos_boot_ready || return 0
'@ `
@'
oneos_boot_hold_display() {
    [ -f /system/priv-app/imsservice/imsservice.apk ] || return 0
    oneos_boot_ready || return 0
'@ "boot_status.sh skip composer SIGSTOP on non-OneUI host"

Replace-Exact "switcher\assets\boot_status.sh" `
@'
    chmod 755 "$ONEOS_BOOT_DIR"; chmod 644 "$ONEOS_BOOT_DIR"/verbose "$ONEOS_BOOT_DIR"/title "$ONEOS_BOOT_DIR"/system_name "$ONEOS_BOOT_DIR"/icon.png 2>/dev/null
    /system/bin/sh /data/local/tmp/oneos/boot_status.sh supervise "$(cat "$ONEOS_BOOT_DIR/generation")" </dev/null >> "$ONEOS_BOOT_DIR/renderer.log" 2>&1 &
}
'@ `
@'
    chmod 755 "$ONEOS_BOOT_DIR"; chmod 644 "$ONEOS_BOOT_DIR"/verbose "$ONEOS_BOOT_DIR"/title "$ONEOS_BOOT_DIR"/system_name "$ONEOS_BOOT_DIR"/icon.png 2>/dev/null
    if [ ! -f /system/priv-app/imsservice/imsservice.apk ]; then
        touch "$ONEOS_BOOT_DIR/stop" 2>/dev/null
        return 0
    fi
    /system/bin/sh /data/local/tmp/oneos/boot_status.sh supervise "$(cat "$ONEOS_BOOT_DIR/generation")" </dev/null >> "$ONEOS_BOOT_DIR/renderer.log" 2>&1 &
}
'@ "boot_status.sh disable OneOSBootStatus overlay worker on non-OneUI host"

Replace-Exact "switcher\assets\oneos_switch.sh" `
@'
            setprop service.bootanim.exit 1
            kill -9 \$(pidof bootanimation) 2>/dev/null
'@ `
@'
            setprop service.bootanim.exit 1
            kill -9 \$(pidof bootanimation) 2>/dev/null
            touch $STAGE/data/oneos_bootui/stop 2>/dev/null
            pkill -f OneOSBootStatus 2>/dev/null
'@ "oneos_switch.sh UI Activator explicit OneOSBootStatus stop"

# 17. switcher/assets/guest_prepare.sh & return_to_oneui.sh:
#  (a) On AOSP/YAAP hosts, always keep host's com.android.cellbroadcast (even when the guest image ships
#      com.google.android.cellbroadcast*, as Nothing OS 5.0 does) so android.uid.networkstack has one signer.
#  (b) When binding host /system/priv-app/NetworkStack (com.android.networkstack) into a guest that only has
#      GoogleNetworkStack_permissions.xml (com.google.android.networkstack), bind host NetworkStack.xml over it.
#  (c) On in-place return, unlink stale /dev/socket/zygote and /dev/socket/usap_pool_primary (labeled socket_device:s0
#      by the guest) as root while Permissive so init does not hit avc: denied { unlink } under Enforcing.
Replace-Exact "switcher\assets\guest_prepare.sh" `
@'
    if [ "$NAME" = cellbroadcast ]; then
        case "$SRC" in
            */com.android.cellbroadcast.apex|*/com.android.cellbroadcast.capex)
                echo "cellbroadcast: the image's ${SRC##*/} is built from source, not Google's; One UI's module stays (android.uid.networkstack has one signer)"
                return 0 ;;
        esac
    fi
'@ `
@'
    if [ "$NAME" = cellbroadcast ]; then
        if [ ! -d /system/priv-app/NetworkStackGoogle ] && [ -d /system/priv-app/NetworkStack ]; then
            echo "cellbroadcast: AOSP host NetworkStack in use; host's cellbroadcast module stays (android.uid.networkstack has one signer)"
            return 0
        fi
        case "$SRC" in
            */com.android.cellbroadcast.apex|*/com.android.cellbroadcast.capex)
                echo "cellbroadcast: the image's ${SRC##*/} is built from source, not Google's; One UI's module stays (android.uid.networkstack has one signer)"
                return 0 ;;
        esac
    fi
'@ "guest_prepare.sh keep AOSP host cellbroadcast for all guest images"

Replace-Exact "switcher\assets\guest_prepare.sh" `
@'
bind_host_app "$HOST_NS" "$GUEST_NS" "$HOST_NS_PKG"
bind_host_app "$HOST_CP" "$GUEST_CP" "$HOST_CP_PKG"
'@ `
@'
bind_host_app "$HOST_NS" "$GUEST_NS" "$HOST_NS_PKG"
bind_host_app "$HOST_CP" "$GUEST_CP" "$HOST_CP_PKG"
if [ "$HOST_NS_PKG" = com.android.networkstack ] && [ -f /system/etc/permissions/NetworkStack.xml ]; then
    for gns_xml in "$ROOTFS/system/etc/permissions/NetworkStack.xml" "$ROOTFS/system/etc/permissions/GoogleNetworkStack_permissions.xml"; do
        if [ -f "$gns_xml" ]; then
            $BB mount --bind /system/etc/permissions/NetworkStack.xml "$gns_xml" &&
                echo "Host NetworkStack.xml -> $gns_xml"
            break
        fi
    done
fi
'@ "guest_prepare.sh bind host NetworkStack.xml over GoogleNetworkStack_permissions.xml"

Replace-Exact "switcher\assets\return_to_oneui.sh" `
@'
    if zs_bound "$f"; then zs_left="$zs_left $f"
    elif [ $n -gt 0 ]; then echo "Took the guest zygote's bind off $f"; fi
done
'@ `
@'
    if zs_bound "$f"; then zs_left="$zs_left $f"
    elif [ $n -gt 0 ]; then echo "Took the guest zygote's bind off $f"; fi
done
if [ -z "$zs_left" ]; then
    in_init_ns rm -f /dev/socket/zygote /dev/socket/usap_pool_primary /dev/socket/zygote_secondary /dev/socket/usap_pool_secondary 2>/dev/null || true
fi
'@ "return_to_oneui.sh remove guest socket_device zygote sockets before Enforcing init restart"

# 18. switcher/assets/guest_prepare.sh, guest_props.sh, oneos_switch.sh: ColorOS 17 Lite & stability optimization for Galaxy A05 (4 GB RAM)
Replace-Exact "switcher\assets\guest_prepare.sh" `
@'
    for d in "$GUEST_SYSTEM_EXT"/priv-app/NTCamera "$ROOTFS"/system/priv-app/NTCamera "$GUEST_PRODUCT"/priv-app/NTCamera; do
        [ -d "$d" ] && [ ! -L "$d" ] || continue
        $BB mount -t tmpfs -o ro,size=4k,mode=755 tmpfs "$d" && \
            echo "Hid guest ${d#"$ROOTFS"/} (Nothing's camera needs Nothing's camera HAL; $OCWHY; ONEOS_GUEST_OEM_CAMERA=1 keeps it)"
    done
fi
'@ `
@'
    for d in "$GUEST_SYSTEM_EXT"/priv-app/NTCamera "$ROOTFS"/system/priv-app/NTCamera "$GUEST_PRODUCT"/priv-app/NTCamera; do
        [ -d "$d" ] && [ ! -L "$d" ] || continue
        $BB mount -t tmpfs -o ro,size=4k,mode=755 tmpfs "$d" && \
            echo "Hid guest ${d#"$ROOTFS"/} (Nothing's camera needs Nothing's camera HAL; $OCWHY; ONEOS_GUEST_OEM_CAMERA=1 keeps it)"
    done
fi
# ColorOS 17 optimization on mid-range / 4 GB RAM phones (Galaxy A05):
# 1. Missing native library crashes: OplusLocationService crashes repeatedly on missing libaol_jni.oplus.so.
# 2. SystemUI ANR & black-screen on sleep: UMS (com.oplus.pantanal.ums / Fluid Cloud Seedling) blocks
#    SystemUI's MediaSeedlingBgThread for 8.5s during sleep, and SmartSideBar blocks ViewRootImpl on screen_off.
# 3. OPPO AI / telemetry / background bloat & Qualcomm-only services that fail or thrash kswapd0 on 4 GB RAM.
# 4. Heavy non-essential Google background apps (keep Play services, Play Store, Gboard, WebView, Trichrome, Dialer, Messages, Contacts).
if [ "${ONEOS_GUEST_COLOROS_LITE:-1}" = 1 ] && { [ -e "$ROOTFS/system/framework/oplus-services.jar" ] || [ -e "$GUEST_SYSTEM_EXT/framework/oplus-services.jar" ]; }; then
    co_hid=0
    for d in \
        "$GUEST_SYSTEM_EXT/app/OplusLocationService" \
        "$GUEST_SYSTEM_EXT/app/NtnSatApp" "$GUEST_SYSTEM_EXT/app/RsmcSatelliteAuth" "$GUEST_SYSTEM_EXT/app/TTSatelliteAuth" \
        "$GUEST_SYSTEM_EXT/app/Olc" "$GUEST_SYSTEM_EXT/app/OTrace" "$GUEST_SYSTEM_EXT/app/LogKit" \
        "$GUEST_SYSTEM_EXT/app/PowerMonitor" "$GUEST_SYSTEM_EXT/app/OTA" \
        "$GUEST_SYSTEM_EXT/app/OplusCommercialEngineerCamera" "$GUEST_SYSTEM_EXT/app/OplusCommercialEngineerMode" \
        "$GUEST_SYSTEM_EXT/app/OplusEngineerNetwork" "$GUEST_SYSTEM_EXT/app/NfcEngineerTest" "$GUEST_SYSTEM_EXT/app/BTtestmode" \
        "$GUEST_SYSTEM_EXT/app/QCC" "$GUEST_SYSTEM_EXT/app/QtiTelephonyService" "$GUEST_SYSTEM_EXT/app/ImsDataChannelService" \
        "$GUEST_SYSTEM_EXT/app/atfwd" "$GUEST_SYSTEM_EXT/app/workloadclassifier" \
        "$GUEST_SYSTEM_EXT/priv-app/DeepThinker" "$GUEST_SYSTEM_EXT/priv-app/StdID" "$GUEST_SYSTEM_EXT/priv-app/DFS" \
        "$GUEST_SYSTEM_EXT/priv-app/MoseyApp" "$GUEST_SYSTEM_EXT/priv-app/BeidouMsgService" "$GUEST_SYSTEM_EXT/priv-app/UpgradeGuide" \
        "$GUEST_SYSTEM_EXT/priv-app/dcf" "$GUEST_SYSTEM_EXT/priv-app/dpmserviceapp" "$GUEST_SYSTEM_EXT/priv-app/ims" \
        "$GUEST_SYSTEM_EXT/priv-app/qcrilmsgtunnel" "$GUEST_SYSTEM_EXT/priv-app/xrcbservice" "$GUEST_SYSTEM_EXT/priv-app/xrvdservice" \
        "$ROOTFS/system/app/AppSearchAiSealConfig" "$ROOTFS/system/app/CrossDeviceServiceBroker" \
        "$ROOTFS/my_stock/priv-app/UMS" "$ROOTFS/my_stock/app/SmartSideBar" "$ROOTFS/my_stock/app/AssistantScreen" \
        "$ROOTFS/my_stock/app/CardService" "$ROOTFS/my_stock/app/FloatAssistant" "$ROOTFS/my_stock/app/AIMemory" \
        "$ROOTFS/my_stock/app/AIWriter" "$ROOTFS/my_stock/app/ARCore" "$ROOTFS/my_stock/app/BaseOcrScanner" \
        "$ROOTFS/my_stock/app/Gleaner" "$ROOTFS/my_stock/app/Instant" "$ROOTFS/my_stock/app/Karaoke" \
        "$ROOTFS/my_stock/app/KeKePay" "$ROOTFS/my_stock/app/LocationProxy" "$ROOTFS/my_stock/app/MCS" \
        "$ROOTFS/my_stock/app/MSPService" "$ROOTFS/my_stock/app/OpenCapabilityService" "$ROOTFS/my_stock/app/OplusOperationManual" \
        "$ROOTFS/my_stock/app/OplusPhoneActivation" "$ROOTFS/my_stock/app/Pictorial" "$ROOTFS/my_stock/app/RomUpdate" \
        "$ROOTFS/my_stock/app/SceneMode" "$ROOTFS/my_stock/app/SecurePay" "$ROOTFS/my_stock/app/SmartEngine" \
        "$ROOTFS/my_stock/app/SoftsimRedteaRoaming" "$ROOTFS/my_stock/app/ColorDirectService" \
        "$ROOTFS/my_stock/priv-app/AISeal" "$ROOTFS/my_stock/priv-app/AIUnit" "$ROOTFS/my_stock/priv-app/aiassistant" \
        "$ROOTFS/my_stock/priv-app/ContentPortal" "$ROOTFS/my_stock/priv-app/Cota" "$ROOTFS/my_stock/priv-app/DCS" \
        "$ROOTFS/my_stock/priv-app/DRS" "$ROOTFS/my_stock/priv-app/DSF" "$ROOTFS/my_stock/priv-app/DeviceHub" \
        "$ROOTFS/my_stock/priv-app/DeviceIntegrationService" "$ROOTFS/my_stock/priv-app/GlobalDrag" "$ROOTFS/my_stock/priv-app/GlobalSearch" \
        "$ROOTFS/my_stock/priv-app/HeyCast" "$ROOTFS/my_stock/priv-app/KeKeMarket" "$ROOTFS/my_stock/priv-app/KeKeUserCenter" \
        "$ROOTFS/my_stock/priv-app/KeKeUserCenterAccount" "$ROOTFS/my_stock/priv-app/LinktoWindows" "$ROOTFS/my_stock/priv-app/MDSService" \
        "$ROOTFS/my_stock/priv-app/Matrix" "$ROOTFS/my_stock/priv-app/Metis" "$ROOTFS/my_stock/priv-app/MyDevices" \
        "$ROOTFS/my_stock/priv-app/NumberRecognition" "$ROOTFS/my_stock/priv-app/OPSynergy" "$ROOTFS/my_stock/priv-app/OShare" \
        "$ROOTFS/my_stock/priv-app/OplusBootReg" "$ROOTFS/my_stock/priv-app/OplusGames" "$ROOTFS/my_stock/priv-app/SandboxRuntime" \
        "$ROOTFS/my_stock/priv-app/SceneService" "$ROOTFS/my_stock/priv-app/SecurityGuard" "$ROOTFS/my_stock/priv-app/Shelper" \
        "$ROOTFS/my_stock/priv-app/StdSP" "$ROOTFS/my_stock/priv-app/dmp" \
        "$ROOTFS/my_product/app/AONService" "$ROOTFS/my_product/app/Facebook-appmanager" "$ROOTFS/my_product/app/GPay3" \
        "$ROOTFS/my_product/app/Gmail2" "$ROOTFS/my_product/app/GoogleGemini" "$ROOTFS/my_product/app/GoogleLens" \
        "$ROOTFS/my_product/app/GoogleLocationHistory" "$ROOTFS/my_product/app/GoogleWallet" "$ROOTFS/my_product/app/Maps" \
        "$ROOTFS/my_product/app/Meet" "$ROOTFS/my_product/app/Photos" "$ROOTFS/my_product/app/SpeechServicesByGoogle" \
        "$ROOTFS/my_product/app/SwitchAccess" "$ROOTFS/my_product/app/YandexKeyboardV" "$ROOTFS/my_product/app/YouTube" \
        "$ROOTFS/my_product/app/clouddpc" "$ROOTFS/my_product/app/talkback" \
        "$ROOTFS/my_product/priv-app/AICallAssistant" "$ROOTFS/my_product/priv-app/AICore" "$ROOTFS/my_product/priv-app/AndroidAutoStub" \
        "$ROOTFS/my_product/priv-app/AndroidSystemIntelligence_Features" "$ROOTFS/my_product/priv-app/CrossDeviceServicesStub" \
        "$ROOTFS/my_product/priv-app/Facebook-installer" "$ROOTFS/my_product/priv-app/Facebook-services" \
        "$ROOTFS/my_product/priv-app/FamilyLinkParentalControls" "$ROOTFS/my_product/priv-app/GoogleOdad" \
        "$ROOTFS/my_product/priv-app/GoogleRestore" "$ROOTFS/my_product/priv-app/GoogleVelvet_CTS" \
        "$ROOTFS/my_product/priv-app/HotwordEnrollmentXGoogleHEXAGON_WIDEBAND.apk" \
        "$ROOTFS/my_product/priv-app/HotwordEnrollmentYGoogleHEXAGON_WIDEBAND.apk" \
        "$ROOTFS/my_product/priv-app/PersonalSafety" "$ROOTFS/my_product/priv-app/PrivateComputeServices" \
        "$ROOTFS/my_product/priv-app/RemoteControl" "$ROOTFS/my_product/priv-app/SearchSelector" \
        "$ROOTFS/my_product/priv-app/SystemClone" "$ROOTFS/my_product/priv-app/Wellbeing"; do
        [ -d "$d" ] && [ ! -L "$d" ] || continue
        $BB mount -t tmpfs -o ro,size=4k,mode=755 tmpfs "$d" && co_hid=$((co_hid + 1))
    done
    for d in "$ROOTFS"/my_*/del-app/* "$GUEST_SYSTEM_EXT"/app/SubsysPlugins_plugin_* "$GUEST_SYSTEM_EXT"/app/NetworkSense_plugin_* "$GUEST_SYSTEM_EXT"/app/NetworkAssistSys_plugin_*; do
        [ -d "$d" ] && [ ! -L "$d" ] || continue
        $BB mount -t tmpfs -o ro,size=4k,mode=755 tmpfs "$d" && co_hid=$((co_hid + 1))
    done
    echo "ColorOS Lite optimization: hid $co_hid non-essential AI/Google/OEM/crashing service folders"
fi
'@ "guest_prepare.sh ColorOS 17 Lite optimization"

Replace-Exact "switcher\assets\guest_props.sh" `
@'
            sed -i "/^$key=/d" "$NEW"
            echo "$key=0" >> "$NEW"
            echo "guest_props: $key=0 for the session (no first-boot clock reset to 1 January)"
        fi
    fi
'@ `
@'
            sed -i "/^$key=/d" "$NEW"
            echo "$key=0" >> "$NEW"
            echo "guest_props: $key=0 for the session (no first-boot clock reset to 1 January)"
        fi
        # ColorOS 17 performance & log optimization on mid-range / non-OPPO ART hosts:
        # 1. sys.gcsupression.optimize.enable=false stops OplusShellTransition from failing on missing
        #    VMRuntime.SupressionGC/DesupressionGC on every window transition.
        # 2. Silencing ANDR-PERF-CLIENT-SYS & [UAH_CLIENT] removes 3,200+ error log lines per session.
        # 3. Limiting background dex2oat threads to 2 keeps UI/SystemUI responsive on 4 GB RAM.
        for kv in sys.gcsupression.optimize.enable=false persist.sys.oplus.anim_level=2 \
                  dalvik.vm.dex2oat-threads=2 dalvik.vm.background-dex2oat-threads=1 \
                  log.tag.ANDR-PERF-CLIENT-SYS=S log.tag.UAH_CLIENT=S; do
            k=${kv%%=*}
            grep -qxF "$k" "$HOST" && continue
            sed -i "/^$(echo "$k" | sed 's/\./\\./g')=/d" "$NEW"
            echo "$kv" >> "$NEW"
        done
        echo "guest_props: ColorOS Lite props set (sys.gcsupression.optimize.enable=false, dex2oat-threads=2, ANDR-PERF-CLIENT-SYS/UAH_CLIENT silenced)"
    fi
'@ "guest_props.sh ColorOS 17 Lite props"

Replace-Exact "switcher\assets\oneos_switch.sh" `
@'
            # Once with the fixed panel curve: the saved value was chosen while the
            # curve was wrong (run 28: 1702 looked like ~420 nits, is ~15).
            [ -f $STAGE/data/.oneos_curve2 ] || { $BB nsenter -t \$PID -m /system/bin/sh /data/oneos_genv.sh /system/bin/settings put system screen_brightness 4570; touch $STAGE/data/.oneos_curve2; }
            fi
'@ `
@'
            # Once with the fixed panel curve: the saved value was chosen while the
            # curve was wrong (run 28: 1702 looked like ~420 nits, is ~15).
            [ -f $STAGE/data/.oneos_curve2 ] || { $BB nsenter -t \$PID -m /system/bin/sh /data/oneos_genv.sh /system/bin/settings put system screen_brightness 4570; touch $STAGE/data/.oneos_curve2; }
            # Prevent early screen-off sleep crash (OplusDisplayPowerControllerExtImpl.onGoToSleepFinish NPE)
            $BB nsenter -t \$PID -m /system/bin/sh /data/oneos_genv.sh /system/bin/settings put system screen_off_timeout 600000 2>/dev/null
            $BB nsenter -t \$PID -m /system/bin/sh /data/oneos_genv.sh /system/bin/svc power stayon true 2>/dev/null
            fi
'@ "oneos_switch.sh ColorOS screen_off_timeout and stayon"

# ---------------------------------------------------------------------------
# Patch 19: Galaxy A05 / ColorOS 17 fixes (SIM radio kick, camera ABI + WingCam,
# resolution/cutout, RAM, SD card).
# ---------------------------------------------------------------------------

# 19A: never restart rild on MediaTek ccci_mdinit phones.
Replace-Exact "switcher\assets\libsec-ril-patch.sh" `
@'
restart_ril() {
    /system/bin/setprop ctl.restart ril-daemon 2>/dev/null
'@ `
@'
# MediaTek (Galaxy A05): ccci_mdinit is oneshot, so a restarted rild never gets its modem back.
is_mtk_ccci() {
    [ -f /vendor/etc/init/init.ss_cccimdinit.rc ] && [ ! -x /vendor/bin/cbd ] && [ ! -x /vendor/bin/cpboot-daemon ]
}
restart_ril() {
    is_mtk_ccci && { echo "inbound SMS: MediaTek modem, rild not restarted"; return 0; }
    /system/bin/setprop ctl.restart ril-daemon 2>/dev/null
'@ "libsec-ril-patch.sh MediaTek guard (restart)"

Replace-Exact "switcher\assets\libsec-ril-patch.sh" `
@'
apply() {
    [ -f "$LIB" ] || {
'@ `
@'
apply() {
    is_mtk_ccci && { echo "inbound SMS: MediaTek modem, vendor RIL left alone"; return 0; }
    [ -f "$LIB" ] || {
'@ "libsec-ril-patch.sh MediaTek guard (apply)"

# 19B: patched One UI camera ABI must not be bound on non-One UI hosts (YAAP uses stock AOSP codes).
Replace-Exact "switcher\assets\guest_prepare.sh" `
@'
if [ -f "$STAGE/framework_patched.jar" ]; then
    $BB umount -l "$ROOTFS/system/framework/framework.jar" 2>/dev/null || true
'@ `
@'
if [ -f "$STAGE/framework_patched.jar" ] && { [ -f /system/priv-app/imsservice/imsservice.apk ] || [ -e "$GUEST_SYSTEM_EXT/framework/miui-services.jar" ] || [ -e "$ROOTFS/system_ext/framework/miui-services.jar" ]; }; then
    $BB umount -l "$ROOTFS/system/framework/framework.jar" 2>/dev/null || true
'@ "guest_prepare.sh framework_patched only on One UI hosts"

Replace-Exact "switcher\assets\guest_prepare.sh" `
@'
    if [ -f "$STAGE/${pair%%:*}" ]; then
        $BB umount -l "$ROOTFS/system/lib64/${pair#*:}" 2>/dev/null || true
'@ `
@'
    if [ -f "$STAGE/${pair%%:*}" ] && ! { [ ! -f /system/priv-app/imsservice/imsservice.apk ] && case "${pair%%:*}" in libcamera*) true ;; *) false ;; esac; }; then
        $BB umount -l "$ROOTFS/system/lib64/${pair#*:}" 2>/dev/null || true
'@ "guest_prepare.sh camera libs only on One UI hosts"

Replace-Exact "switcher\assets\guest_prepare.sh" `
@'
 || [ -d "$GUEST_SYSTEM_EXT/app/Aperture" ] || [ "$SAMCAM" = 1 ]; }; then
'@ `
@'
 || [ -d "$GUEST_SYSTEM_EXT/app/Aperture" ] || [ "$SAMCAM" = 1 ] || [ -f /system/priv-app/WingCam-N28/WingCam-N28.apk ]; }; then
'@ "guest_prepare.sh hide OplusCamera with WingCam"

# 19B/19D: ColorOS lite hide list additions, keep cellular plugins, stage WingCam as a system app.
Replace-Exact "switcher\assets\guest_prepare.sh" `
@'
        "$ROOTFS/my_stock/priv-app/StdSP" "$ROOTFS/my_stock/priv-app/dmp" \
'@ `
@'
        "$ROOTFS/my_stock/priv-app/StdSP" "$ROOTFS/my_stock/priv-app/dmp" \
        "$ROOTFS/my_stock/priv-app/PhoneManager" "$ROOTFS/my_stock/priv-app/AccessoryFramework" \
        "$GUEST_SYSTEM_EXT/app/SubsystemApp" "$GUEST_SYSTEM_EXT/app/NetworkHealthService" \
'@ "guest_prepare.sh Lite hide list RAM hogs"

Replace-Exact "switcher\assets\guest_prepare.sh" `
@'
 "$GUEST_SYSTEM_EXT"/app/NetworkSense_plugin_* "$GUEST_SYSTEM_EXT"/app/NetworkAssistSys_plugin_*; do
'@ `
@'
 "$GUEST_SYSTEM_EXT"/app/NetworkSense_plugin_*; do
'@ "guest_prepare.sh keep NetworkAssistSys plugins"

Replace-Exact "switcher\assets\guest_prepare.sh" `
@'
    echo "ColorOS Lite optimization: hid $co_hid non-essential AI/Google/OEM/crashing service folders"
fi
'@ `
@'
    echo "ColorOS Lite optimization: hid $co_hid non-essential AI/Google/OEM/crashing service folders"
fi
# YAAP's Samsung camera (WingCam-N28) as a ColorOS system app: stock AOSP camera ABI matches both
# hosts. Staged once on /data (too big for the 1 MB overlay tmpfs), bound over a hidden app folder.
WCAPK=/system/priv-app/WingCam-N28/WingCam-N28.apk
WCMP="$ROOTFS/my_stock/app/Karaoke"
if [ -f "$WCAPK" ] && [ -d "$WCMP" ] && [ -e "$ROOTFS/system/framework/oplus-services.jar" -o -e "$GUEST_SYSTEM_EXT/framework/oplus-services.jar" ]; then
    WCD="$STAGE/wingcam"; WCSTAMP=$(stat -c %s "$WCAPK" 2>/dev/null)
    if [ "$(cat "$WCD/.stamp" 2>/dev/null)" != "$WCSTAMP" ]; then
        rm -rf "$WCD"; mkdir -p "$WCD/lib/arm64"
        cp "$WCAPK" "$WCD/WingCam-N28.apk"
        for p in libBST libBSD_jni libBarcodeReader.quram libBstStick2D libFaceDetectCA libMTFilters libMTRefocus libMTSingleBokeh libSEF.quram libagifencoder.quram libdualAfter libexifa.camera.samsung libfloatingfeature libimagecodec.quram libjniBst libjni_imageutils libjpega.camera.samsung libmegface libmt_ libwingrefocusJni libwt_ libc++_shared libtensorflowlite_jni libRSSupport libblasV8 librsjni; do
            for f in /system/lib64/$p*.so; do [ -f "$f" ] && cp "$f" "$WCD/lib/arm64/"; done
        done
        chmod -R a+rX "$WCD"; $BB chcon -R u:object_r:system_file:s0 "$WCD" 2>/dev/null || true
        echo "$WCSTAMP" > "$WCD/.stamp"
    fi
    # A copy installed from /data would shadow the system app.
    rm -rf "$STAGE"/data/app/*/com.sec.android.app.camera-* 2>/dev/null
    $BB umount -l "$WCMP" 2>/dev/null || true
    if $BB mount --bind "$WCD" "$WCMP"; then
        $BB mount --make-rslave "$WCMP" 2>/dev/null || true
        echo "WingCam-N28 bound as ColorOS system app over ${WCMP#"$ROOTFS"/}"
    else
        echo "!!! WingCam-N28 bind failed"
    fi
fi
'@ "guest_prepare.sh WingCam staging"

# 19C: guest props for 720x1600.
Replace-Exact "switcher\assets\guest_props.sh" `
@'
        echo "guest_props: ColorOS Lite props set (sys.gcsupression.optimize.enable=false, dex2oat-threads=2, ANDR-PERF-CLIENT-SYS/UAH_CLIENT silenced)"
'@ `
@'
        echo "guest_props: ColorOS Lite props set (sys.gcsupression.optimize.enable=false, dex2oat-threads=2, ANDR-PERF-CLIENT-SYS/UAH_CLIENT silenced)"
        case "$(getprop ro.product.device)$(getprop ro.product.vendor.device)" in
            *a05m*)
                for kv in ro.oplus.resolution.high=720,1600 ro.oplus.resolution.low=720,1600 \
                          ro.oplus.density.fhd_default=300 ro.oplus.density.qhd_default=300; do
                    k=${kv%%=*}
                    grep -qxF "$k" "$HOST" && continue
                    sed -i "/^$(echo "$k" | sed 's/\./\\./g')=/d" "$NEW"
                    echo "$kv" >> "$NEW"
                done
                echo "guest_props: ColorOS 720x1600 @300 dpi props set (A05)" ;;
        esac
'@ "guest_props.sh A05 resolution props"

# 19C + helper script: host_statusbar for A05, and the fixes script itself.
Replace-Exact "switcher\assets\oneos_switch.sh" `
@'
# One UI's scale, for the guest's density (UI activator; standing rule: right on
'@ `
@'
# Galaxy A05 (720 x 1600): a small cutout so ColorOS apps do not reserve 160 px at the top.
case "$(getprop ro.product.device)$(getprop ro.product.vendor.device)" in
    *a05m*)
        { echo "spec=M -32,0 L -32,58 L 32,58 L 32,0 Z"; echo "height=66"; echo "radius=36"
          echo "hole=328,0:392,58"; echo "rect_px=328,0:392,58"; echo "hole_px=328,0:392,58"
        } > "$STAGE/host_statusbar"
        echo "328,0:392,58" > "$STAGE/host_screenhole"
        echo 36 > "$STAGE/host_corner_radius"
        echo "Host status bar: A05 fixed cutout written" ;;
esac
# Post-boot fixes for the guest (radio kick, WingCam permissions, RAM, SD card), started by the UI activator.
cat > "$STAGE/oneos_fixes.sh" <<'OSFIXEOF'
#!/system/bin/sh
PID=$1
STAGE=/data/local/tmp/oneos
BB=""
for c in /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do [ -x "$c" ] && { BB=$c; break; }; done
G() { $BB nsenter -t "$PID" -m /system/bin/sh /data/oneos_genv.sh "$@"; }
n=0; while [ $n -lt 30 ]; do G /system/bin/service check phone 2>/dev/null | grep -q ': found' && break; n=$((n+1)); sleep 1; done
sleep 3
# SIM: host radio is already ON, so the guest never saw radioStateChanged. Cycle it (no rild restart).
case "$(getprop gsm.sim.state)" in
    LOADED*|READY*)
        if [ "$(getprop ril.radiostate)" = 10 ] && G /system/bin/dumpsys isub 2>/dev/null | grep -q 'mSimState.*UNKNOWN'; then
            echo "radio kick: guest has no SIM state, cycling radio power"
            service call android.hardware.radio.modem.IRadioModem/slot1 16 i32 9001 i32 0 i32 0 i32 0
            sleep 2
            service call android.hardware.radio.modem.IRadioModem/slot1 16 i32 9002 i32 1 i32 0 i32 0
        fi ;;
esac
# RAM on 4 GB phones.
MT=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
if [ "${MT:-9999999}" -lt 5000000 ]; then
    for p in com.google.android.apps.chromecast.app com.heytap.store com.coloros.phonemanager com.heytap.accessory com.oplus.subsys com.oplus.nhs; do
        G /system/bin/pm disable-user --user 0 $p >/dev/null 2>&1
    done
    G /system/bin/device_config put activity_manager max_cached_processes 16 >/dev/null 2>&1
fi
# WingCam permissions.
n=0; while [ $n -lt 20 ]; do G /system/bin/pm path com.sec.android.app.camera 2>/dev/null | grep -q package && break; n=$((n+1)); sleep 1; done
if G /system/bin/pm path com.sec.android.app.camera 2>/dev/null | grep -q package; then
    for perm in CAMERA RECORD_AUDIO READ_PHONE_STATE READ_MEDIA_IMAGES READ_MEDIA_VIDEO POST_NOTIFICATIONS; do
        G /system/bin/pm grant com.sec.android.app.camera android.permission.$perm >/dev/null 2>&1
    done
    G /system/bin/appops set --user 0 com.sec.android.app.camera READ_PHONE_STATE allow >/dev/null 2>&1
    echo "WingCam permissions granted"
fi
# SD card: mount inside MediaProvider's own mount namespace only.
DEV=/dev/block/mmcblk1p1
if [ -b "$DEV" ]; then
    FST=$($BB blkid "$DEV" 2>/dev/null | sed -n 's/.*TYPE="\([^"]*\)".*/\1/p')
    [ -n "$FST" ] || FST=vfat
    MP=""; n=0
    while [ $n -lt 30 ] && [ -z "$MP" ]; do
        for d in /proc/[0-9]*; do
            [ "$(tr '\0' ' ' < $d/cmdline 2>/dev/null | cut -d' ' -f1)" = com.google.android.providers.media.module ] && { MP=${d#/proc/}; break; }
        done
        [ -n "$MP" ] || { n=$((n+1)); sleep 1; }
    done
    if [ -n "$MP" ] && ! grep -q ' /storage/emulated/0/SDCard ' /proc/$MP/mountinfo 2>/dev/null; then
        $BB nsenter -t "$MP" -m /system/bin/mkdir -p /storage/emulated/0/SDCard
        case "$FST" in
            vfat) OPTS=rw,nosuid,nodev,noexec,noatime,gid=1077,fmask=0007,dmask=0007,utf8,shortname=mixed ;;
            *) OPTS=rw,nosuid,nodev,noexec,noatime ;;
        esac
        $BB nsenter -t "$MP" -m $BB mount -t "$FST" -o "$OPTS" "$DEV" /storage/emulated/0/SDCard && echo "SD card ($FST) mounted for the guest"
    fi
fi
OSFIXEOF
chmod 755 "$STAGE/oneos_fixes.sh"
# One UI's scale, for the guest's density (UI activator; standing rule: right on
'@ "oneos_switch.sh A05 cutout + fixes script"

Replace-Exact "switcher\assets\oneos_switch.sh" `
@'
            $BB nsenter -t \$PID -m /system/bin/sh /data/oneos_genv.sh /system/bin/svc power stayon true 2>/dev/null
'@ `
@'
            $BB nsenter -t \$PID -m /system/bin/sh /data/oneos_genv.sh /system/bin/svc power stayon true 2>/dev/null
            ( $BB sh $STAGE/oneos_fixes.sh \$PID >> $STAGE/oneos_fixes.log 2>&1 & )
'@ "oneos_switch.sh launch fixes script"

Write-Host "Done."
