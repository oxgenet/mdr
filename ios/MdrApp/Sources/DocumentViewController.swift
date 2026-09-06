import UIKit
import WebKit

/// Viewer / editor for one Markdown document. Layout mirrors a PDF viewer:
/// the rendered page fills the screen; the navigation bar carries Done, table
/// of contents, search, edit (pen) and share. Edit mode splits the screen into
/// a source pane (native UITextView: IME, undo, dictation) and the live preview.
final class DocumentViewController: UIViewController, UITextViewDelegate, WKNavigationDelegate {
    private let document: MarkdownDocument
    private let webView = WKWebView(frame: .zero, configuration: {
        let c = WKWebViewConfiguration()
        c.preferences.javaScriptCanOpenWindowsAutomatically = false
        return c
    }())
    private let textView = UITextView()
    private var editMode = false { didSet { layoutForMode() } }
    private var previewTimer: Timer?
    private var editorHeight: NSLayoutConstraint!

    init(document: MarkdownDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = document.fileURL.lastPathComponent
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(share)),
            UIBarButtonItem(image: UIImage(systemName: "pencil.tip.crop.circle"), style: .plain, target: self, action: #selector(toggleEdit)),
            UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(search)),
            UIBarButtonItem(image: UIImage(systemName: "list.bullet"), style: .plain, target: self, action: #selector(showToc)),
        ]
        navigationController?.hidesBarsOnSwipe = true   // PDF-viewer behaviour: bars hide while reading

        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        textView.delegate = self
        textView.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.backgroundColor = .secondarySystemBackground
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        textView.inputAccessoryView = makeSyntaxBar()

        for v in [textView, webView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        editorHeight = textView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editorHeight,
            webView.topAnchor.constraint(equalTo: textView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        document.open { [weak self] ok in
            guard let self = self else { return }
            guard ok else { self.showError("Could not open \(self.document.fileURL.lastPathComponent)"); return }
            self.textView.text = self.document.text
            self.render()
            NSLog("[mdr-ios] opened %@ (%d bytes, lang=%@)", self.document.fileURL.path, self.document.text.utf8.count,
                  MdrCore.detectLang(markdown: self.document.text))
        }
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    private func render() {
        let html = MdrCore.renderPage(markdown: document.text, baseDir: document.baseDir)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // The page's own ⋮ menu and inline editor are replaced by the native bar.
        webView.evaluateJavaScript("document.getElementById('kebab').style.display='none'; document.body.classList.add('no-toc'); 'ok'") { _, _ in }
        NSLog("[mdr-ios] rendered")
    }

    // MARK: - Modes

    private func layoutForMode() {
        editorHeight.constant = editMode ? view.bounds.height * 0.42 : 0
        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
        if editMode {
            textView.becomeFirstResponder()
        } else {
            textView.resignFirstResponder()
            // Re-render unconditionally: programmatic text changes (paste via
            // accessibility, dictation) do not always call textViewDidChange.
            previewTimer?.invalidate()
            webView.evaluateJavaScript(MdrCore.updateScript(markdown: textView.text, baseDir: document.baseDir)) { _, _ in }
            save()
        }
        navigationItem.rightBarButtonItems?[1].image = UIImage(systemName: editMode ? "checkmark.circle" : "pencil.tip.crop.circle")
    }

    @objc private func toggleEdit() { editMode.toggle() }

    @objc private func close() {
        save()
        document.close { [weak self] _ in self?.dismiss(animated: true) }
    }

    private func save() {
        document.markEdited(textView.text)
        if document.hasUnsavedChanges {
            document.save(to: document.fileURL, for: .forOverwriting) { ok in NSLog("[mdr-ios] saved=%d", ok ? 1 : 0) }
        }
    }

    // MARK: - Editing → live preview

    func textViewDidChange(_ textView: UITextView) {
        previewTimer?.invalidate()
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let js = MdrCore.updateScript(markdown: textView.text, baseDir: self.document.baseDir)
            self.webView.evaluateJavaScript(js) { _, _ in }
            self.document.markEdited(textView.text)   // UIDocument autosaves
        }
    }

    /// Keyboard accessory: wrap/insert Markdown syntax without typing it.
    private func makeSyntaxBar() -> UIView {
        let bar = UIToolbar()
        bar.sizeToFit()
        func item(_ title: String, _ sel: Selector) -> UIBarButtonItem {
            UIBarButtonItem(title: title, style: .plain, target: self, action: sel)
        }
        bar.items = [
            item("H", #selector(insHeading)), item("B", #selector(insBold)), item("I", #selector(insItalic)),
            item("•", #selector(insList)), item("☑", #selector(insTask)), item("`", #selector(insCode)),
            item("🔗", #selector(insLink)),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(toggleEdit)),
        ]
        return bar
    }
    private func wrap(_ l: String, _ r: String, placeholder: String) {
        let sel = textView.selectedRange
        let ns = textView.text as NSString
        let inner = sel.length > 0 ? ns.substring(with: sel) : placeholder
        textView.textStorage.replaceCharacters(in: sel, with: l + inner + r)
        textView.selectedRange = NSRange(location: sel.location + l.count, length: inner.count)
        textViewDidChange(textView)
    }
    private func linePrefix(_ p: String) {
        let ns = textView.text as NSString
        let line = ns.lineRange(for: NSRange(location: textView.selectedRange.location, length: 0))
        textView.textStorage.replaceCharacters(in: NSRange(location: line.location, length: 0), with: p)
        textViewDidChange(textView)
    }
    @objc private func insHeading() { linePrefix("## ") }
    @objc private func insBold() { wrap("**", "**", placeholder: "bold") }
    @objc private func insItalic() { wrap("*", "*", placeholder: "italic") }
    @objc private func insList() { linePrefix("- ") }
    @objc private func insTask() { linePrefix("- [ ] ") }
    @objc private func insCode() { wrap("`", "`", placeholder: "code") }
    @objc private func insLink() { wrap("[", "](https://)", placeholder: "link") }

    @objc private func keyboardChanged(_ n: Notification) {
        guard editMode, let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let overlap = max(0, view.bounds.maxY - view.convert(end, from: nil).minY)
        textView.contentInset.bottom = 0
        webView.scrollView.contentInset.bottom = overlap
    }

    // MARK: - Table of contents / search

    @objc private func showToc() {
        let js = "Array.from(document.querySelectorAll('.sidebar li')).map(li => ({t: li.textContent, h: li.querySelector('a').getAttribute('href'), l: li.className}))"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self, let items = result as? [[String: String]], !items.isEmpty else {
                self?.showError("No headings in this document"); return
            }
            let sheet = UIAlertController(title: "Contents", message: nil, preferredStyle: .actionSheet)
            for it in items {
                let level = Int(it["l"]?.replacingOccurrences(of: "toc-h", with: "") ?? "1") ?? 1
                let indent = String(repeating: "    ", count: max(0, level - 1))
                sheet.addAction(UIAlertAction(title: indent + (it["t"] ?? ""), style: .default) { _ in
                    let id = (it["h"] ?? "#").dropFirst()
                    self.webView.evaluateJavaScript("document.getElementById('\(id)')?.scrollIntoView({behavior:'smooth',block:'start'})") { _, _ in }
                })
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            sheet.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItems?.last
            self.present(sheet, animated: true)
        }
    }

    @objc private func search() {
        // Reuse the page's own search bar (highlights + next/prev).
        webView.evaluateJavaScript("(function(){var b=document.getElementById('searchBar');b.style.display='flex';var i=document.getElementById('searchInput');i.focus();i.select();})()") { _, _ in }
    }

    // MARK: - Share (.md as-is, or PDF for recipients without a Markdown app)

    @objc private func share() {
        save()
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Share Markdown (.md)", style: .default) { _ in
            self.presentShare([self.document.fileURL])
        })
        sheet.addAction(UIAlertAction(title: "Share as PDF", style: .default) { _ in
            self.webView.createPDF { result in
                switch result {
                case .success(let data):
                    let name = self.document.fileURL.deletingPathExtension().lastPathComponent + ".pdf"
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                    try? data.write(to: url)
                    self.presentShare([url])
                case .failure(let e): self.showError(e.localizedDescription)
                }
            }
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(sheet, animated: true)
    }

    private func presentShare(_ items: [Any]) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(vc, animated: true)
    }

    private func showError(_ message: String) {
        let a = UIAlertController(title: "mdr", message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }
}
