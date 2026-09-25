import XCTest
import WebKit
@testable import MdrApp

/// Pinch-zoom, which a reader needs because a large Mermaid diagram is
/// shrunk to fit the column and its labels are unreadable at that size.
///
/// `src/core/page.rs` pins the viewport string (`viewport_lets_the_reader_pinch_zoom`),
/// but that only proves the core does not *forbid* zooming. It says nothing
/// about whether WKWebView actually allows it — the shell could disable it,
/// and nobody had checked. This loads a real rendered page into a real
/// WKWebView and asks the scroll view.
@MainActor
final class ZoomTests: XCTestCase {

    private func load(_ markdown: String) async throws -> WKWebView {
        let html = MdrCore.renderPage(markdown: markdown, baseDir: "")
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let window = UIWindow(frame: web.frame)
        window.addSubview(web)
        window.makeKeyAndVisible()
        web.loadHTMLString(html, baseURL: nil)

        let deadline = Date().addingTimeInterval(30)
        while web.isLoading && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertFalse(web.isLoading, "the page never finished loading")
        // Let the viewport be applied to the scroll view.
        try await Task.sleep(nanoseconds: 700_000_000)
        return web
    }

    func testTheRenderedPageIsPinchZoomable() async throws {
        let web = try await load("# t\n\nSome text to lay out.\n")
        let scroll = web.scrollView
        XCTAssertGreaterThan(
            scroll.maximumZoomScale, scroll.minimumZoomScale,
            "WKWebView will not zoom this page: min \(scroll.minimumZoomScale), "
                + "max \(scroll.maximumZoomScale). A viewport with user-scalable=no or a "
                + "maximum-scale would do this, as would the shell overriding the scroll view."
        )
        XCTAssertGreaterThan(scroll.maximumZoomScale, 1.0, "no room to zoom in")
        XCTAssertTrue(scroll.isMultipleTouchEnabled, "the pinch gesture cannot be recognised")
    }

    /// The zoom actually takes effect, not merely permitted by the scroll view.
    func testZoomingInChangesTheScale() async throws {
        let web = try await load("# t\n\nSome text to lay out.\n")
        let scroll = web.scrollView
        let before = scroll.zoomScale
        scroll.setZoomScale(min(2.0, scroll.maximumZoomScale), animated: false)
        XCTAssertGreaterThan(scroll.zoomScale, before, "the scroll view refused the zoom")
    }

    /// The case the reader actually hits: the large subgraph diagram from
    /// tests/samples/mermaid/complex.md section 2.
    func testALargeDiagramFitsTheColumnAndStaysZoomable() async throws {
        let diagram = """
        ## A deliberately large diagram

        ```mermaid
        graph TD
            subgraph Input
                A1[Markdown file] --> A2[Read from disk]
                A2 --> A3[Strip front matter]
            end
            subgraph Parsing
                A3 --> B1[comrak GFM parse]
                B1 --> B2[Add heading ids]
                B2 --> B3[Extract table of contents]
            end
        ```
        """
        let web = try await load(diagram)
        let scroll = web.scrollView

        // It must not force a horizontally scrolling page: the diagram is
        // capped with max-width, so the layout stays within the column.
        let contentWidth = scroll.contentSize.width
        XCTAssertLessThanOrEqual(
            contentWidth, web.bounds.width + 1,
            "the page is wider than the screen at 1x — the diagram is not being capped"
        )
        XCTAssertGreaterThan(
            scroll.maximumZoomScale, 1.0,
            "a diagram shrunk to fit must still be zoomable, or its labels cannot be read"
        )
    }
}
