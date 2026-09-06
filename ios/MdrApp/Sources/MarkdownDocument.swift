import UIKit

/// A `.md` file opened in place (Files, iCloud Drive, other providers).
/// UIDocument gives us coordinated reads/writes, autosave and conflict handling
/// — the same machinery PDF apps use for annotating in place.
final class MarkdownDocument: UIDocument {
    var text: String = ""

    override func contents(forType typeName: String) throws -> Any {
        Data(text.utf8)
    }

    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        guard let data = contents as? Data else { return }
        text = String(decoding: data, as: UTF8.self)
    }

    /// Directory used to resolve relative images in the document.
    var baseDir: String { fileURL.deletingLastPathComponent().path }

    /// Mark the document dirty; UIDocument autosaves shortly after.
    func markEdited(_ newText: String) {
        guard newText != text else { return }
        text = newText
        updateChangeCount(.done)
    }
}
