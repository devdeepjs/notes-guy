import Foundation

public struct WikiWorkspace: Sendable {
    public struct BootstrapResult: Equatable, Sendable {
        public var vaultURL: URL
        public var changedFiles: [String]

        public init(vaultURL: URL, changedFiles: [String]) {
            self.vaultURL = vaultURL
            self.changedFiles = changedFiles
        }
    }

    public var configuration: VaultConfiguration

    public init(configuration: VaultConfiguration) {
        self.configuration = configuration
    }

    public var vaultURL: URL { configuration.vaultURL }
    public var rawRootURL: URL { configuration.url(for: configuration.rawRoot) }
    public var wikiRootURL: URL { configuration.url(for: configuration.wikiRoot) }
    public var schemaURL: URL { configuration.url(for: configuration.schemaPath) }
    public var indexURL: URL { configuration.url(for: configuration.indexPath) }
    public var logURL: URL { configuration.url(for: configuration.logPath) }
    public var sessionsURL: URL { configuration.url(for: configuration.sessionsPath) }
    public var configURL: URL { configuration.url(for: configuration.configPath) }

    public func rawSessionURL(sessionID: String) -> URL {
        rawRootURL.appendingPathComponent(sessionID, isDirectory: true)
    }

    public func bootstrap(fileManager: FileManager = .default) throws -> BootstrapResult {
        var changedFiles: [String] = []

        try createDirectory(vaultURL, fileManager: fileManager)
        try createDirectory(configURL.deletingLastPathComponent(), fileManager: fileManager)
        try createDirectory(rawRootURL, fileManager: fileManager)
        try createDirectory(wikiRootURL, fileManager: fileManager)
        try createDirectory(wikiRootURL.appendingPathComponent("sources", isDirectory: true), fileManager: fileManager)
        try createDirectory(wikiRootURL.appendingPathComponent("concepts", isDirectory: true), fileManager: fileManager)
        try createDirectory(wikiRootURL.appendingPathComponent("topics", isDirectory: true), fileManager: fileManager)
        try createDirectory(wikiRootURL.appendingPathComponent("syntheses", isDirectory: true), fileManager: fileManager)
        try createDirectory(wikiRootURL.appendingPathComponent("guides", isDirectory: true), fileManager: fileManager)

        if try writeIfMissing(configurationJSON(), to: configURL, fileManager: fileManager) {
            changedFiles.append(configuration.configPath)
        }
        if try writeIfMissing(Self.defaultSchemaMarkdown, to: schemaURL, fileManager: fileManager) {
            changedFiles.append(configuration.schemaPath)
        } else if try appendIfMissing(Self.guideSchemaMigrationMarkdown, marker: "Wiki/guides/", to: schemaURL, fileManager: fileManager) {
            changedFiles.append(configuration.schemaPath)
        }
        if try writeIfMissing(Self.defaultIndexMarkdown, to: indexURL, fileManager: fileManager) {
            changedFiles.append(configuration.indexPath)
        } else if try appendIfMissing(Self.guidesIndexMigrationMarkdown, marker: "## Guides", to: indexURL, fileManager: fileManager) {
            changedFiles.append(configuration.indexPath)
        }
        if try writeIfMissing(Self.defaultLogMarkdown, to: logURL, fileManager: fileManager) {
            changedFiles.append(configuration.logPath)
        }
        if try writeIfMissing("[]\n", to: sessionsURL, fileManager: fileManager) {
            changedFiles.append(configuration.sessionsPath)
        }

        return BootstrapResult(vaultURL: vaultURL, changedFiles: changedFiles.sorted())
    }

    private func createDirectory(_ url: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func writeIfMissing(_ content: String, to url: URL, fileManager: FileManager) throws -> Bool {
        if fileManager.fileExists(atPath: url.path) {
            return false
        }
        try createDirectory(url.deletingLastPathComponent(), fileManager: fileManager)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    private func appendIfMissing(_ content: String, marker: String, to url: URL, fileManager: FileManager) throws -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }
        let current = try String(contentsOf: url, encoding: .utf8)
        guard !current.contains(marker) else {
            return false
        }
        let separator = current.hasSuffix("\n") ? "\n" : "\n\n"
        try (current + separator + content).write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    private func configurationJSON() throws -> String {
        let encoder = JSONEncoder.notesGuyPretty
        let data = try encoder.encode(configuration)
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}

public extension WikiWorkspace {
    static let defaultSchemaMarkdown = """
    # Notes Guy Schema

    This file tells the wiki agent how to maintain this vault.

    ## Workspace Rules

    - Treat `.notes-guy/raw/` as immutable session evidence.
    - Write user-facing knowledge pages under `Wiki/`.
    - Read `Wiki/index.md` before creating a new page.
    - Append every ingest, follow-up, lint, and repair operation to `.notes-guy/log.md`.
    - Prefer focused source/concept/topic/synthesis/guide pages over one giant session dump.
    - Use explicit Obsidian links such as `[[Wiki/concepts/page.md|Readable Title]]` when a related page exists or is created. Do not use bare links that create empty root notes.
    - Preserve uncertainty. Do not invent details missing from transcript or screenshots.

    ## Navigation Model

    Keep two layers:

    - `Wiki/sources/` contains one source note per captured video, article, paper, meeting, or code session. Its title should stay source-navigation friendly: the actual source title, document title, meeting title, or a concise captured-context title.
    - `Wiki/concepts/`, `Wiki/topics/`, `Wiki/syntheses/`, and `Wiki/guides/` contain durable wiki pages that evolve across many source notes and discussions.
    - `Wiki/guides/` contains enriched study, interview, reference, paper, and implementation guides that may combine source evidence, existing wiki context, and explicitly marked external research when available.

    When a new source arrives, do not leave it isolated. Link it to existing related pages, update those pages with new evidence, and create only the smallest missing concept/topic/synthesis/guide pages.

    ## Naming Rules

    - Source note titles should answer: "Which thing did I watch/read/attend?"
    - Concept note titles should answer: "Which reusable idea is explained here?"
    - Topic note titles should answer: "Which area does this organize?"
    - Synthesis note titles should answer: "Which cross-source comparison or learning map does this maintain?"
    - Guide note titles should answer: "Which reusable study, interview, reference, or implementation guide does this maintain?"
    - Prefer updating an existing matching page over creating a duplicate with a slightly different title.

    ## Page Types

    - Source pages preserve one video, paper, blog, article, meeting, or code session and point into the reusable wiki layer.
    - Concept pages explain reusable ideas across sources.
    - Topic pages organize related concepts.
    - Synthesis pages compare or connect multiple sources.
    - Guide pages turn captured and researched material into study guides, interview guides, paper guides, coding cheat sheets, or implementation references.

    ## Enrichment Rules

    After a source note is ready, enrich the wiki by reading the schema, index, log, source note, and related existing pages.
    Create or update durable pages only when they add reusable knowledge.
    External research is allowed only when the local agent runtime exposes research/search tools; if not available, continue from captured evidence and existing wiki context and state that external research was not performed.
    Do not overwrite unrelated notes. Preserve existing source-backed content and make targeted additions or revisions.

    ## Evidence References

    When useful, refer to raw session evidence with:

    `Evidence: .notes-guy/raw/<session-id>/<file>`

    """

    static let defaultIndexMarkdown = """
    # Wiki Index

    This is the content-oriented map for the personal wiki.

    ## Start Here

    Use topics for navigation, concepts for reusable ideas, syntheses for cross-source learning maps, and source notes for raw session provenance.

    ## Source Notes

    ## Concepts

    ## Topics

    ## Syntheses

    ## Guides

    """

    static let defaultLogMarkdown = """
    # Notes Guy Log

    Append-only timeline of ingest, follow-up, lint, and repair actions.

    """

    static let guideSchemaMigrationMarkdown = """
    ## Guide Pages

    - `Wiki/guides/` contains enriched study, interview, reference, paper, and implementation guides that may combine source evidence, existing wiki context, and explicitly marked external research when available.
    - Prefer guides when a source teaches a reusable workflow, interview pattern, coding reference, research-paper reading, or study map that is larger than one atomic concept.

    """

    static let guidesIndexMigrationMarkdown = """
    ## Guides

    """
}
