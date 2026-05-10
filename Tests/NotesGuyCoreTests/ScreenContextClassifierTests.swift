import XCTest
@testable import NotesGuyCore

final class ScreenContextClassifierTests: XCTestCase {
    func testPromptsForYouTubeWindow() {
        let context = ScreenSourceContext(
            permissionStatus: .available,
            frontmostApplicationName: "Google Chrome",
            frontmostBundleIdentifier: "com.google.Chrome",
            visibleWindowTitles: ["Attention Is All You Need - YouTube"]
        )

        let suggestion = ScreenContextClassifier().classify(context)

        XCTAssertTrue(suggestion.shouldPrompt)
        XCTAssertEqual(suggestion.sessionType, .youtube)
        XCTAssertTrue(suggestion.title.contains("YouTube"))
    }

    func testPromptsForGenericVideoLearningWindow() {
        let context = ScreenSourceContext(
            permissionStatus: .available,
            frontmostApplicationName: "Safari",
            visibleWindowTitles: ["CS231n Lecture Video Player"]
        )

        let suggestion = ScreenContextClassifier().classify(context)

        XCTAssertTrue(suggestion.shouldPrompt)
        XCTAssertEqual(suggestion.sessionType, .general)
    }

    func testDoesNotPromptForPlainBrowserWindow() {
        let context = ScreenSourceContext(
            permissionStatus: .available,
            frontmostApplicationName: "Brave Browser",
            frontmostBundleIdentifier: "com.brave.Browser",
            visibleWindowTitles: ["Inbox - Work"]
        )

        let suggestion = ScreenContextClassifier().classify(context)

        XCTAssertFalse(suggestion.shouldPrompt)
    }

    func testDoesNotPromptForOwnAppWindow() {
        let context = ScreenSourceContext(
            permissionStatus: .available,
            frontmostApplicationName: "notes-guy",
            visibleWindowTitles: ["notes-guy"]
        )

        let suggestion = ScreenContextClassifier().classify(context)

        XCTAssertFalse(suggestion.shouldPrompt)
    }

    func testFingerprintChangesWithWindowTitle() {
        let first = ScreenSourceContext(
            frontmostApplicationName: "Chrome",
            visibleWindowTitles: ["A - YouTube"]
        )
        let second = ScreenSourceContext(
            frontmostApplicationName: "Chrome",
            visibleWindowTitles: ["B - YouTube"]
        )

        XCTAssertNotEqual(
            ScreenContextClassifier.fingerprint(for: first),
            ScreenContextClassifier.fingerprint(for: second)
        )
    }
}
