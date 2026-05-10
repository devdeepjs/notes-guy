import XCTest
@testable import NotesGuyCore

final class SessionStoreTests: XCTestCase {
    func testCreateSessionCreatesRawFoldersManifestAndHistory() throws {
        let workspace = try makeWorkspace()
        let store = SessionStore(workspace: workspace)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let session = try store.createSession(
            id: "session-1",
            title: "Attention Tutorial",
            sourceURL: "https://example.com/video",
            sourceHint: "Visible YouTube page",
            sessionType: .youtube,
            startedAt: startedAt
        )

        XCTAssertEqual(session.status, .recording)
        XCTAssertEqual(session.rawArtifactRoot, ".notes-guy/raw/session-1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.rawSessionURL(sessionID: "session-1").appendingPathComponent("screenshots").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.rawSessionURL(sessionID: "session-1").appendingPathComponent("audio").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.rawSessionURL(sessionID: "session-1").appendingPathComponent("manifest.json").path))

        let sessions = try store.loadSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].title, "Attention Tutorial")
    }

    func testUpdateStatusPersistsChangedWikiPaths() throws {
        let workspace = try makeWorkspace()
        let store = SessionStore(workspace: workspace)
        _ = try store.createSession(id: "session-2", sessionType: .paper)

        let updated = try store.updateStatus(
            sessionID: "session-2",
            status: .completed,
            endedAt: Date(timeIntervalSince1970: 1_700_000_060),
            changedWikiPaths: ["Wiki/sources/paper.md", "Wiki/index.md"]
        )

        XCTAssertEqual(updated.status, .completed)
        XCTAssertEqual(updated.changedWikiPaths, ["Wiki/sources/paper.md", "Wiki/index.md"])

        let reloaded = try store.loadSessions()
        XCTAssertEqual(reloaded[0].status, .completed)
        XCTAssertEqual(reloaded[0].changedWikiPaths.count, 2)
    }

    private func makeWorkspace() throws -> WikiWorkspace {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-guy-session-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspace = WikiWorkspace(configuration: VaultConfiguration(vaultURL: root.appendingPathComponent("notes")))
        _ = try workspace.bootstrap()
        return workspace
    }
}
