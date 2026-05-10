import XCTest
@testable import NotesGuyCore

final class DuplicateFrameDetectorTests: XCTestCase {
    func testFirstFrameIsProcessed() {
        var detector = DuplicateFrameDetector(threshold: 4)

        XCTAssertTrue(detector.shouldProcess(samples: [0, 1, 2, 3, 4, 5, 6, 7]))
    }

    func testIdenticalFrameIsSkipped() {
        var detector = DuplicateFrameDetector(threshold: 4)
        let frame = Array(UInt8(0)..<UInt8(64))

        XCTAssertTrue(detector.shouldProcess(samples: frame))
        XCTAssertFalse(detector.shouldProcess(samples: frame))
    }

    func testDifferentFrameIsProcessed() {
        var detector = DuplicateFrameDetector(threshold: 4)
        let dark = Array(repeating: UInt8(0), count: 64)
        let alternating = (0..<64).map { UInt8($0 % 2 == 0 ? 0 : 255) }

        XCTAssertTrue(detector.shouldProcess(samples: dark))
        XCTAssertTrue(detector.shouldProcess(samples: alternating))
    }
}
