import UIKit

/// The config screen: reading preferences, the tip jar, and About.
///
/// The counterpart of `SettingsActivity` on Android, as an inset-grouped table
/// in the iOS Settings idiom. Preferences are applied the next time a document
/// renders — `DocumentViewController` re-reads them in `viewWillAppear`, so a
/// change here is visible on returning without reopening the file.
@MainActor
final class SettingsViewController: UITableViewController {

    private let prefs: Prefs
    private let store: Store

    /// Current tip-jar state, mirrored into the table.
    private var storeState: Store.State = .loading

    private enum Section: Int, CaseIterable {
        case reading, support, about
    }

    /// `store` is constructed here rather than defaulted in the signature:
    /// `Store` is main-actor isolated, and Swift evaluates default arguments in
    /// a nonisolated context.
    init(prefs: Prefs = Prefs(), store: Store? = nil) {
        self.prefs = prefs
        self.store = store ?? Store()
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("settings_title", comment: "Settings")
        view.accessibilityIdentifier = "settingsScreen"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "settingsDoneButton"

        store.onState = { [weak self] state in
            guard let self = self else { return }
            self.storeState = state
            self.tableView.reloadSections(IndexSet(integer: Section.support.rawValue), with: .automatic)
        }
        store.start()
    }

    deinit {
        // `deinit` is not main-actor isolated; the store's teardown only
        // cancels tasks, so hop rather than block.
        let store = self.store
        Task { @MainActor in store.stop() }
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .reading: return NSLocalizedString("section_reading", comment: "Reading")
        case .support: return NSLocalizedString("section_support", comment: "Support the Developer")
        case .about: return NSLocalizedString("section_about", comment: "About")
        case .none: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .reading: return NSLocalizedString("pref_lang_summary", comment: "")
        case .support: return NSLocalizedString("support_blurb", comment: "")
        case .about: return NSLocalizedString("about_blurb", comment: "")
        case .none: return nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .reading:
            return 2
        case .support:
            // Either one status line, or one row per tier.
            switch storeState {
            case .ready(let tiers): return tiers.count
            case .loading, .unavailable, .thanks: return 1
            }
        case .about:
            return 1
        case .none:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default
        var content = cell.defaultContentConfiguration()

        switch Section(rawValue: indexPath.section) {
        case .reading:
            if indexPath.row == 0 {
                content.text = NSLocalizedString("pref_toc", comment: "Show table of contents")
                content.secondaryText = NSLocalizedString("pref_toc_summary", comment: "")
                let toggle = UISwitch()
                toggle.isOn = prefs.showToc
                toggle.accessibilityIdentifier = "tocSwitch"
                toggle.addTarget(self, action: #selector(tocChanged(_:)), for: .valueChanged)
                cell.accessoryView = toggle
                cell.selectionStyle = .none
            } else {
                content.text = NSLocalizedString("pref_lang", comment: "Document language")
                content.secondaryText = Prefs.langLabel(at: Prefs.langIndex(prefs.lang))
                cell.accessoryType = .disclosureIndicator
                cell.accessibilityIdentifier = "languageRow"
            }

        case .support:
            switch storeState {
            case .loading:
                content.text = NSLocalizedString("support_loading", comment: "Loading…")
                cell.selectionStyle = .none
                cell.accessibilityIdentifier = "supportStatus"
            case .unavailable:
                // Not something the reader can act on: the app is still fully
                // usable, so this stays a quiet line rather than a dialog.
                content.text = NSLocalizedString("support_unavailable", comment: "")
                content.textProperties.color = .secondaryLabel
                cell.selectionStyle = .none
                cell.accessibilityIdentifier = "supportStatus"
            case .thanks:
                content.text = NSLocalizedString("support_thanks", comment: "")
                cell.selectionStyle = .none
                cell.accessibilityIdentifier = "supportStatus"
            case .ready(let tiers):
                let tier = tiers[indexPath.row]
                content.text = tier.label
                // StoreKit supplies the price already formatted for the
                // storefront, so this is never a hardcoded ¥ amount.
                content.secondaryText = tier.price
                cell.accessibilityIdentifier = "tier_\(tier.id)"
            }

        case .about:
            let version = MdrCore.version.isEmpty ? "—" : MdrCore.version
            content.text = String(format: NSLocalizedString("about_version", comment: "Version %@"), version)
            cell.selectionStyle = .none
            cell.accessibilityIdentifier = "aboutVersion"

        case .none:
            break
        }

        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section) {
        case .reading where indexPath.row == 1:
            let picker = LanguagePickerViewController(selected: prefs.lang) { [weak self] tag in
                guard let self = self else { return }
                self.prefs.lang = tag
                self.tableView.reloadRows(at: [indexPath], with: .automatic)
            }
            navigationController?.pushViewController(picker, animated: true)

        case .support:
            guard case .ready(let tiers) = storeState, indexPath.row < tiers.count else { return }
            let tier = tiers[indexPath.row]
            Task { await store.buy(tier) }

        default:
            break
        }
    }

    // MARK: - Actions

    @objc private func tocChanged(_ sender: UISwitch) {
        prefs.showToc = sender.isOn
    }

    // MARK: - Test seams

    /// Drive the table from a known store state, so the support section can be
    /// asserted without waiting on the network.
    func applyStoreState(_ state: Store.State) {
        storeState = state
        if isViewLoaded {
            tableView.reloadSections(IndexSet(integer: Section.support.rawValue), with: .none)
        }
    }

    var currentStoreState: Store.State { storeState }
}

/// The five language options, as a checked list. The iOS equivalent of
/// Android's `Spinner`, and the same five tags in the same order.
final class LanguagePickerViewController: UITableViewController {

    private let onSelect: (String) -> Void
    private var selectedIndex: Int

    init(selected tag: String, onSelect: @escaping (String) -> Void) {
        self.selectedIndex = Prefs.langIndex(tag)
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
        title = NSLocalizedString("pref_lang", comment: "Document language")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "languagePicker"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "lang")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Prefs.langTags.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "lang", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = Prefs.langLabel(at: indexPath.row)
        cell.contentConfiguration = content
        cell.accessoryType = indexPath.row == selectedIndex ? .checkmark : .none
        cell.accessibilityIdentifier = "lang_\(Prefs.langTags[indexPath.row].isEmpty ? "auto" : Prefs.langTags[indexPath.row])"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        selectedIndex = indexPath.row
        onSelect(Prefs.langTags[indexPath.row])
        tableView.reloadData()
        navigationController?.popViewController(animated: true)
    }
}
