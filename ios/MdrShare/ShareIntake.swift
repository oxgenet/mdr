import Foundation

/// The decisions the Share Extension has to make about an incoming payload,
/// kept free of `NSItemProvider` and UIKit so they can be tested directly.
/// `ShareViewController` does the plumbing; everything that could be *wrong*
/// lives here.
enum ShareIntake {
    /// Extensions inherit the filesystem's rules, not Markdown's: a heading
    /// like `# Chapter 3/4: notes` is a perfectly good title and an illegal
    /// file name. Anything that would break a path, or a name, comes out.
    private static let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")

    /// A file name (no extension) for shared text, taken from its first line
    /// the way a Markdown document names itself: the H1, minus the hashes.
    static func stem(forText text: String) -> String {
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let cleaned = firstLine
            .replacingOccurrences(of: "#", with: "")
            .components(separatedBy: illegal).joined(separator: "-")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let trimmed = String(cleaned.prefix(40)).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Shared" : trimmed
    }

    /// Does this URL point at something mdr can read as a document? Only then
    /// is it worth fetching. Everything else becomes a link note instead —
    /// mdr has no HTML-to-Markdown converter and should not pretend otherwise.
    static func isDocumentURL(_ url: URL) -> Bool {
        ["md", "markdown", "mdown", "mkd", "mkdn", "txt", "text"]
            .contains(url.pathExtension.lowercased())
    }

    /// What a shared web page becomes: a note holding the title and the link.
    /// Deliberately not the page itself — fetching and converting arbitrary
    /// HTML is a different app, and the description promises it is not this one.
    static func linkNote(for url: URL, title: String?) -> String {
        "# \(heading(for: url, title: title))\n\n<\(url.absoluteString)>\n"
    }

    /// The file name for a shared web page, from its title when the sharing
    /// app gave us one and the host when it did not.
    static func stem(for url: URL, title: String?) -> String {
        let candidate = heading(for: url, title: title)
        return stem(forText: candidate)
    }

    private static func heading(for url: URL, title: String?) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return url.host ?? url.absoluteString
    }

    /// Inbox names collide: two pages called "Release notes" is normal. The
    /// app's importer already disambiguates on the way into Documents, but the
    /// Inbox itself needs to survive the second share before that runs.
    static func uniqueName(_ name: String, ext: String, taken: (String) -> Bool) -> String {
        let first = "\(name).\(ext)"
        guard taken(first) else { return first }
        var n = 2
        while taken("\(name) \(n).\(ext)") { n += 1 }
        return "\(name) \(n).\(ext)"
    }
}
