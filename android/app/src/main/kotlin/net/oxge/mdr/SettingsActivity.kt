package net.oxge.mdr

import android.app.Activity
import android.os.Bundle
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Spinner
import android.widget.Switch
import android.widget.TextView

/**
 * The config screen: reading preferences, the tip jar, and About.
 *
 * Preferences are applied the next time a document renders — [MainActivity]
 * reads them in `onResume`, so a change here is visible on returning without
 * needing to reopen the file.
 */
class SettingsActivity : Activity() {

    private lateinit var prefs: Prefs
    private var billing: Billing? = null

    private lateinit var status: TextView
    private lateinit var tiers: LinearLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)
        setTitle(R.string.settings_title)
        actionBar?.setDisplayHomeAsUpEnabled(true)

        prefs = Prefs.from(this)
        status = findViewById(R.id.support_status)
        tiers = findViewById(R.id.tier_container)

        bindReadingPrefs()
        bindImagePrefs()
        findViewById<TextView>(R.id.about_version).text =
            getString(R.string.about_version, MdrCore.version.ifEmpty { "—" })

        billing = Billing(this) { render(it) }.also { it.start() }
    }

    override fun onDestroy() {
        billing?.stop()
        super.onDestroy()
    }

    override fun onOptionsItemSelected(item: android.view.MenuItem): Boolean {
        if (item.itemId == android.R.id.home) {
            finish()
            return true
        }
        return super.onOptionsItemSelected(item)
    }

    // --- reading preferences ---

    /**
     * The image policy section, hidden when the loaded core has no setters for
     * it. Showing switches that silently do nothing would be worse than not
     * offering them: the reader would conclude the feature is broken.
     */
    private fun bindImagePrefs() {
        val section = findViewById<LinearLayout>(R.id.images_section)
        if (!MdrCore.policySupported) {
            section.visibility = View.GONE
            return
        }
        val localHttp = findViewById<Switch>(R.id.local_http_switch)
        findViewById<Switch>(R.id.remote_images_switch).apply {
            isChecked = prefs.remoteImages
            setOnCheckedChangeListener { _, checked ->
                prefs.remoteImages = checked
                prefs.applyImagePolicy()
                // Plain-http is a narrowing of remote images, so it cannot
                // mean anything on its own.
                localHttp.isEnabled = checked
            }
        }
        localHttp.apply {
            isChecked = prefs.allowLocalHttp
            isEnabled = prefs.remoteImages
            setOnCheckedChangeListener { _, checked ->
                prefs.allowLocalHttp = checked
                prefs.applyImagePolicy()
            }
        }
    }

    private fun bindReadingPrefs() {
        findViewById<Switch>(R.id.toc_switch).apply {
            isChecked = prefs.showToc
            setOnCheckedChangeListener { _, checked -> prefs.showToc = checked }
        }

        val labels = listOf(
            R.string.lang_auto, R.string.lang_ja, R.string.lang_zh_hans,
            R.string.lang_zh_hant, R.string.lang_ko,
        ).map(::getString)

        findViewById<Spinner>(R.id.lang_spinner).apply {
            adapter = ArrayAdapter(this@SettingsActivity, android.R.layout.simple_spinner_dropdown_item, labels)
            setSelection(Prefs.langIndex(prefs.lang))
            onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
                override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                    prefs.lang = Prefs.LANG_TAGS[position]
                }

                override fun onNothingSelected(parent: AdapterView<*>?) = Unit
            }
        }
    }

    // --- tip jar ---

    private fun render(state: Billing.State) = runOnUiThread {
        when (state) {
            is Billing.State.Loading -> {
                status.visibility = View.VISIBLE
                status.setText(R.string.support_loading)
                tiers.removeAllViews()
            }

            is Billing.State.Unavailable -> {
                // Not an error the reader can act on: the app is still fully
                // usable, so this stays a quiet line rather than a dialog.
                status.visibility = View.VISIBLE
                status.setText(R.string.support_unavailable)
                tiers.removeAllViews()
            }

            is Billing.State.Ready -> {
                status.visibility = View.GONE
                tiers.removeAllViews()
                state.tiers.forEach { tier -> tiers.addView(buttonFor(tier)) }
            }

            is Billing.State.Thanks -> {
                status.visibility = View.VISIBLE
                status.setText(R.string.support_thanks)
                tiers.removeAllViews()
            }
        }
    }

    private fun buttonFor(tier: Billing.Tier): Button =
        Button(this, null, 0, R.style.TierButton).apply {
            // Play supplies the price already formatted for the storefront, so
            // this reads "¥300" in Japan and "$2.99" elsewhere without any
            // currency handling here.
            text = listOf(tier.label, tier.price).filter { it.isNotBlank() }.joinToString("  —  ")
            setOnClickListener { billing?.buy(tier) }
        }
}
