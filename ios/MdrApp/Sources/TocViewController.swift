import UIKit

struct TocEntry {
    let title: String
    let anchor: String   // element id
    let level: Int
}

/// Native table of contents, presented as a sheet (medium / large detents),
/// like the outline panel of a PDF viewer. Indentation follows heading level.
final class TocViewController: UITableViewController {
    private let entries: [TocEntry]
    private let onSelect: (TocEntry) -> Void

    init(entries: [TocEntry], onSelect: @escaping (TocEntry) -> Void) {
        self.entries = entries
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
        title = "Contents"
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "toc")
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeSheet))
    }

    @objc private func closeSheet() { dismiss(animated: true) }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { entries.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "toc", for: indexPath)
        let e = entries[indexPath.row]
        var cfg = cell.defaultContentConfiguration()
        cfg.text = e.title
        cfg.textProperties.font = e.level <= 1 ? .preferredFont(forTextStyle: .headline) : .preferredFont(forTextStyle: .body)
        cfg.textProperties.color = e.level >= 4 ? .secondaryLabel : .label
        cell.contentConfiguration = cfg
        cell.indentationLevel = max(0, e.level - 1)
        cell.indentationWidth = 18
        cell.accessoryType = .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let e = entries[indexPath.row]
        dismiss(animated: true) { self.onSelect(e) }
    }

    /// Wrap in a navigation controller and configure sheet detents.
    static func sheet(entries: [TocEntry], onSelect: @escaping (TocEntry) -> Void) -> UIViewController {
        let nav = UINavigationController(rootViewController: TocViewController(entries: entries, onSelect: onSelect))
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        return nav
    }
}
