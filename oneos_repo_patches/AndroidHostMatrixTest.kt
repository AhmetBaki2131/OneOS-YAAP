package com.fahadali.oneos.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Device-free regression checks for Android 15/16/17 host compatibility across
 * stock One UI and custom ROMs (LineageOS, crDroid, EvolutionX, PixelOS, YAAP, One UI ports, GSIs).
 */
class AndroidHostMatrixTest {
    private val GRANTED_ROOT = RootSignals(
        managerPackages = listOf("me.weishu.kernelsu"),
        probe = SuProbeResult(
            SuState.GRANTED,
            0,
            "u:r:ksu:s0",
            "uid=0(root) gid=0(root) groups=0(root) context=u:r:ksu:s0",
        ),
    )

    private fun report(
        sdk: Int,
        phase: GatePhase,
        profile: PhoneProfile = Profiles.S_ULTRA_8850,
        image: ImageRef = Images.FIND_X9U_IN_1105,
        facts: DeviceFacts = Fixtures.s26Ultra(root = GRANTED_ROOT).copy(
            sdk = sdk,
            androidRelease = AndroidRelease.name(sdk),
        ),
        installd: InstalldDerivation? = Bundles.S26U.installd,
        allowCustomAospHost: Boolean = false,
    ): GateReport {
        val staged = StageState(
            mounts = emptyList(),
            activeBridges = emptyList(),
            sessionActive = false,
            marker = StageMarker(
                versionCode = 4,
                profileId = profile.id,
                imageId = image.id,
                setId = profile.choice(image.id)!!.packageSetId,
                createdEpoch = 1_792_000_000,
            ),
            filesVerified = true,
        )
        val input = GateInput(
            facts = facts,
            screenLockSet = false,
            oldSwitcherInstalled = false,
            installd = installd,
            stage = staged,
            imageFile = ImageFileCheck(image.gzName, image.gzBytes, image.gzSha256, image.gzBytes),
            appVersionCode = 4,
            allowCustomAospHost = allowCustomAospHost,
        )
        return SwitchGates.evaluate(phase, input)
    }

    private fun a05Facts(
        sdk: Int,
        model: String = "SM-A055F",
        vendorModel: String = "SM-A055F",
        oneUiRaw: String = "",
        bootloader: String = "A055FXXU6CXI1",
    ): DeviceFacts = Fixtures.s26Ultra(root = GRANTED_ROOT).let { base ->
        base.copy(
            model = model,
            device = "a05m",
            soc = SocInfo(SocVendor.MEDIATEK, "MT6768", "mt6768", "MediaTek Helio G85"),
            oneUiRaw = oneUiRaw,
            sdk = sdk,
            androidRelease = AndroidRelease.name(sdk),
            form = FormResult(FormFactor.BAR, FormFactor.BAR, false, null, false, listOf("test")),
            bootloader = bootloader,
            vendorModel = vendorModel,
        )
    }

    private fun derivationFrom(map: Map<String, Pair<Int, String>>, shift: Int = 0): InstalldDerivation =
        InstalldDerivation(
            methods = map.entries.map { (name, pair) -> InstalldMethod(name, pair.first + shift, pair.second) }
                .sortedBy { it.code },
            sourceJar = "/system/framework/services.jar",
            sourceEntry = "classes.dex",
            sourceSha256 = "0".repeat(64),
            inputs = listOf("/system/framework/services.jar!classes.dex"),
            error = null,
        )

    @Test
    fun galaxyA05GlobalAndLatamVariantsResolveOnAndroid15To17() {
        for (model in listOf("SM-A055F", "SM-A055M")) {
            val suffix = model.removePrefix("SM-")
            for (sdk in 35..37) {
                val facts = a05Facts(
                    sdk = sdk,
                    model = model,
                    vendorModel = model,
                    bootloader = suffix + "XXU1TEST",
                )
                val expected = if (model == "SM-A055M") Profiles.A05M else Profiles.A05
                val other = if (model == "SM-A055M") Profiles.A05 else Profiles.A05M
                val resolution = Profiles.resolve(facts)
                assertEquals("$model / Android $sdk profile", expected.id, resolution.profile?.id)
                assertTrue("$model / Android $sdk must match only its calibrated profile", expected.matches(facts))
                assertFalse("$model / Android $sdk must not match the other regional profile", other.matches(facts))
            }
        }
    }

    @Test
    fun android15And16CanPrepareButNotSwitchAndroid17Image() {
        for (sdk in listOf(35, 36)) {
            val preparation = report(sdk, GatePhase.PREPARE)
            assertEquals("SDK $sdk prepare Android", Level.WARN, preparation.find(SwitchGates.ID_ANDROID)?.level)
            assertEquals("SDK $sdk prepare installd", Level.WARN, preparation.find(SwitchGates.ID_INSTALLD)?.level)

            val switching = report(sdk, GatePhase.SWITCH)
            assertEquals("SDK $sdk switch Android", Level.BLOCK, switching.find(SwitchGates.ID_ANDROID)?.level)
            assertEquals("SDK $sdk switch installd", Level.BLOCK, switching.find(SwitchGates.ID_INSTALLD)?.level)
            assertFalse(
                "SDK $sdk must not switch even after acknowledging warnings",
                switching.allows(switching.toTick.mapNotNull { it.tickKey }.toSet()),
            )
        }
    }

    @Test
    fun android17RetainsExistingImageAndHostTableChecks() {
        for (phase in GatePhase.entries) {
            val result = report(37, phase)
            assertEquals("Android 17 gate", Level.OK, result.find(SwitchGates.ID_ANDROID)?.level)
            assertEquals("Android 17 installd", Level.OK, result.find(SwitchGates.ID_INSTALLD)?.level)
        }
    }

    @Test
    fun android16HostSupportsOxygen16OnCustomRomAndShiftedInstalld() {
        val shiftedA16 = derivationFrom(InstalldExpected.ALLOWED_AOSP_36, shift = 2)
        val stockA16 = derivationFrom(InstalldExpected.ALLOWED_AOSP_36, shift = 0)
        for ((label, installd, oneUi) in listOf(
            Triple("One UI 8.5", stockA16, "80500"),
            Triple("Custom A16 ROM", shiftedA16, ""),
        )) {
            val facts = a05Facts(sdk = 36, oneUiRaw = oneUi)
            for (phase in GatePhase.entries) {
                val res = report(
                    sdk = 36,
                    phase = phase,
                    profile = Profiles.A05,
                    image = Images.OXYGEN16,
                    facts = facts,
                    installd = installd,
                    allowCustomAospHost = true,
                )
                assertEquals("$label $phase Android", Level.OK, res.find(SwitchGates.ID_ANDROID)?.level)
                assertEquals("$label $phase installd", Level.OK, res.find(SwitchGates.ID_INSTALLD)?.level)
                assertFalse("$label $phase should not block", res.blocked)
            }
        }
    }

    @Test
    fun anyAndroid17CustomRomAndPortRomPassWithValidInstalld() {
        val shiftedA17 = derivationFrom(InstalldExpected.ALLOWED_AOSP_37, shift = 3)
        // Custom ROM spoofing model name (e.g., GSI / Pixel spoof), resolved via vendorModel
        val spoofedFacts = a05Facts(sdk = 37, model = "Pixel 9 Pro", vendorModel = "SM-A055F", oneUiRaw = "")
        assertEquals(Profiles.A05.id, Profiles.resolve(spoofedFacts).profile?.id)
        for (phase in GatePhase.entries) {
            val customRes = report(
                sdk = 37,
                phase = phase,
                profile = Profiles.A05,
                image = Images.FIND_X9U_IN_1105,
                facts = spoofedFacts,
                installd = shiftedA17,
                allowCustomAospHost = true,
            )
            assertEquals("Custom A17 $phase Android", Level.OK, customRes.find(SwitchGates.ID_ANDROID)?.level)
            assertEquals("Custom A17 $phase installd", Level.OK, customRes.find(SwitchGates.ID_INSTALLD)?.level)
            assertEquals("Custom A17 $phase customRom", Level.WARN, customRes.find(CustomRomRule.ID)?.level)
            assertFalse("Custom A17 $phase should not block", customRes.blocked)
        }

        // One UI port ROM reporting another model while hardware bootloader/vendor is A05
        val portFacts = a05Facts(sdk = 37, model = "SM-S948B", vendorModel = "SM-A055F", oneUiRaw = "90000")
        val portRes = report(
            sdk = 37,
            phase = GatePhase.SWITCH,
            profile = Profiles.A05,
            image = Images.FIND_X9U_IN_1105,
            facts = portFacts,
            installd = shiftedA17,
            allowCustomAospHost = true,
        )
        assertEquals("Port ROM customRom level", Level.WARN, portRes.find(CustomRomRule.ID)?.level)
        assertEquals("Port ROM installd", Level.OK, portRes.find(SwitchGates.ID_INSTALLD)?.level)
        assertFalse("Port ROM should not block", portRes.blocked)
    }

    @Test
    fun badInstalldSignatureOrMissingMethodBlocksAllSdks() {
        val badSig = derivationFrom(
            InstalldExpected.ALLOWED_AOSP_37 + ("invalidateMounts" to (40 to "(I)V")),
        )
        val missingMethod = derivationFrom(InstalldExpected.ALLOWED_AOSP_37 - "enableFsverity")

        for ((label, bad) in listOf("badSig" to badSig, "missing" to missingMethod)) {
            assertFalse("A17 $label", InstalldExpected.allowedSubsetCompatible(bad, 37))
            assertFalse("A16 $label", InstalldExpected.allowedSubsetCompatible(bad, 36))
            assertFalse("A15 $label", InstalldExpected.allowedSubsetCompatible(bad, 35))

            val r37 = report(37, GatePhase.SWITCH, Profiles.A05, Images.FIND_X9U_IN_1105, a05Facts(37), bad, true)
            assertEquals("A17 $label blocks", Level.BLOCK, r37.find(SwitchGates.ID_INSTALLD)?.level)

            val r36 = report(36, GatePhase.SWITCH, Profiles.A05, Images.OXYGEN16, a05Facts(36), bad, true)
            assertEquals("A16 $label blocks", Level.BLOCK, r36.find(SwitchGates.ID_INSTALLD)?.level)

            val r35 = report(35, GatePhase.SWITCH, Profiles.A05, Images.FIND_X9U_IN_1105, a05Facts(35), bad, true)
            assertEquals("A15 $label blocks", Level.BLOCK, r35.find(SwitchGates.ID_INSTALLD)?.level)
            assertTrue("A15 $label blocks switch", r35.blocked)
        }
    }
}
