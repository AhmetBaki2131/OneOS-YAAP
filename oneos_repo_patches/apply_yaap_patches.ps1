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
        return base + ("services_patched.jar" to yaap.sha256)
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

Write-Host "Done."
