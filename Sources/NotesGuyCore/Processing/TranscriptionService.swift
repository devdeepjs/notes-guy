import Foundation

#if canImport(Speech)
import Speech
#endif

public struct TranscriptionRequest: Equatable, Sendable {
    public var sourceURL: URL
    public var source: String

    public init(sourceURL: URL, source: String) {
        self.sourceURL = sourceURL
        self.source = source
    }
}

public protocol TranscriptionService {
    func transcribe(_ request: TranscriptionRequest) async throws -> [TranscriptChunk]
}

public struct ImportedTranscriptService: TranscriptionService {
    public init() {}

    public func transcribe(_ request: TranscriptionRequest) async throws -> [TranscriptChunk] {
        let text = try String(contentsOf: request.sourceURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard text.isEmpty == false else {
            return []
        }

        return [
            TranscriptChunk(
                startSeconds: 0,
                endSeconds: 0,
                text: text,
                confidence: nil,
                source: request.source
            )
        ]
    }
}

public struct TranscriptWriter {
    public init() {}

    public func write(_ chunks: [TranscriptChunk], jsonURL: URL, textURL: URL) throws {
        try FileManager.default.createDirectory(at: jsonURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.notesGuyPretty.encode(chunks)
        try data.write(to: jsonURL, options: .atomic)

        let plainText = chunks.map(\.text).joined(separator: "\n\n") + (chunks.isEmpty ? "" : "\n")
        try plainText.write(to: textURL, atomically: true, encoding: .utf8)
    }
}

public enum SpeechTranscriptionError: Error, Equatable, LocalizedError {
    case unavailable
    case notAuthorized
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "macOS speech recognition is unavailable."
        case .notAuthorized:
            return "Speech recognition permission is not authorized."
        case .failed(let message):
            return message
        }
    }
}

public final class MacOSSpeechTranscriptionService: NSObject, TranscriptionService, @unchecked Sendable {
    public override init() {}

    public func transcribe(_ request: TranscriptionRequest) async throws -> [TranscriptChunk] {
        #if canImport(Speech)
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard authorization == .authorized else {
            throw SpeechTranscriptionError.notAuthorized
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw SpeechTranscriptionError.unavailable
        }

        let recognitionRequest = SFSpeechURLRecognitionRequest(url: request.sourceURL)
        recognitionRequest.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            _ = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let error {
                    guard didResume == false else { return }
                    didResume = true
                    continuation.resume(throwing: SpeechTranscriptionError.failed(error.localizedDescription))
                    return
                }

                guard let result, result.isFinal else {
                    return
                }

                guard didResume == false else { return }
                didResume = true
                let chunks = Self.chunkSegments(result.bestTranscription.segments, source: request.source)
                continuation.resume(returning: chunks)
            }
        }
        #else
        throw SpeechTranscriptionError.unavailable
        #endif
    }

    #if canImport(Speech)
    private static func chunkSegments(_ segments: [SFTranscriptionSegment], source: String) -> [TranscriptChunk] {
        var chunks: [TranscriptChunk] = []
        var chunkStart: TimeInterval?
        var chunkEnd: TimeInterval = 0
        var words: [String] = []
        var confidenceTotal: Float = 0
        var confidenceCount: Int = 0

        func flush() {
            guard let start = chunkStart, words.isEmpty == false else {
                return
            }
            let text = words
                .joined(separator: " ")
                .replacingOccurrences(of: " ,", with: ",")
                .replacingOccurrences(of: " .", with: ".")
                .replacingOccurrences(of: " ?", with: "?")
                .replacingOccurrences(of: " !", with: "!")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            chunks.append(
                TranscriptChunk(
                    startSeconds: start,
                    endSeconds: chunkEnd,
                    text: text,
                    confidence: confidenceCount == 0 ? nil : Double(confidenceTotal / Float(confidenceCount)),
                    source: source
                )
            )
            chunkStart = nil
            chunkEnd = 0
            words.removeAll(keepingCapacity: true)
            confidenceTotal = 0
            confidenceCount = 0
        }

        for segment in segments {
            let word = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
            guard word.isEmpty == false else {
                continue
            }

            if chunkStart == nil {
                chunkStart = segment.timestamp
            }

            words.append(word)
            chunkEnd = segment.timestamp + segment.duration
            confidenceTotal += segment.confidence
            confidenceCount += 1

            let duration = chunkEnd - (chunkStart ?? chunkEnd)
            let endsSentence = word.hasSuffix(".") || word.hasSuffix("?") || word.hasSuffix("!")
            if duration >= 10 || words.count >= 35 || (endsSentence && duration >= 4) {
                flush()
            }
        }

        flush()
        return chunks
    }
    #endif
}
