import XCTest
@testable import NotesGuyCore

final class ImmediateSourceNoteDraftWriterTests: XCTestCase {
    func testWritesCleanDraftFromFramesWithoutRawTimeline() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-guy-immediate-draft-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let rawURL = root.appendingPathComponent(".notes-guy/raw/session-1", isDirectory: true)
        try FileManager.default.createDirectory(at: rawURL, withIntermediateDirectories: true)

        let noteURL = root.appendingPathComponent("Wiki/sources/interview-pen-system-design-session-1.md")
        try FileManager.default.createDirectory(at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        ---
        title: "Interview Pen | System Design"
        status: "capture-in-progress"
        ---

        # Interview Pen | System Design

        ## Visual Timeline

        - [0:01] raw screenshot line
        <!-- capture-status:start -->
        ## Capture Status
        - Screen capture: available
        <!-- capture-status:end -->
        """.write(to: noteURL, atomically: true, encoding: .utf8)

        let frames = [
            #"{"elapsed_seconds":1.2,"screenshot_path":".notes-guy/raw/session-1/screenshots/frame-1.png","visible_text":["Brave","interviewpen.com/courses/system-design/database-fundamentals","Products","Reviews","Customers","Orders"]}"#,
            #"{"elapsed_seconds":242.0,"screenshot_path":".notes-guy/raw/session-1/screenshots/frame-2.png","visible_text":["CRUD","Indexing","Replication","Sharding"]}"#
        ].joined(separator: "\n")
        try frames.write(to: rawURL.appendingPathComponent("frames.jsonl"), atomically: true, encoding: .utf8)

        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let session = LearningSession(
            id: "session-1",
            title: "Interview Pen | System Design",
            sourceURL: "https://interviewpen.com/courses/system-design/database-fundamentals",
            sourceHint: "App: Brave Browser",
            sessionType: .youtube,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(300),
            status: .completed,
            rawArtifactRoot: ".notes-guy/raw/session-1"
        )

        try ImmediateSourceNoteDraftWriter().writeDraft(
            noteURL: noteURL,
            session: session,
            rawURL: rawURL,
            observations: [
                SessionContextObservation(
                    timestamp: startedAt,
                    elapsedSeconds: 1,
                    appName: "Brave Browser",
                    summary: "Brave Browser: Interview Pen | System Design"
                )
            ]
        )

        let note = try String(contentsOf: noteURL, encoding: .utf8)
        XCTAssertTrue(note.contains("title: \"Interview Pen - Database Fundamentals\""))
        XCTAssertTrue(note.contains("status: \"source-draft\""))
        XCTAssertTrue(note.contains("Database Fundamentals"))
        XCTAssertTrue(note.contains("Database Schema Design"))
        XCTAssertTrue(note.contains("CRUD"))
        XCTAssertTrue(note.contains("Replication"))
        XCTAssertTrue(note.contains("[[Wiki/topics/system-design.md|System Design]]"))
        XCTAssertFalse(note.contains("[[System Design]]"))
        XCTAssertFalse(note.contains("## Visual Timeline"))
        XCTAssertFalse(note.contains("capture-status:start"))
        XCTAssertFalse(note.contains("raw screenshot line"))
    }

    func testDraftRecoversURLAndTitleFromSourceHintWhenSessionURLIsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-guy-immediate-draft-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let rawURL = root.appendingPathComponent(".notes-guy/raw/session-2", isDirectory: true)
        try FileManager.default.createDirectory(at: rawURL, withIntermediateDirectories: true)

        let noteURL = root.appendingPathComponent("Wiki/sources/interview-pen-system-design-session-2.md")
        try FileManager.default.createDirectory(at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        try """
        {"elapsed_seconds":2.0,"screenshot_path":".notes-guy/raw/session-2/screenshots/frame-1.png","visible_text":["Database Optimization","Partial Indexes","Hash Indexes","Materialized Views"]}
        """.write(to: rawURL.appendingPathComponent("frames.jsonl"), atomically: true, encoding: .utf8)

        let startedAt = Date(timeIntervalSince1970: 1_800_000_500)
        let session = LearningSession(
            id: "session-2",
            title: "Interview Pen | System Design",
            sourceURL: nil,
            sourceHint: "App: Brave Browser\nURL: https://interviewpen.com/courses/system-design/database-optimization",
            sessionType: .general,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(120),
            status: .completed,
            rawArtifactRoot: ".notes-guy/raw/session-2"
        )

        try ImmediateSourceNoteDraftWriter().writeDraft(
            noteURL: noteURL,
            session: session,
            rawURL: rawURL,
            observations: []
        )

        let note = try String(contentsOf: noteURL, encoding: .utf8)
        XCTAssertTrue(note.contains("title: \"Interview Pen - Database Optimization\""))
        XCTAssertTrue(note.contains("source_url: \"https://interviewpen.com/courses/system-design/database-optimization\""))
        XCTAssertTrue(note.contains("source_title: \"Interview Pen - Database Optimization\""))
        XCTAssertTrue(note.contains("Partial Indexes"))
        XCTAssertFalse(note.contains("source_url: \"\""))
    }
}
