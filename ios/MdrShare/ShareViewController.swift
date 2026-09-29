import UIKit
import UniformTypeIdentifiers

/// Share Extension: receives text, a file or a web link from any app's share
/// sheet and drops it into the shared Inbox (App Group container). The main app
/// moves Inbox items into its Documents folder on next activation and opens them.
final class ShareViewController: UIViewController {
    static let appGroup = "group.net.oxge.mdr"

    /// A page can be slow and the extension is not allowed to hang the host
    /// app's share sheet waiting for it.
    private static let fetchTimeout: TimeInterval = 20
    /// Someone will eventually share a link to a 400 MB file. The Inbox is the
    /// user's own device storage, but an extension is not the place to fill it.
    private static let maxFetchBytes = 8 * 1024 * 1024

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = NSLocalizedString("share_saving", comment: "")
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

    /// Reserve a free name in the Inbox. Two shares of the same title in a row
    /// must not overwrite each other before the app has imported the first.
    private func destination(_ inbox: URL, stem: String, ext: String) -> URL {
        let name = ShareIntake.uniqueName(stem, ext: ext) {
            FileManager.default.fileExists(atPath: inbox.appendingPathComponent($0).path)
        }
        return inbox.appendingPathComponent(name)
    }

    private func handleInput() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem],
              let provider = items.flatMap({ $0.attachments ?? [] }).first,
              let inbox = inbox() else { finish(error: "No shared content or no App Group container"); return }

        // Safari puts the page title in the item, not the attachment.
        let title = items.compactMap { $0.attributedContentText?.string }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        // File first: a file URL conforms to `public.url` too, so testing for
        // the general case ahead of the specific one would send every shared
        // document down the link-note path.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let url = item as? URL else { self.finish(error: "Bad file"); return }
                let dest = self.destination(inbox,
                                            stem: url.deletingPathExtension().lastPathComponent,
                                            ext: url.pathExtension.isEmpty ? "md" : url.pathExtension)
                do { try FileManager.default.copyItem(at: url, to: dest); self.finish(error: nil) }
                catch { self.finish(error: error.localizedDescription) }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                guard let url = item as? URL else { self.finish(error: "Bad link"); return }
                self.handle(webURL: url, title: title, inbox: inbox)
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                let text = (item as? String) ?? (item as? Data).map { String(decoding: $0, as: UTF8.self) } ?? ""
                let dest = self.destination(inbox, stem: ShareIntake.stem(forText: text), ext: "md")
                do { try text.write(to: dest, atomically: true, encoding: .utf8); self.finish(error: nil) }
                catch { self.finish(error: error.localizedDescription) }
            }
        } else {
            finish(error: "Unsupported content")
        }
    }

    /// A link to a Markdown or text file is fetched — that is the same act as
    /// opening it, and the user asked for it by sharing. Anything else becomes
    /// a note holding the link: mdr renders Markdown, it does not scrape pages.
    private func handle(webURL url: URL, title: String?, inbox: URL) {
        guard ShareIntake.isDocumentURL(url) else {
            let dest = destination(inbox, stem: ShareIntake.stem(for: url, title: title), ext: "md")
            do { try ShareIntake.linkNote(for: url, title: title).write(to: dest, atomically: true, encoding: .utf8) }
            catch { finish(error: error.localizedDescription); return }
            finish(error: nil)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.fetchTimeout
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { self.finish(error: error.localizedDescription); return }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                self.finish(error: "Server returned \(http.statusCode)"); return
            }
            guard let data = data, !data.isEmpty else { self.finish(error: "Empty response"); return }
            guard data.count <= Self.maxFetchBytes else { self.finish(error: "File too large"); return }
            let dest = self.destination(inbox,
                                        stem: url.deletingPathExtension().lastPathComponent,
                                        ext: url.pathExtension.isEmpty ? "md" : url.pathExtension)
            do { try data.write(to: dest, options: .atomic); self.finish(error: nil) }
            catch { self.finish(error: error.localizedDescription) }
        }.resume()
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
