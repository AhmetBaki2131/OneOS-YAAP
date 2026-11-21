package com.fahadali.oneos.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/**
 * Device-free regression checks for the custom-ROM Android 15/16/17 patch.
 *
 * These tests confirm what we can verify before collecting real SDK 35/36
 * device logs. They DO NOT prove that a cross-version guest will boot.
 */
class AndroidHostMatrixTest {
    private fun report(sdk: Int, phase: GatePhase): GateReport {
        val profile = Profiles.S_ULTRA_8850
        val image = Images.FIND_X9U_IN_1105
        val facts = Fixtures.s26Ultra().copy(
            sdk = sdk,
            androidRelease = AndroidRelease.name(sdk),
        )
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
            installd = Bundles.S26U.installd,
            stage = staged,
            imageFile = ImageFileCheck(image.gzName, image.gzBytes, image.gzSha256, image.gzBytes),
            appVersionCode = 4,
        )
        return SwitchGates.evaluate(phase, input)
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
            assertFalse("SDK $sdk must not switch even after acknowledging warnings",
                switching.allows(switching.toTick.mapNotNull { it.tickKey }.toSet()))
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
}
