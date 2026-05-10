import Foundation

public struct SessionNoteUpdater: Sendable {
    public init() {}

    public func appendObservation(_ observation: SessionContextObservation, to noteURL: URL) throws {
        var markdown = try loadMarkdown(from: noteURL)
        ensureSection("## Observed Timeline", in: &markdown)

        let elapsed = Self.durationString(observation.elapsedSeconds)
        let line = "- [\(elapsed)] \(observation.summary)\n"
        if markdown.contains(line) == false {
            markdown.append(line)
        }

        try write(markdown, to: noteURL)
    }

    public func appendVisualObservation(
        elapsedSeconds: Double,
        screenshotRelativePath: String,
        visibleText: [String],
        to noteURL: URL
    ) throws {
        var markdown = try loadMarkdown(from: noteURL)
        ensureSection("## Visual Timeline", in: &markdown)

        let elapsed = Self.durationString(elapsedSeconds)
        let excerpt = visibleText
            .prefix(4)
            .joined(separator: " / ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let text = excerpt.isEmpty ? "screen frame captured" : excerpt
        let line = "- [\(elapsed)] `\(screenshotRelativePath)` - \(text)\n"
        if markdown.contains(line) == false {
            markdown.append(line)
        }

        try write(markdown, to: noteURL)
    }

    public func upsertAudioArtifact(_ audioRelativePath: String, to noteURL: URL) throws {
        var markdown = try loadMarkdown(from: noteURL)
        let section = """

        <!-- audio-artifact:start -->
        ## Audio

        Recording: `\(audioRelativePath)`
        <!-- audio-artifact:end -->

        """
        replaceMarkedSection(
            startMarker: "<!-- audio-artifact:start -->",
            endMarker: "<!-- audio-artifact:end -->",
            replacement: section,
            in: &markdown
        )
        try write(markdown, to: noteURL)
    }

    public func upsertCaptureStatus(_ lines: [String], to noteURL: URL) throws {
        var markdown = try loadMarkdown(from: noteURL)
        let body = lines.isEmpty ? "- Capture status unavailable." : lines.map { "- \($0)" }.joined(separator: "\n")
        let section = """

        <!-- capture-status:start -->
        ## Capture Status

        \(body)
        <!-- capture-status:end -->

        """
        replaceMarkedSection(
            startMarker: "<!-- capture-status:start -->",
            endMarker: "<!-- capture-status:end -->",
            replacement: section,
            in: &markdown
        )
        try write(markdown, to: noteURL)
    }

    public func upsertTranscript(_ chunks: [TranscriptChunk], to noteURL: URL) throws {
        var markdown = try loadMarkdown(from: noteURL)
        let transcript = chunks
            .map { "- [\(Self.durationString($0.startSeconds))] \($0.text)" }
            .joined(separator: "\n")
        let section = """

        <!-- audio-transcript:start -->
        ## Audio Transcript

        \(transcript.isEmpty ? "No transcript text was produced." : transcript)
        <!-- audio-transcript:end -->

        """
        replaceMarkedSection(
            startMarker: "<!-- audio-transcript:start -->",
            endMarker: "<!-- audio-transcript:end -->",
            replacement: section,
            in: &markdown
        )
        try write(markdown, to: noteURL)
    }

    public func upsertTranscriptStatus(_ message: String, to noteURL: URL) throws {
        var markdown = try loadMarkdown(from: noteURL)
        let section = """

        <!-- audio-transcript:start -->
        ## Audio Transcript

        \(message)
        <!-- audio-transcript:end -->

        """
        replaceMarkedSection(
            startMarker: "<!-- audio-transcript:start -->",
            endMarker: "<!-- audio-transcript:end -->",
            replacement: section,
            in: &markdown
        )
        try write(markdown, to: noteURL)
    }

    public func upsertTranscriptNotes(_ notes: YouTubeCaptionNote, to noteURL: URL) throws {
        var markdown = try loadMarkdown(from: noteURL)
        let section = """

        <!-- transcript-notes:start -->
        ## Transcript Notes

        Source: [\(notes.title)](\(notes.webpageURL))

        Captions saved at: `\(notes.transcriptRelativePath)`

        ### Key Points

        \(notes.keyPoints.map { "- \($0)" }.joined(separator: "\n"))

        ### Transcript Excerpt

        \(Self.blockquote(notes.excerpt))
        <!-- transcript-notes:end -->

        """
        replaceMarkedSection(
            startMarker: "<!-- transcript-notes:start -->",
            endMarker: "<!-- transcript-notes:end -->",
            replacement: section,
            in: &markdown
        )
        try write(markdown, to: noteURL)
    }

    public func upsertTranscriptFailure(_ message: String, to noteURL: URL) throws {
        var markdown = try loadMarkdown(from: noteURL)
        let section = """

        <!-- transcript-notes:start -->
        ## Transcript Notes

        Captions were not available automatically.

        Reason: \(message)
        <!-- transcript-notes:end -->

        """
        replaceMarkedSection(
            startMarker: "<!-- transcript-notes:start -->",
            endMarker: "<!-- transcript-notes:end -->",
            replacement: section,
            in: &markdown
        )
        try write(markdown, to: noteURL)
    }

    public func finalize(
        noteURL: URL,
        session: LearningSession,
        observations: [SessionContextObservation],
        endedAt: Date
    ) throws {
        var markdown = try loadMarkdown(from: noteURL)
        markdown = markdown.replacingOccurrences(of: "status: draft", with: "status: completed")

        let duration = Self.durationString(endedAt.timeIntervalSince(session.startedAt))
        let appList = Set(observations.compactMap(\.appName)).sorted()
        let section = """

        <!-- session-summary:start -->
        ## Session Summary

        Duration: \(duration)

        Status: completed

        Apps observed: \(appList.isEmpty ? "current screen" : appList.joined(separator: ", "))

        Observations captured: \(observations.count)
        <!-- session-summary:end -->

        """
        replaceMarkedSection(
            startMarker: "<!-- session-summary:start -->",
            endMarker: "<!-- session-summary:end -->",
            replacement: section,
            in: &markdown
        )
        try write(markdown, to: noteURL)
    }

    private func loadMarkdown(from noteURL: URL) throws -> String {
        try String(contentsOf: noteURL, encoding: .utf8)
    }

    private func write(_ markdown: String, to noteURL: URL) throws {
        try markdown.write(to: noteURL, atomically: true, encoding: .utf8)
    }

    private func ensureSection(_ heading: String, in markdown: inout String) {
        if markdown.contains(heading) == false {
            markdown.append("\n\(heading)\n\n")
        }
        if markdown.hasSuffix("\n") == false {
            markdown.append("\n")
        }
    }

    private func replaceMarkedSection(
        startMarker: String,
        endMarker: String,
        replacement: String,
        in markdown: inout String
    ) {
        guard let start = markdown.range(of: startMarker),
              let end = markdown.range(of: endMarker, range: start.upperBound..<markdown.endIndex) else {
            markdown.append(replacement)
            return
        }

        markdown.replaceSubrange(start.lowerBound..<end.upperBound, with: replacement.trimmingCharacters(in: .newlines))
        if markdown.hasSuffix("\n") == false {
            markdown.append("\n")
        }
    }

    public static func durationString(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static func blockquote(_ value: String) -> String {
        value
            .split(separator: "\n")
            .map { "> \($0)" }
            .joined(separator: "\n")
    }
}
