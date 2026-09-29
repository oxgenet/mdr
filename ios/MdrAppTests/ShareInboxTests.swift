import XCTest
@testable import MdrApp

/// The half of the share path that runs inside the app: whatever the Share
/// Extension left in the App Group Inbox has to end up in Documents, or the
/// share silently did nothing.
///
/// App Groups do not exist on an unsigned simulator build — the container comes
/// back nil — so these skip there and run for real on a signed device. That is
/// the whole reason this path went unverified for so long.
final class ShareInboxTests: XCTestCase {

    private func inbox() throws -> URL {
        guard let group = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SceneDelegate.appGroup) else {
            throw XCTSkip("""
                No App Group container. Entitlements for \(SceneDelegate.appGroup) only take \
                effect in a signed build, so this runs on a device, not the simulator.
                """)
        }
        let dir = group.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testASharedFileIsMovedOutOfTheInboxIntoDocuments() throws {
        let inbox = try inbox()
        let docs = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("docs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: docs) }

        let shared = inbox.appendingPathComponent("From Safari.md")
        try "# From Safari\n\n<https://example.com>\n".write(to: shared, atomically: true, encoding: .utf8)

        let newest = SceneDelegate.importShareInbox(documents: docs)

        XCTAssertEqual(newest?.lastPathComponent, "From Safari.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: docs.appendingPathComponent("From Safari.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: shared.path),
                       "the Inbox copy must be moved, not left behind to be imported again next launch")
    }

    func testTwoSharesOfTheSameNameBothSurvive() throws {
        let inbox = try inbox()
        let docs = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("docs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: docs) }

        for body in ["first", "second"] {
            try body.write(to: inbox.appendingPathComponent("Notes.md"), atomically: true, encoding: .utf8)
            SceneDelegate.importShareInbox(documents: docs)
        }

        XCTAssertEqual(try String(contentsOf: docs.appendingPathComponent("Notes.md"), encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: docs.appendingPathComponent("Notes 2.md"), encoding: .utf8), "second")
    }

    func testAnEmptyInboxOpensNothing() throws {
        _ = try inbox()
        let docs = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("docs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: docs) }
        // On a device the Inbox may hold something a real share left there;
        // drain it first so this asserts about emptiness, not about history.
        SceneDelegate.importShareInbox(documents: docs)
        XCTAssertNil(SceneDelegate.importShareInbox(documents: docs))
    }
}
