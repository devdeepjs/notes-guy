import Foundation

public struct LocalWikiEnrichmentSeedResult: Equatable, Sendable {
    public var changedPaths: [String]

    public init(changedPaths: [String]) {
        self.changedPaths = changedPaths
    }
}

public struct LocalWikiEnrichmentSeedWriter: Sendable {
    public init() {}

    @discardableResult
    public func writeSeeds(
        sourceNoteURL: URL,
        sourceNoteRelativePath: String,
        workspace: WikiWorkspace,
        sessionID: String
    ) throws -> LocalWikiEnrichmentSeedResult {
        let markdown = try String(contentsOf: sourceNoteURL, encoding: .utf8)
        let sourceTitle = frontmatterValue("title", in: markdown) ?? headingTitle(in: markdown) ?? sourceNoteURL.deletingPathExtension().lastPathComponent
        let links = wikiLinks(in: markdown)
            .filter { isDurableWikiPath($0.path) }

        var changedPaths: [String] = []
        for link in links where FileManager.default.fileExists(atPath: workspace.configuration.url(for: link.path).path) == false {
            try writeSeedPage(
                link: link,
                sourceTitle: sourceTitle,
                sourceNoteRelativePath: sourceNoteRelativePath,
                sourceMarkdown: markdown,
                workspace: workspace
            )
            changedPaths.append(link.path)
        }

        let indexChanged = try upsertIndexEntries(
            sourceTitle: sourceTitle,
            sourceNoteRelativePath: sourceNoteRelativePath,
            links: links,
            workspace: workspace
        )
        if indexChanged {
            changedPaths.append(workspace.configuration.indexPath)
        }

        let topicChanged = try upsertTopicLinks(
            sourceTitle: sourceTitle,
            sourceNoteRelativePath: sourceNoteRelativePath,
            links: links,
            workspace: workspace
        )
        changedPaths.append(contentsOf: topicChanged)

        if changedPaths.isEmpty == false {
            try appendLog(
                changedPaths: changedPaths,
                sourceTitle: sourceTitle,
                sourceNoteRelativePath: sourceNoteRelativePath,
                workspace: workspace,
                sessionID: sessionID
            )
            changedPaths.append(workspace.configuration.logPath)
        }

        return LocalWikiEnrichmentSeedResult(changedPaths: stableUnique(changedPaths))
    }

    private func writeSeedPage(
        link: WikiLink,
        sourceTitle: String,
        sourceNoteRelativePath: String,
        sourceMarkdown: String,
        workspace: WikiWorkspace
    ) throws {
        let noteURL = workspace.configuration.url(for: link.path)
        try FileManager.default.createDirectory(at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let title = link.title
        let type = pageType(for: link.path)
        let excerpt = sourceBackedExcerpt(for: title, sourceMarkdown: sourceMarkdown)
        let content = """
        ---
        title: "\(escapeYAML(title))"
        type: "\(type)"
        status: "seed"
        tags:
          - notes-guy
        sources:
          - "[[\(sourceNoteRelativePath)|\(escapeYAML(sourceTitle))]]"
        ---

        # \(title)

        ## Atomic Idea

        This page was created immediately from [[\(sourceNoteRelativePath)|\(sourceTitle)]] so the source is connected into the durable wiki before slow enrichment finishes.

        ## Source-Backed Notes

        \(excerpt)

        ## Related Source

        - [[\(sourceNoteRelativePath)|\(sourceTitle)]]

        ## Questions To Grow This Note

        - Which examples from the source should become permanent examples here?
        - Which tradeoffs or failure modes need a deeper note?
        """
        try content.write(to: noteURL, atomically: true, encoding: .utf8)
    }

    private func upsertIndexEntries(
        sourceTitle: String,
        sourceNoteRelativePath: String,
        links: [WikiLink],
        workspace: WikiWorkspace
    ) throws -> Bool {
        var index = (try? String(contentsOf: workspace.indexURL, encoding: .utf8)) ?? WikiWorkspace.defaultIndexMarkdown
        let before = index
        upsertEntry("- [[\(sourceNoteRelativePath)|\(sourceTitle)]]", section: "## Source Notes", in: &index)
        for link in links {
            upsertEntry("- [[\(link.path)|\(link.title)]]", section: section(for: link.path), in: &index)
        }
        guard index != before else {
            return false
        }
        try index.write(to: workspace.indexURL, atomically: true, encoding: .utf8)
        return true
    }

    private func upsertTopicLinks(
        sourceTitle: String,
        sourceNoteRelativePath: String,
        links: [WikiLink],
        workspace: WikiWorkspace
    ) throws -> [String] {
        let topicLinks = links.filter { $0.path.hasPrefix("\(workspace.configuration.wikiRoot)/topics/") }
        var changed: [String] = []
        for topic in topicLinks {
            let topicURL = workspace.configuration.url(for: topic.path)
            guard FileManager.default.fileExists(atPath: topicURL.path) else {
                continue
            }
            var markdown = try String(contentsOf: topicURL, encoding: .utf8)
            let before = markdown
            let sourceEntry = "- [[\(sourceNoteRelativePath)|\(sourceTitle)]] - source note captured for this topic."
            upsertEntry(sourceEntry, section: "## Source Notes", in: &markdown)
            for link in links where link.path != topic.path && link.path.hasPrefix("\(workspace.configuration.wikiRoot)/concepts/") {
                let conceptEntry = "- [[\(link.path)|\(link.title)]] - concept seeded from [[\(sourceNoteRelativePath)|\(sourceTitle)]]."
                upsertEntry(conceptEntry, section: "## Start Here", in: &markdown)
            }
            if markdown != before {
                try markdown.write(to: topicURL, atomically: true, encoding: .utf8)
                changed.append(topic.path)
            }
        }
        return changed
    }

    private func appendLog(
        changedPaths: [String],
        sourceTitle: String,
        sourceNoteRelativePath: String,
        workspace: WikiWorkspace,
        sessionID: String
    ) throws {
        if FileManager.default.fileExists(atPath: workspace.logURL.path) == false {
            try WikiWorkspace.defaultLogMarkdown.write(to: workspace.logURL, atomically: true, encoding: .utf8)
        }
        let changed = stableUnique(changedPaths).map { "`\($0)`" }.joined(separator: ", ")
        let entry = "\n- Local seed enrichment for `\(sessionID)` connected [[\(sourceNoteRelativePath)|\(sourceTitle)]] into durable wiki pages: \(changed).\n"
        let handle = try FileHandle(forWritingTo: workspace.logURL)
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(Data(entry.utf8))
    }

    private func sourceBackedExcerpt(for title: String, sourceMarkdown: String) -> String {
        let headingPattern = #"(?m)^###\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: headingPattern) else {
            return "- Seed page created from the linked source note. Slow enrichment should replace this with a durable explanation."
        }
        let matches = regex.matches(in: sourceMarkdown, range: NSRange(sourceMarkdown.startIndex..., in: sourceMarkdown))
        for (index, match) in matches.enumerated() {
            guard let titleRange = Range(match.range(at: 1), in: sourceMarkdown) else {
                continue
            }
            let heading = String(sourceMarkdown[titleRange])
            guard fuzzyMatch(title, heading) else {
                continue
            }
            let sectionStart = Range(match.range, in: sourceMarkdown)?.upperBound ?? sourceMarkdown.startIndex
            let sectionEnd: String.Index
            if index + 1 < matches.count,
               let nextRange = Range(matches[index + 1].range, in: sourceMarkdown) {
                sectionEnd = nextRange.lowerBound
            } else if let nextH2 = sourceMarkdown.range(of: "\n## ", range: sectionStart..<sourceMarkdown.endIndex) {
                sectionEnd = nextH2.lowerBound
            } else {
                sectionEnd = sourceMarkdown.endIndex
            }
            let section = sourceMarkdown[sectionStart..<sectionEnd]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if section.isEmpty == false {
                return section
                    .split(separator: "\n")
                    .prefix(12)
                    .joined(separator: "\n")
            }
        }
        return "- Seed page created from the linked source note. Slow enrichment should replace this with a durable explanation."
    }

    private func frontmatterValue(_ key: String, in markdown: String) -> String? {
        let pattern = #"(?m)^\#(key):\s*"?([^"\n]+)"?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)),
              let range = Range(match.range(at: 1), in: markdown) else {
            return nil
        }
        return String(markdown[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func headingTitle(in markdown: String) -> String? {
        let pattern = #"(?m)^#\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)),
              let range = Range(match.range(at: 1), in: markdown) else {
            return nil
        }
        return String(markdown[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func wikiLinks(in markdown: String) -> [WikiLink] {
        let pattern = #"\[\[(Wiki\/[^\]|]+)(?:\|([^\]]+))?\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        var links: [WikiLink] = []
        var seen = Set<String>()
        for match in regex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)) {
            guard let pathRange = Range(match.range(at: 1), in: markdown) else {
                continue
            }
            let path = String(markdown[pathRange])
            guard seen.insert(path).inserted else {
                continue
            }
            let title: String
            if match.range(at: 2).location != NSNotFound,
               let titleRange = Range(match.range(at: 2), in: markdown) {
                title = String(markdown[titleRange])
            } else {
                title = titleFromPath(path)
            }
            links.append(WikiLink(path: path, title: title))
        }
        return links
    }

    private func isDurableWikiPath(_ path: String) -> Bool {
        path.hasPrefix("Wiki/concepts/") ||
            path.hasPrefix("Wiki/topics/") ||
            path.hasPrefix("Wiki/syntheses/") ||
            path.hasPrefix("Wiki/guides/")
    }

    private func pageType(for path: String) -> String {
        if path.hasPrefix("Wiki/topics/") { return "topic-note" }
        if path.hasPrefix("Wiki/syntheses/") { return "synthesis-note" }
        if path.hasPrefix("Wiki/guides/") { return "guide" }
        return "concept-note"
    }

    private func section(for path: String) -> String {
        if path.hasPrefix("Wiki/topics/") { return "## Topics" }
        if path.hasPrefix("Wiki/syntheses/") { return "## Syntheses" }
        if path.hasPrefix("Wiki/guides/") { return "## Guides" }
        return "## Concepts"
    }

    private func upsertEntry(_ entry: String, section: String, in markdown: inout String) {
        guard markdown.contains(entry) == false else {
            return
        }
        if let range = markdown.range(of: section) {
            let insertAt = markdown.index(after: range.upperBound)
            markdown.insert(contentsOf: "\n\(entry)", at: insertAt)
        } else {
            markdown.append("\n\(section)\n\n\(entry)\n")
        }
    }

    private func titleFromPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private func fuzzyMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = Set(lhs.lowercased().split(separator: " ").map(String.init))
        let right = Set(rhs.lowercased().split(separator: " ").map(String.init))
        return left.isSubset(of: right) || right.isSubset(of: left) || left.intersection(right).count >= min(2, left.count)
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func escapeYAML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

private struct WikiLink: Equatable {
    var path: String
    var title: String
}
