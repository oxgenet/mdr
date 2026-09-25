import UIKit
import WebKit
import PhotosUI
import UniformTypeIdentifiers

/// Viewer / editor for one Markdown document. Layout mirrors a PDF viewer:
/// the rendered page fills the screen; the navigation bar carries Done, table
/// of contents, search, edit (pen) and share. Edit mode splits the screen into
/// a source pane (native UITextView: IME, undo, dictation) and the live preview.
final class DocumentViewController: UIViewController, UITextViewDelegate, WKNavigationDelegate,
                                    UISearchBarDelegate, PHPickerViewControllerDelegate {
    private let document: MarkdownDocument
    private let prefs = Prefs()
    /// The preferences the current page was rendered with, so returning from
    /// Settings can tell whether anything actually changed. Mirrors
    /// `MainActivity.renderedWith` on Android.
    private var renderedWith: (toc: Bool, lang: String, remoteImages: Bool, localHttp: Bool)?
    private let webView = WKWebView(frame: .zero, configuration: {
        let c = WKWebViewConfiguration()
        c.preferences.javaScriptCanOpenWindowsAutomatically = false
        return c
    }())
    private let textView = UITextView()
    private let searchBar = UISearchBar()
    private var editMode = false { didSet { layoutForMode() } }
    private var searching = false
    private var previewTimer: Timer?
    private var editorHeight: NSLayoutConstraint!
    private var editItem: UIBarButtonItem!
    private var searchItem: UIBarButtonItem!

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
        editItem = UIBarButtonItem(image: UIImage(systemName: "pencil.tip.crop.circle"), style: .plain, target: self, action: #selector(toggleEdit))
        name(editItem, "Edit", "editButton")
        searchItem = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(toggleSearch))
        name(searchItem, "Search", "searchButton")
        installBarItems()
        navigationController?.hidesBarsOnSwipe = true   // PDF-viewer behaviour: bars hide while reading

        searchBar.delegate = self
        searchBar.placeholder = NSLocalizedString("search_hint", comment: "Search in document")
        searchBar.searchBarStyle = .minimal
        searchBar.showsCancelButton = false
        searchBar.returnKeyType = .search
        searchBar.enablesReturnKeyAutomatically = false
        searchBar.autocapitalizationType = .none

        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.accessibilityIdentifier = "documentPage"
        searchBar.accessibilityIdentifier = "documentSearch"
        textView.accessibilityIdentifier = "sourceEditor"
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

    /// Give a symbol-only bar button a name, in all three places that need one.
    ///
    /// `title` is not decoration here. When iOS 26 collapses an item into the
    /// "More" overflow it renders it as a text row, and an item with only an
    /// image is labelled with the raw SF Symbol name — the Settings item read
    /// as "gearshape" to VoiceOver and to the tests. Setting a title fixes the
    /// menu row; the bar itself still shows just the image.
    private func name(_ item: UIBarButtonItem, _ title: String, _ identifier: String) {
        item.title = title
        item.accessibilityLabel = title
        item.accessibilityIdentifier = identifier
    }

    private func installBarItems() {
        navigationItem.titleView = nil
        let done = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(close))
        done.accessibilityIdentifier = "doneButton"
        navigationItem.leftBarButtonItem = done
        let shareItem = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(share))
        name(shareItem, NSLocalizedString("action_share", comment: "Share"), "shareButton")
        let tocItem = UIBarButtonItem(image: UIImage(systemName: "list.bullet"), style: .plain, target: self, action: #selector(showToc))
        name(tocItem, NSLocalizedString("action_toc", comment: "Table of contents"), "tocButton")
        let settingsItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: self, action: #selector(showSettings))
        name(settingsItem, NSLocalizedString("action_settings", comment: "Settings"), "settingsButton")
        // Order matters. iOS 26 collapses whatever does not fit into a "More"
        // overflow, taking from the trailing (rightmost) end — which is
        // element 0 of this array. Five items plus Done do not fit at 390pt,
        // the width of an iPhone 16/16e, so one of them *will* be collapsed on
        // most phones. Settings goes first so that it is the one to go: it is
        // the least-used of the five, and on Android it already lives in the
        // options-menu overflow. Share, Edit, Search and Table of contents
        // stay on the bar.
        //
        // This was found by CI, not locally: a 402pt iPhone 17 Pro fits all
        // six and shows nothing wrong.
        navigationItem.rightBarButtonItems = [settingsItem, shareItem, editItem, searchItem, tocItem]
    }

    private func render() {
        renderedWith = (prefs.showToc, prefs.lang, prefs.remoteImages, prefs.allowLocalHttp)
        let html = MdrCore.renderPage(
            markdown: document.text,
            baseDir: document.baseDir,
            lang: prefs.lang,
            toc: prefs.showToc
        )
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func refreshPreview() {
        webView.evaluateJavaScript(
            MdrCore.updateScript(markdown: textView.text, baseDir: document.baseDir, lang: prefs.lang)
        ) { _, _ in }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // The page's own ⋮ menu, inline editor and search bar are replaced by
        // native UI, so the kebab always goes.
        //
        // The sidebar is conditional: this used to add `no-toc` unconditionally,
        // which would have made "Show table of contents" a setting that
        // silently did nothing — the core would render the sidebar and this
        // line would immediately hide it again. Android never stripped it.
        let hideSidebar = prefs.showToc ? "" : " document.body.classList.add('no-toc');"
        webView.evaluateJavaScript(
            "document.getElementById('kebab').style.display='none';\(hideSidebar) 'ok'"
        ) { _, _ in }
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
            refreshPreview()
            save()
        }
        editItem.image = UIImage(systemName: editMode ? "checkmark.circle" : "pencil.tip.crop.circle")
    }

    @objc private func toggleEdit() {
        if searching { toggleSearch() }
        editMode.toggle()
    }

    @objc private func showSettings() {
        let settings = SettingsViewController(prefs: prefs)
        let nav = UINavigationController(rootViewController: settings)
        present(nav, animated: true)
    }

    /// Re-render if Settings changed something since this page was drawn.
    /// The counterpart of `MainActivity.onResume` on Android.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let drawn = renderedWith else { return }
        // Image policy counts too: remote images are resolved while the page
        // is built, so flipping either switch changes what the page contains.
        if drawn.toc != prefs.showToc
            || drawn.lang != prefs.lang
            || drawn.remoteImages != prefs.remoteImages
            || drawn.localHttp != prefs.allowLocalHttp {
            render()
        }
    }

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
            self.refreshPreview()
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
        // Keep to what fits one phone-width row (iOS 26 scrolls overflowing toolbars,
        // which hides the photo / done buttons). Italic and inline code stay as
        // plain typing.
        let photo = UIBarButtonItem(image: UIImage(systemName: "photo"), style: .plain, target: self, action: #selector(insertImage))
        photo.accessibilityLabel = "Insert photo"
        bar.items = [
            item("H", #selector(insHeading)), item("B", #selector(insBold)),
            item("•", #selector(insList)), item("☑", #selector(insTask)),
            item("🔗", #selector(insLink)), photo,
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(toggleEdit)),
        ]
        return bar
    }
    private func insertAtCursor(_ text: String) {
        let sel = textView.selectedRange
        textView.textStorage.replaceCharacters(in: sel, with: text)
        textView.selectedRange = NSRange(location: sel.location + (text as NSString).length, length: 0)
        textViewDidChange(textView)
    }
    private func wrap(_ l: String, _ r: String, placeholder: String) {
        let sel = textView.selectedRange
        let ns = textView.text as NSString
        let inner = sel.length > 0 ? ns.substring(with: sel) : placeholder
        textView.textStorage.replaceCharacters(in: sel, with: l + inner + r)
        textView.selectedRange = NSRange(location: sel.location + (l as NSString).length, length: (inner as NSString).length)
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

    // MARK: - Image insertion (photo library → file next to the document → ![](name))

    @objc private func insertImage() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        let stem = document.fileURL.deletingPathExtension().lastPathComponent
        let name = "\(stem)-\(Int(Date().timeIntervalSince1970)).jpg"
        let dest = document.fileURL.deletingLastPathComponent().appendingPathComponent(name)
        provider.loadObject(ofClass: UIImage.self) { [weak self] obj, err in
            guard let self = self else { return }
            // Downscale to a document-friendly size (longest side 2048 px) before saving.
            guard let raw = obj as? UIImage, let data = Self.downscaled(raw, maxSide: 2048).jpegData(compressionQuality: 0.85) else {
                DispatchQueue.main.async { self.showError(err?.localizedDescription ?? "Could not load image") }
                return
            }
            // Write next to the document with file coordination (it may live in iCloud / a provider).
            var coordErr: NSError?
            NSFileCoordinator().coordinate(writingItemAt: dest, options: .forReplacing, error: &coordErr) { url in
                try? data.write(to: url)
            }
            DispatchQueue.main.async {
                self.insertAtCursor("\n![\(stem)](\(name))\n")
                NSLog("[mdr-ios] inserted image %@ (%d bytes)", name, data.count)
            }
        }
    }

    private static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    @objc private func keyboardChanged(_ n: Notification) {
        guard let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let overlap = max(0, view.bounds.maxY - view.convert(end, from: nil).minY)
        webView.scrollView.contentInset.bottom = overlap
    }

    // MARK: - Table of contents (native sheet)

    @objc private func showToc() {
        let js = "Array.from(document.querySelectorAll('.sidebar li')).map(li => ({t: li.textContent, h: li.querySelector('a').getAttribute('href'), l: li.className}))"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            let entries = ((result as? [[String: String]]) ?? []).map { it -> TocEntry in
                let level = Int((it["l"] ?? "toc-h1").replacingOccurrences(of: "toc-h", with: "")) ?? 1
                return TocEntry(title: it["t"] ?? "", anchor: String((it["h"] ?? "#").dropFirst()), level: level)
            }
            guard !entries.isEmpty else { self.showError(NSLocalizedString("no_headings", comment: "")); return }
            NSLog("[mdr-ios] toc %d entries", entries.count)
            let sheet = TocViewController.sheet(entries: entries) { e in
                let id = e.anchor.replacingOccurrences(of: "'", with: "\\'")
                self.webView.evaluateJavaScript("document.getElementById('\(id)')?.scrollIntoView({behavior:'smooth',block:'start'})") { _, _ in }
            }
            self.present(sheet, animated: true)
        }
    }

    // MARK: - Search (native bar in the navigation bar, highlights in the page)

    @objc private func toggleSearch() {
        searching.toggle()
        if searching {
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItems = [UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(toggleSearch))]
            navigationItem.titleView = searchBar
            searchBar.becomeFirstResponder()
        } else {
            searchBar.text = nil
            searchBar.prompt = nil
            searchBar.resignFirstResponder()
            installBarItems()
            webView.evaluateJavaScript("window.mdrSearch && mdrSearch('')") { _, _ in }
        }
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let q = searchText.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.mdrSearch ? mdrSearch('\(q)') : 0") { n, _ in
            let count = (n as? Int) ?? 0
            searchBar.prompt = searchText.isEmpty ? nil : (count == 0 ? "No matches" : "\(count) match\(count == 1 ? "" : "es")")
            NSLog("[mdr-ios] search '%@' -> %d", searchText, count)
        }
    }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        webView.evaluateJavaScript("window.searchNav && searchNav(1)") { _, _ in }
    }
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) { toggleSearch() }

    // MARK: - Share (.md as-is, or PDF for recipients without a Markdown app)

    @objc private func share() {
        save()
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Share Markdown (.md)", style: .default) { _ in
            NSLog("[mdr-ios] share md %@", self.document.fileURL.lastPathComponent)
            self.presentShare([self.document.fileURL])
        })
        sheet.addAction(UIAlertAction(title: "Share as PDF", style: .default) { _ in
            self.exportPDF { url in self.presentShare([url]) }
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(sheet, animated: true)
    }

    /// Render the current page to a PDF file in the temporary directory.
    func exportPDF(completion: @escaping (URL) -> Void) {
        webView.createPDF { result in
            switch result {
            case .success(let data):
                let name = self.document.fileURL.deletingPathExtension().lastPathComponent + ".pdf"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                do {
                    try data.write(to: url)
                    NSLog("[mdr-ios] pdf exported %@ (%d bytes)", name, data.count)
                    completion(url)
                } catch { self.showError(error.localizedDescription) }
            case .failure(let e): self.showError(e.localizedDescription)
            }
        }
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
