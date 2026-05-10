import Foundation

public enum YouTubeCaptionNoteError: Error, Equatable, LocalizedError {
    case ytDLPNotFound
    case commandFailed(Int32, String)
    case noCaptionFile
    case noTranscriptText

    public var errorDescription: String? {
        switch self {
        case .ytDLPNotFound:
            return "yt-dlp was not found on this Mac."
        case .commandFailed(_, let output):
            return output.isEmpty ? "yt-dlp failed." : output
        case .noCaptionFile:
            return "No English caption file was found for this video."
        case .noTranscriptText:
            return "The caption file did not contain readable transcript text."
        }
    }
}

public struct YouTubeCaptionNote: Codable, Equatable, Sendable {
    public var title: String
    public var webpageURL: String
    public var transcriptRelativePath: String
    public var transcriptText: String
    public var keyPoints: [String]
    public var excerpt: String

    public init(
        title: String,
        webpageURL: String,
        transcriptRelativePath: String,
        transcriptText: String,
        keyPoints: [String],
        excerpt: String
    ) {
        self.title = title
        self.webpageURL = webpageURL
        self.transcriptRelativePath = transcriptRelativePath
        self.transcriptText = transcriptText
        self.keyPoints = keyPoints
        self.excerpt = excerpt
    }
}

public struct YouTubeCaptionNoteService: Sendable {
    public var ytDLPPath: String?

    public init(ytDLPPath: String? = nil) {
        self.ytDLPPath = ytDLPPath
    }

    public func fetchNotes(videoURL: String, rawSessionURL: URL) async throws -> YouTubeCaptionNote {
        let path = ytDLPPath
        return try await Task.detached {
            try Self.fetchNotesSynchronously(videoURL: videoURL, rawSessionURL: rawSessionURL, ytDLPPath: path)
        }.value
    }

    private static func fetchNotesSynchronously(
        videoURL: String,
        rawSessionURL: URL,
        ytDLPPath: String?
    ) throws -> YouTubeCaptionNote {
        let executable = try ytDLPPath ?? findYtDLP()
        let captionsURL = rawSessionURL.appendingPathComponent("captions", isDirectory: true)
        try FileManager.default.createDirectory(at: captionsURL, withIntermediateDirectories: true)

        let metadata = try fetchMetadata(executable: executable, videoURL: videoURL)
        let outputTemplate = captionsURL.appendingPathComponent("caption.%(ext)s").path
        _ = try run(
            executable,
            arguments: [
                "--skip-download",
                "--write-subs",
                "--write-auto-subs",
                "--sub-langs", "en.*,en",
                "--sub-format", "vtt",
                "--no-playlist",
                "--output", outputTemplate,
                videoURL
            ]
        )

        let captionURL = try largestCaptionFile(in: captionsURL)
        let vtt = try String(contentsOf: captionURL, encoding: .utf8)
        let transcript = parseVTT(vtt)
        guard transcript.isEmpty == false else {
            throw YouTubeCaptionNoteError.noTranscriptText
        }

        let transcriptURL = rawSessionURL.appendingPathComponent("transcript.txt")
        try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)

        return makeNote(
            title: metadata.title,
            webpageURL: metadata.webpageURL,
            transcriptRelativePath: "\(rawSessionURL.lastPathComponent)/transcript.txt",
            transcript: transcript
        )
    }

    private struct Metadata: Decodable {
        var title: String?
        var fulltitle: String?
        var webpage_url: String?
        var original_url: String?
    }

    private static func fetchMetadata(executable: String, videoURL: String) throws -> (title: String, webpageURL: String) {
        let output = try run(
            executable,
            arguments: ["--dump-json", "--skip-download", "--no-playlist", videoURL]
        )
        let data = Data(output.utf8)
        let metadata = try? JSONDecoder().decode(Metadata.self, from: data)
        let title = metadata?.title ?? metadata?.fulltitle ?? "YouTube Video"
        let webpageURL = metadata?.webpage_url ?? metadata?.original_url ?? videoURL
        return (title, webpageURL)
    }

    private static func findYtDLP() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        let pathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("yt-dlp").path }
        let home = environment["HOME"] ?? NSHomeDirectory()
        let candidates = pathCandidates + [
            "\(home)/Library/Python/3.13/bin/yt-dlp",
            "\(home)/Library/Python/3.12/bin/yt-dlp",
            "\(home)/Library/Python/3.11/bin/yt-dlp",
            "\(home)/Library/Python/3.10/bin/yt-dlp",
            "\(home)/Library/Python/3.9/bin/yt-dlp",
            "\(home)/.local/bin/yt-dlp",
            "\(home)/.homebrew/bin/yt-dlp",
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp"
        ]

        if let path = candidates.first(where: { isWorkingYtDLP(at: $0) }) {
            return path
        }
        throw YouTubeCaptionNoteError.ytDLPNotFound
    }

    private static func isWorkingYtDLP(at path: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-guy-ytdlp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let stdoutURL = outputDirectory.appendingPathComponent("stdout.log")
        let stderrURL = outputDirectory.appendingPathComponent("stderr.log")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        process.waitUntilExit()

        stdoutHandle.synchronizeFile()
        stderrHandle.synchronizeFile()
        let output = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let error = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
        guard process.terminationStatus == 0 else {
            throw YouTubeCaptionNoteError.commandFailed(process.terminationStatus, error + output)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func largestCaptionFile(in captionsURL: URL) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(
            at: captionsURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
            .filter { $0.pathExtension.lowercased() == "vtt" }

        guard let largest = files.max(by: { lhs, rhs in
            fileSize(lhs) < fileSize(rhs)
        }) else {
            throw YouTubeCaptionNoteError.noCaptionFile
        }
        return largest
    }

    private static func fileSize(_ url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    public static func parseVTT(_ vtt: String) -> String {
        var lines: [String] = []
        var previous = ""

        for rawLine in vtt.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.isEmpty == false else { continue }
            guard line != "WEBVTT" else { continue }
            guard line.hasPrefix("Kind:") == false else { continue }
            guard line.hasPrefix("Language:") == false else { continue }
            guard line.hasPrefix("NOTE") == false else { continue }
            guard line.contains("-->") == false else { continue }
            guard Int(line) == nil else { continue }

            let cleaned = line
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard cleaned.isEmpty == false, cleaned != previous else { continue }
            lines.append(cleaned)
            previous = cleaned
        }

        return lines.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func makeNote(
        title: String,
        webpageURL: String,
        transcriptRelativePath: String,
        transcript: String
    ) -> YouTubeCaptionNote {
        let sentences = transcript
            .components(separatedBy: CharacterSet(charactersIn: ".?!"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 35 }

        let keyPoints = Array(sentences.prefix(14)).map { sentence in
            sentence.hasSuffix(".") ? sentence : "\(sentence)."
        }
        let excerpt = String(transcript.prefix(900))

        return YouTubeCaptionNote(
            title: title,
            webpageURL: webpageURL,
            transcriptRelativePath: transcriptRelativePath,
            transcriptText: transcript,
            keyPoints: keyPoints.isEmpty ? [String(transcript.prefix(220))] : keyPoints,
            excerpt: excerpt
        )
    }
}
