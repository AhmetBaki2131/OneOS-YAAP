package com.fahadali.oneos.ui

import android.content.Intent
import android.graphics.drawable.Drawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Menu
import android.view.MenuItem
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import androidx.fragment.app.Fragment
import androidx.preference.Preference
import androidx.preference.PreferenceCategory
import androidx.preference.PreferenceFragmentCompat
import com.fahadali.oneos.R
import com.fahadali.oneos.core.model.SuProbeResult
import com.fahadali.oneos.core.model.SuState
import com.fahadali.oneos.core.model.Units
import com.fahadali.oneos.core.root.SuProbe
import com.fahadali.oneos.probe.ProbeSession
import dev.oneuiproject.oneui.R as OuiIcons
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Root-required, English-only entry point for OneOS Probe: checks `su -c id`
 * at launch and unlocks the read-only device report tools only after uid 0
 * is confirmed.
 */
internal object EditionHome {
    private fun enforceEnglish() {
        runCatching {
            val en = LocaleListCompat.forLanguageTags("en")
            if (AppCompatDelegate.getApplicationLocales().toLanguageTags() != "en") {
                AppCompatDelegate.setApplicationLocales(en)
            }
        }
    }

    fun onboarding(a: MainActivity): Intent {
        enforceEnglish()
        return Intent(a, BeforeYouStartActivity::class.java)
    }

    fun redirect(a: MainActivity): Intent? = null

    val layoutRes: Int get() = R.layout.activity_toolbar

    fun createFragment(): Fragment = ProbeRootGateFragment()

    /** OneOS Probe sends no usage count; ensure the UI stays in English. */
    fun started(a: MainActivity) {
        enforceEnglish()
    }

    fun created(a: MainActivity) = Unit

    fun createMenu(a: MainActivity, menu: Menu): Boolean = false

    fun menuItem(a: MainActivity, item: MenuItem): Boolean = false

    fun bind(f: PreferenceFragmentCompat) = Unit

    fun resume(f: PreferenceFragmentCompat) = Unit
}

/**
 * Home fragment for OneOS Probe that blocks all device report actions until
 * root access (uid 0) is verified.
 */
class ProbeRootGateFragment : PreferenceFragmentCompat() {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var checking = false
    private var rootResult: SuProbeResult? = null

    private val isRootGranted: Boolean
        get() = rootResult?.let { it.state == SuState.GRANTED && it.uid == 0 } == true

    override fun onCreatePreferences(savedInstanceState: Bundle?, rootKey: String?) {
        preferenceScreen = preferenceManager.createPreferenceScreen(preferenceManager.context)
        rootResult = savedInstanceState?.let(::restoreProbe)
        render()
        if (rootResult == null) {
            checkRoot()
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        rootResult?.let { p ->
            outState.putString(KEY_STATE, p.state.name)
            p.uid?.let { outState.putInt(KEY_UID, it) }
            outState.putString(KEY_CONTEXT, p.context)
            outState.putString(KEY_OUTPUT, p.output)
        }
    }

    override fun onStart() {
        super.onStart()
        render()
    }

    override fun onResume() {
        super.onResume()
        if (isRootGranted) {
            render()
        }
    }

    override fun onDestroy() {
        executor.shutdownNow()
        main.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private fun checkRoot() {
        if (checking) return
        checking = true
        render()
        executor.execute {
            val result = SuProbe.runId()
            main.post {
                checking = false
                rootResult = result
                if (isAdded) {
                    render()
                }
            }
        }
    }

    private fun render() {
        if (!isAdded) return
        val screen = preferenceScreen ?: return
        screen.removeAll()
        val toolbar = activity as? ToolbarActivity

        if (isRootGranted) {
            toolbar?.setExpandedSubtitle("Root granted · Device Report ready")
            val reportCat = category("Device Report")
            val ctxLabel = rootResult?.context?.takeIf { it.isNotBlank() }?.let { " ($it)" } ?: ""
            reportCat.row(
                title = "Root access granted",
                summary = "uid=0$ctxLabel. Read-only device report tools unlocked.",
                icon = icon(OuiIcons.drawable.ic_oui_checkbox_checked, R.color.verdict_ok),
            )
            reportCat.row(
                title = "Generate Device Report",
                summary = "Runs read-only root probes (getprop, services.jar IInstalld table, displays, HALs, SELinux) and builds a redacted ZIP report. Nothing on the phone is modified.",
                icon = icon(OuiIcons.drawable.ic_oui_labs_outline, R.color.verdict_ok),
                onClick = { startActivity(Intent(requireContext(), RunTestsActivity::class.java)) },
            )
            val zip = ProbeSession.latestZip(requireContext())
            val zipPref = reportCat.row(
                title = "View & Share Report ZIP",
                summary = if (zip != null) {
                    "${zip.name} (${Units.bytes(zip.length())}). Open to preview, Share, or Save to Downloads."
                } else {
                    "No device report generated yet. Tap Generate Device Report first."
                },
                icon = icon(
                    OuiIcons.drawable.ic_oui_file_type_zip,
                    if (zip != null) R.color.verdict_ok else R.color.verdict_info,
                ),
                onClick = if (zip != null) {
                    { startActivity(Intent(requireContext(), FindingsActivity::class.java)) }
                } else {
                    null
                },
            )
            zipPref.isEnabled = zip != null
            reportCat.row(
                title = "Quick Phone Summary",
                summary = "Model, chip, One UI, Android SDK, displays, root and storage overview.",
                icon = icon(OuiIcons.drawable.ic_oui_info_outline, R.color.verdict_info),
                onClick = { startActivity(Intent(requireContext(), DeviceReportActivity::class.java)) },
            )

            val appCat = category("OneOS Probe")
            appCat.row(
                title = "Before you start",
                summary = getString(R.string.before_link_summary),
                onClick = { startActivity(Intent(requireContext(), BeforeYouStartActivity::class.java)) },
            )
            appCat.row(
                title = "About OneOS Probe",
                summary = getString(R.string.home_about_summary),
                onClick = { startActivity(Intent(requireContext(), AboutActivity::class.java)) },
            )
            return
        }

        if (checking) {
            toolbar?.setExpandedSubtitle("Checking root access...")
            val cat = category("Root Check")
            cat.row(
                title = "Checking root permission...",
                summary = "Running su -c id. Allow OneOS Probe in Magisk, KernelSU or APatch if prompted.",
                icon = icon(OuiIcons.drawable.ic_oui_refresh, R.color.verdict_info),
            )
            return
        }

        toolbar?.setExpandedSubtitle("Root access required")
        val cat = category("Root Access Required")
        cat.row(
            title = "Root permission required",
            summary = "OneOS Probe cannot run or generate a device report without root access (uid 0).\n\n" +
                "${failureText(rootResult)}\n\n" +
                "Allow OneOS Probe in KernelSU, Magisk or APatch, then tap Retry root check.",
            icon = icon(OuiIcons.drawable.ic_oui_block, R.color.verdict_block),
        )
        cat.row(
            title = "Retry root check",
            summary = "Runs su -c id again after you grant root access to OneOS Probe.",
            icon = icon(OuiIcons.drawable.ic_oui_refresh, R.color.verdict_info),
            onClick = ::checkRoot,
        )
        cat.row(
            title = "Exit",
            summary = "Close OneOS Probe.",
            icon = icon(OuiIcons.drawable.ic_oui_error, R.color.verdict_block),
            onClick = { requireActivity().finishAffinity() },
        )
    }

    private fun failureText(p: SuProbeResult?): String = when (p?.state) {
        null -> "Root check has not completed yet."
        SuState.NOT_FOUND -> "su binary was not found or is hidden from OneOS Probe (${p.output.ifBlank { "not found" }})."
        SuState.DENIED -> "Root request was denied for OneOS Probe (${p.output.ifBlank { "no output" }})."
        SuState.TIMEOUT -> "Root manager did not answer in time for OneOS Probe."
        SuState.ERROR -> "Root check failed: ${p.output.ifBlank { "unknown error" }}."
        SuState.GRANTED -> "su did not return uid 0 (uid=${p.uid ?: "unknown"})."
    }

    private fun icon(res: Int, color: Int? = null): Drawable? {
        val ctx = requireContext()
        return ctx.getDrawable(res)?.mutate()?.apply { if (color != null) setTint(ctx.getColor(color)) }
    }

    private fun category(title: String): PreferenceCategory {
        val c = PreferenceCategory(preferenceManager.context)
        c.title = title
        c.isIconSpaceReserved = false
        preferenceScreen.addPreference(c)
        return c
    }

    private fun PreferenceCategory.row(
        title: CharSequence,
        summary: CharSequence?,
        icon: Drawable? = null,
        onClick: (() -> Unit)? = null,
    ): Preference {
        val p = Preference(context)
        p.title = title
        p.summary = summary
        p.icon = icon
        p.isIconSpaceReserved = icon != null
        if (onClick == null) {
            p.isSelectable = false
        } else {
            p.setOnPreferenceClickListener { onClick(); true }
        }
        addPreference(p)
        return p
    }

    private fun restoreProbe(b: Bundle): SuProbeResult? {
        val state = b.getString(KEY_STATE)?.let { runCatching { SuState.valueOf(it) }.getOrNull() } ?: return null
        return SuProbeResult(
            state = state,
            uid = if (b.containsKey(KEY_UID)) b.getInt(KEY_UID) else null,
            context = b.getString(KEY_CONTEXT),
            output = b.getString(KEY_OUTPUT).orEmpty(),
        )
    }

    private companion object {
        const val KEY_STATE = "probe_state"
        const val KEY_UID = "probe_uid"
        const val KEY_CONTEXT = "probe_context"
        const val KEY_OUTPUT = "probe_output"
    }
}
