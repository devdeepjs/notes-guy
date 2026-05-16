import XCTest
@testable import NotesGuyCore

final class LocalWikiEnrichmentSeedWriterTests: XCTestCase {
    func testCreatesMissingDurablePagesAndUpdatesIndexLogAndTopic() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-guy-local-seed-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspace = WikiWorkspace(configuration: VaultConfiguration(vaultURL: root.appendingPathComponent("notes", isDirectory: true)))
        _ = try workspace.bootstrap()

        let topicURL = workspace.configuration.url(for: "Wiki/topics/system-design.md")
        try """
        # System Design

        ## Start Here

        ## Source Notes

        """.write(to: topicURL, atomically: true, encoding: .utf8)

        let sourceRelativePath = "Wiki/sources/interview-pen-caching-basics-session.md"
        let sourceURL = workspace.configuration.url(for: sourceRelativePath)
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        ---
        title: "Interview Pen - Caching Basics"
        status: "source-ready"
        related_notes:
          - "[[Wiki/topics/system-design.md|System Design]]"
          - "[[Wiki/concepts/caching.md|Caching]]"
          - "[[Wiki/concepts/cache-eviction.md|Cache Eviction]]"
        ---

        # Interview Pen - Caching Basics

        ## Source Notes

        ### Cache Eviction

        - Atomic idea: cache memory is finite.
        - Mental model: remove entries that are old or cold.
        """.write(to: sourceURL, atomically: true, encoding: .utf8)

        let result = try LocalWikiEnrichmentSeedWriter().writeSeeds(
            sourceNoteURL: sourceURL,
            sourceNoteRelativePath: sourceRelativePath,
            workspace: workspace,
            sessionID: "session-1"
        )

        XCTAssertTrue(result.changedPaths.contains("Wiki/concepts/caching.md"))
        XCTAssertTrue(result.changedPaths.contains("Wiki/concepts/cache-eviction.md"))
        XCTAssertTrue(result.changedPaths.contains("Wiki/index.md"))
        XCTAssertTrue(result.changedPaths.contains("Wiki/topics/system-design.md"))
        XCTAssertTrue(result.changedPaths.contains(".notes-guy/log.md"))

        let caching = try String(contentsOf: workspace.configuration.url(for: "Wiki/concepts/caching.md"), encoding: .utf8)
        XCTAssertTrue(caching.contains("type: \"concept-note\""))
        XCTAssertTrue(caching.contains("[[Wiki/sources/interview-pen-caching-basics-session.md|Interview Pen - Caching Basics]]"))

        let eviction = try String(contentsOf: workspace.configuration.url(for: "Wiki/concepts/cache-eviction.md"), encoding: .utf8)
        XCTAssertTrue(eviction.contains("- Atomic idea: cache memory is finite."))
        XCTAssertFalse(eviction.contains("[[Cache Eviction]]"))

        let index = try String(contentsOf: workspace.indexURL, encoding: .utf8)
        XCTAssertTrue(index.contains("[[Wiki/sources/interview-pen-caching-basics-session.md|Interview Pen - Caching Basics]]"))
        XCTAssertTrue(index.contains("[[Wiki/concepts/caching.md|Caching]]"))
        XCTAssertTrue(index.contains("[[Wiki/concepts/cache-eviction.md|Cache Eviction]]"))

        let topic = try String(contentsOf: topicURL, encoding: .utf8)
        XCTAssertTrue(topic.contains("[[Wiki/concepts/caching.md|Caching]]"))
        XCTAssertTrue(topic.contains("[[Wiki/sources/interview-pen-caching-basics-session.md|Interview Pen - Caching Basics]]"))

        let log = try String(contentsOf: workspace.logURL, encoding: .utf8)
        XCTAssertTrue(log.contains("Local seed enrichment"))
    }

    func testUsesFrontmatterTitleWhenHeadingIsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-guy-local-seed-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspace = WikiWorkspace(configuration: VaultConfiguration(vaultURL: root.appendingPathComponent("notes", isDirectory: true)))
        _ = try workspace.bootstrap()

        let sourceRelativePath = "Wiki/sources/browser-reading-session.md"
        let sourceURL = workspace.configuration.url(for: sourceRelativePath)
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        ---
        title: "Browser Reading Session"
        status: "source-draft"
        related_notes:
          - "[[Wiki/concepts/browser-reading.md|Browser Reading]]"
        ---

        ## Source Notes

        ### Browser Reading

        - Atomic idea: a reading session can be captured from OCR and active-window context.
        """.write(to: sourceURL, atomically: true, encoding: .utf8)

        _ = try LocalWikiEnrichmentSeedWriter().writeSeeds(
            sourceNoteURL: sourceURL,
            sourceNoteRelativePath: sourceRelativePath,
            workspace: workspace,
            sessionID: "session-frontmatter"
        )

        let concept = try String(contentsOf: workspace.configuration.url(for: "Wiki/concepts/browser-reading.md"), encoding: .utf8)
        XCTAssertTrue(concept.contains("[[Wiki/sources/browser-reading-session.md|Browser Reading Session]]"))
    }
}
