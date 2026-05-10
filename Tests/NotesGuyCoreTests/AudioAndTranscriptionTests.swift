import XCTest
@testable import NotesGuyCore

final class AudioAndTranscriptionTests: XCTestCase {
    func testAudioImportCopiesFileIntoSessionAudioDirectory() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("sample.m4a")
        try Data([1, 2, 3]).write(to: source)
        let audioDirectory = root.appendingPathComponent("session/audio", isDirectory: true)

        let artifact = try AudioImportService().importAudioFile(from: source, into: audioDirectory)

        XCTAssertEqual(artifact.mode, .importedAudio)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.path))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: artifact.path)), Data([1, 2, 3]))
    }

    func testImportedTranscriptServiceCreatesSingleChunk() async throws {
        let root = try temporaryDirectory()
        let transcript = root.appendingPathComponent("transcript.txt")
        try "KV cache avoids recomputing attention keys.".write(to: transcript, atomically: true, encoding: .utf8)

        let chunks = try await ImportedTranscriptService().transcribe(
            TranscriptionRequest(sourceURL: transcript, source: "imported-transcript")
        )

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].startSeconds, 0)
        XCTAssertEqual(chunks[0].source, "imported-transcript")
        XCTAssertEqual(chunks[0].text, "KV cache avoids recomputing attention keys.")
    }

    func testTranscriptWriterWritesJsonAndText() throws {
        let root = try temporaryDirectory()
        let json = root.appendingPathComponent("transcript.json")
        let text = root.appendingPathComponent("transcript.txt")
        let chunks = [
            TranscriptChunk(startSeconds: 0, endSeconds: 1, text: "hello", source: "imported-transcript"),
            TranscriptChunk(startSeconds: 1, endSeconds: 2, text: "world", source: "imported-transcript")
        ]

        try TranscriptWriter().write(chunks, jsonURL: json, textURL: text)

        XCTAssertTrue(FileManager.default.fileExists(atPath: json.path))
        XCTAssertEqual(try String(contentsOf: text, encoding: .utf8), "hello\n\nworld\n")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-guy-audio-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
