import UIKit
import UniformTypeIdentifiers

/// Home screen: the system document browser (Recents / Browse), exactly what
/// PDF apps show. Picking or creating a `.md` opens the viewer.
final class DocumentBrowserViewController: UIDocumentBrowserViewController, UIDocumentBrowserViewControllerDelegate {
    static let markdownType = UTType("net.daringfireball.markdown") ?? .plainText

    init() {
        super.init(forOpening: [Self.markdownType, .plainText])
        delegate = self
        allowsDocumentCreation = true
        allowsPickingMultipleItems = false
        shouldShowFileExtensions = true
        localizedCreateDocumentActionTitle = "New Markdown"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - UIDocumentBrowserViewControllerDelegate

    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         didRequestDocumentCreationWithHandler importHandler: @escaping (URL?, UIDocumentBrowserViewController.ImportMode) -> Void) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("Untitled.md")
        let template = "# Untitled\n\n"
        do {
            try template.write(to: tmp, atomically: true, encoding: .utf8)
            importHandler(tmp, .move)
        } catch {
            importHandler(nil, .none)
        }
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController, didPickDocumentsAt documentURLs: [URL]) {
        guard let url = documentURLs.first else { return }
        open(url: url, presentImmediately: false)
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController, didImportDocumentAt sourceURL: URL, toDestinationURL destinationURL: URL) {
        open(url: destinationURL, presentImmediately: false)
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController, failedToImportDocumentAt documentURL: URL, error: Error?) {
        NSLog("[mdr-ios] import failed: %@", error?.localizedDescription ?? "unknown")
    }

    // MARK: - Opening

    func open(url: URL, presentImmediately: Bool) {
        let document = MarkdownDocument(fileURL: url)
        let viewer = DocumentViewController(document: document)
        let nav = UINavigationController(rootViewController: viewer)
        nav.modalPresentationStyle = .fullScreen
        let present: () -> Void = { [weak self] in self?.present(nav, animated: !presentImmediately) }
        if presentImmediately { present() } else { DispatchQueue.main.async(execute: present) }
    }
}
