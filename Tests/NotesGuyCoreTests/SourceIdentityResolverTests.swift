import XCTest
@testable import NotesGuyCore

final class SourceIdentityResolverTests: XCTestCase {
    func testGenericInterviewPenTitleUsesBrowserURLSlug() {
        let identity = SourceIdentityResolver.resolve(
            browserURL: "https://interviewpen.com/courses/system-design/database-optimization",
            browserTitle: "Interview Pen | System Design",
            fallbackTitle: "Interview Pen | System Design",
            sourceHint: "App: Brave Browser"
        )

        XCTAssertEqual(identity.sourceURL, "https://interviewpen.com/courses/system-design/database-optimization")
        XCTAssertEqual(identity.title, "Interview Pen - Database Optimization")
    }

    func testURLCanBeRecoveredFromSourceHintWhenBrowserAutomationFails() {
        let identity = SourceIdentityResolver.resolve(
            browserURL: nil,
            browserTitle: "Interview Pen | System Design",
            fallbackTitle: "Interview Pen | System Design",
            sourceHint: "Windows: Interview Pen | System Design\nURL: https://interviewpen.com/courses/system-design/data-models-and-types-of-databases)."
        )

        XCTAssertEqual(identity.sourceURL, "https://interviewpen.com/courses/system-design/data-models-and-types-of-databases")
        XCTAssertEqual(identity.title, "Interview Pen - Data Models And Types Of Databases")
    }

    func testSpecificBrowserTitleWinsOverURLDerivedTitle() {
        let identity = SourceIdentityResolver.resolve(
            browserURL: "https://example.com/articles/raw-slug",
            browserTitle: "Database Optimization - Interview Pen",
            fallbackTitle: "Interview Pen | System Design"
        )

        XCTAssertEqual(identity.sourceURL, "https://example.com/articles/raw-slug")
        XCTAssertEqual(identity.title, "Database Optimization - Interview Pen")
    }

    func testURLCanBeRecoveredFromVisibleText() {
        let identity = SourceIdentityResolver.resolve(
            browserURL: nil,
            browserTitle: "Brave Browser",
            fallbackTitle: "Screen learning session",
            visibleText: ["https://interviewpen.com/courses/system-design/database-optimization"]
        )

        XCTAssertEqual(identity.sourceURL, "https://interviewpen.com/courses/system-design/database-optimization")
        XCTAssertEqual(identity.title, "Interview Pen - Database Optimization")
    }
}
