import Foundation

public struct StarterNoteWriter: Sendable {
    public init() {}

    public func writeStarterNote(
        for session: LearningSession,
        workspace: WikiWorkspace,
        now: Date = Date(),
        publishToIndex: Bool = false
    ) throws -> String {
        let title = cleanTitle(session.title ?? "Learning Session")
        let slug = Self.slug(for: title)
        let sessionSlug = Self.slug(for: session.id)
        let relativePath = "\(workspace.configuration.wikiRoot)/sources/\(slug)-\(sessionSlug).md"
        let noteURL = workspace.configuration.url(for: relativePath)
        try FileManager.default.createDirectory(at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let content = markdown(
            title: title,
            session: session,
            relativeRawPath: session.rawArtifactRoot,
            now: now
        )
        try content.write(to: noteURL, atomically: true, encoding: .utf8)
        if publishToIndex {
            try appendIndexEntry(title: title, relativePath: relativePath, workspace: workspace)
        }
        return relativePath
    }

    private func markdown(title: String, session: LearningSession, relativeRawPath: String, now: Date) -> String {
        let created = ISO8601DateFormatter().string(from: now)
        let sourceHint = (session.sourceHint ?? "Captured from current screen").trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        ---
        title: "\(title.replacingOccurrences(of: "\"", with: "\\\""))"
        type: "source-note"
        source_type: "\(session.sessionType.rawValue)"
        source_url: "\(session.sourceURL ?? "")"
        created: \(created)
        session: \(session.id)
        status: "capture-in-progress"
        primary_concepts: []
        ---

        # \(title)

        ## Source Context

        \(sourceHint.isEmpty ? "Started from current screen." : sourceHint)

        ## Notes

        Recording started. This note will update as the session runs.

        ## Observed Timeline

        - Session started. Waiting for screen context and transcript signals.

        ## Evidence

        Raw session folder: `\(relativeRawPath)`

        ## See Also

        - [[Wiki/index.md|index]]

        """
    }

    private func appendIndexEntry(title: String, relativePath: String, workspace: WikiWorkspace) throws {
        let indexURL = workspace.indexURL
        var index = (try? String(contentsOf: indexURL, encoding: .utf8)) ?? WikiWorkspace.defaultIndexMarkdown
        let entry = "- [[\(relativePath)|\(title)]]\n"
        if index.contains(entry) == false {
            if let range = index.range(of: "## Source Notes\n") {
                index.insert(contentsOf: "\n\(entry)", at: range.upperBound)
            } else if let range = index.range(of: "## Sources\n") {
                index.insert(contentsOf: "\n\(entry)", at: range.upperBound)
            } else {
                index.append("\n## Source Notes\n\n\(entry)")
            }
            try index.write(to: indexURL, atomically: true, encoding: .utf8)
        }
    }

    private func cleanTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Learning Session" : trimmed
    }

    public static func slug(for value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "- "))
        let filtered = value
            .lowercased()
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(filtered)
            .replacingOccurrences(of: " ", with: "-")
            .split(separator: "-")
            .filter { $0.isEmpty == false }
            .joined(separator: "-")
        return collapsed.isEmpty ? "learning-session" : String(collapsed.prefix(80))
    }
}
