import UIKit
import UniformTypeIdentifiers

/// Share Extension: receives text or a file from any app's share sheet and
/// drops it into the shared Inbox (App Group container). The main app moves
/// Inbox items into its Documents folder on next activation and opens them.
final class ShareViewController: UIViewController {
    static let appGroup = "group.net.oxge.mdr"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "Saving to mdr…"
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        handleInput()
    }

    private func inbox() -> URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) else { return nil }
        let dir = base.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func handleInput() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem],
              let provider = items.flatMap({ $0.attachments ?? [] }).first,
              let inbox = inbox() else { finish(error: "No shared content or no App Group container"); return }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let url = item as? URL else { self.finish(error: "Bad file"); return }
                let dest = inbox.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                do { try FileManager.default.copyItem(at: url, to: dest); self.finish(error: nil) }
                catch { self.finish(error: error.localizedDescription) }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                let text = (item as? String) ?? (item as? Data).map { String(decoding: $0, as: UTF8.self) } ?? ""
                let first = text.split(separator: "\n").first.map(String.init) ?? "Shared"
                let stem = first.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "/", with: "-").prefix(40)
                let dest = inbox.appendingPathComponent("\(stem.isEmpty ? "Shared" : String(stem)).md")
                do { try text.write(to: dest, atomically: true, encoding: .utf8); self.finish(error: nil) }
                catch { self.finish(error: error.localizedDescription) }
            }
        } else {
            finish(error: "Unsupported content")
        }
    }

    private func finish(error: String?) {
        DispatchQueue.main.async {
            if let error = error {
                self.extensionContext?.cancelRequest(withError: NSError(domain: "net.oxge.mdr.share", code: 1,
                                                                        userInfo: [NSLocalizedDescriptionKey: error]))
            } else {
                self.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }
}
