import XCTest
@testable import NotesGuyCore

final class StarterNoteWriterTests: XCTestCase {
    func testWritesStarterNoteWithoutPublishingDraftToIndex() throws {
        let workspace = try makeWorkspace()
        let session = LearningSession(
            id: "session-1",
            title: "Attention Is All You Need - YouTube",
            sourceHint: "App: Chrome\nWindows: Attention Is All You Need - YouTube",
            sessionType: .youtube,
            rawArtifactRoot: ".notes-guy/raw/session-1"
        )

        let relativePath = try StarterNoteWriter().writeStarterNote(for: session, workspace: workspace)
        let noteURL = workspace.configuration.url(for: relativePath)

        XCTAssertEqual(relativePath, "Wiki/sources/attention-is-all-you-need-youtube-session-1.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: noteURL.path))
        let note = try String(contentsOf: noteURL, encoding: .utf8)
        XCTAssertTrue(note.contains("# Attention Is All You Need - YouTube"))
        XCTAssertTrue(note.contains("type: \"source-note\""))
        XCTAssertTrue(note.contains("source_type: \"youtube\""))
        XCTAssertTrue(note.contains("primary_concepts: []"))
        XCTAssertTrue(note.contains("Raw session folder: `.notes-guy/raw/session-1`"))

        let index = try String(contentsOf: workspace.indexURL, encoding: .utf8)
        XCTAssertTrue(index.contains("## Source Notes"))
        XCTAssertFalse(index.contains("[[Wiki/sources/attention-is-all-you-need-youtube-session-1.md|Attention Is All You Need - YouTube]]"))
    }

    func testCanPublishStarterNoteToIndexWhenExplicitlyRequested() throws {
        let workspace = try makeWorkspace()
        let session = LearningSession(
            id: "session-1",
            title: "Attention Is All You Need - YouTube",
            sourceHint: "App: Chrome\nWindows: Attention Is All You Need - YouTube",
            sessionType: .youtube,
            rawArtifactRoot: ".notes-guy/raw/session-1"
        )

        let relativePath = try StarterNoteWriter().writeStarterNote(
            for: session,
            workspace: workspace,
            publishToIndex: true
        )

        let index = try String(contentsOf: workspace.indexURL, encoding: .utf8)
        XCTAssertTrue(index.contains("[[\(relativePath)|Attention Is All You Need - YouTube]]"))
    }

    func testSlugIsFilesystemFriendly() {
        XCTAssertEqual(StarterNoteWriter.slug(for: "KV Cache: Why? / How!"), "kv-cache-why-how")
    }

    private func makeWorkspace() throws -> WikiWorkspace {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-guy-starter-note-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspace = WikiWorkspace(configuration: VaultConfiguration(vaultURL: root.appendingPathComponent("notes")))
        _ = try workspace.bootstrap()
        return workspace
    }
}
