import Foundation

public struct ImmediateSourceNoteDraftWriter: Sendable {
    public init() {}

    public func writeDraft(
        noteURL: URL,
        session: LearningSession,
        rawURL: URL,
        observations: [SessionContextObservation]
    ) throws {
        let frameEvidence = loadFrameEvidence(rawURL: rawURL)
        let visibleText = salientVisibleText(from: frameEvidence)
        let sourceIdentity = SourceIdentityResolver.resolve(
            browserURL: session.sourceURL,
            browserTitle: session.title,
            fallbackTitle: session.title,
            sourceHint: session.sourceHint,
            visibleText: visibleText + observations.flatMap { [$0.summary] + $0.windowTitles }
        )
        let concepts = inferredConcepts(session: session, visibleText: visibleText, observations: observations)
        let relatedNotes = relatedNotes(for: concepts, session: session)
        let title = sourceIdentity.title
        let markdown = buildMarkdown(
            title: title,
            sourceIdentity: sourceIdentity,
            session: session,
            rawURL: rawURL,
            observations: observations,
            frameEvidence: frameEvidence,
            visibleText: visibleText,
            concepts: concepts,
            relatedNotes: relatedNotes
        )
        try markdown.write(to: noteURL, atomically: true, encoding: .utf8)
    }

    private func buildMarkdown(
        title: String,
        sourceIdentity: SourceIdentity,
        session: LearningSession,
        rawURL: URL,
        observations: [SessionContextObservation],
        frameEvidence: [FrameEvidence],
        visibleText: [String],
        concepts: [String],
        relatedNotes: [String]
    ) -> String {
        let date = Self.dayFormatter.string(from: session.startedAt)
        let sourceTitle = sourceIdentity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let capturedRange = captureRange(session: session, observations: observations, frames: frameEvidence)
        let conceptsYAML = concepts.isEmpty
            ? "  - \"Screen Learning\""
            : concepts.map { "  - \"\(escapeYAML($0))\"" }.joined(separator: "\n")
        let relatedYAML = relatedNotes.isEmpty
            ? "  - \"[[Wiki/index.md|index]]\""
            : relatedNotes.map { "  - \"[[\(escapeYAML($0))]]\"" }.joined(separator: "\n")
        let sourceNotes = sourceNotesSection(
            concepts: concepts,
            visibleText: visibleText,
            session: session,
            sourceIdentity: sourceIdentity
        )
        let sourceAnchors = sourceAnchorsSection(frames: frameEvidence)
        let screenEvidence = screenEvidenceSection(visibleText)
        let links = relatedNotes.isEmpty
            ? "- [[Wiki/index.md|index]] - wiki entry point"
            : relatedNotes.map { "- [[\($0)]] - related wiki page" }.joined(separator: "\n")

        return """
        ---
        title: "\(escapeYAML(title))"
        date: "\(date)"
        type: "source-note"
        source_type: "\(session.sessionType.rawValue)"
        source_url: "\(escapeYAML(sourceIdentity.sourceURL ?? ""))"
        source_title: "\(escapeYAML(sourceTitle.isEmpty ? title : sourceTitle))"
        captured_range: "\(escapeYAML(capturedRange))"
        session: "\(session.id)"
        status: "source-draft"
        primary_concepts:
        \(conceptsYAML)
        related_notes:
        \(relatedYAML)
        ---

        # \(title)

        ## Why This Matters

        This note was written immediately when capture stopped, before any slow transcript or Codex enrichment finished. It preserves the usable screen context now so the file is not left as a raw starter note.

        ## Source Notes

        \(sourceNotes)

        ## Screen Evidence

        \(screenEvidence)

        ## Links Into The Wiki

        \(links)

        ## Open Questions

        - What did the audio/transcript add that is not visible in the screen evidence?
        - Which concepts should be split into permanent concept notes after enrichment?
        - Which examples from the source should become interview or implementation prompts?

        ## Source Anchors

        \(sourceAnchors)

        ## Raw Evidence

        - Raw session folder: `\(relativeRawPath(rawURL, session: session))`
        - Session id: `\(session.id)`
        - Audio may exist under the raw session folder if microphone capture was available.
        """
    }

    private func sourceNotesSection(
        concepts: [String],
        visibleText: [String],
        session: LearningSession,
        sourceIdentity: SourceIdentity
    ) -> String {
        let conceptSet = Set(concepts)
        if conceptSet.contains("Database Fundamentals") || conceptSet.contains("Database Schema Design") {
            return """
            ### Database Fundamentals

            A database choice in system design is a cluster of storage decisions: schema, CRUD paths, indexes, replication, sharding, consistency, transactions, and database type.

            ### Schema And Relationships

            The captured screen evidence points at ecommerce-style entities such as products, reviews, customers, and orders when those terms are visible. The useful design move is to name relationships, cardinality, identifiers, and access patterns instead of only listing entities.

            ### Operations And Scale

            CRUD separates create, read, update, and delete paths. Indexing supports specific reads. Replication copies data for availability or read scale. Sharding splits data ownership across nodes and makes shard-key choice central.
            """
        }

        if conceptSet.contains("Distributed Queues") {
            return """
            ### Distributed Queues

            A distributed queue decouples producers from consumers while preserving durable message handoff across more than one machine. The design question is not just "where do messages go"; it is how the system owns ordering, retries, acknowledgements, visibility timeouts, backpressure, partitioning, and failure recovery.

            ### Durable Use

            Treat this source as system-design material for queue semantics, broker architecture, partitioned consumption, delivery guarantees, and operational failure modes. The enrichment pass should split durable pages for queues, message delivery guarantees, retries, and partitioning when enough transcript or screenshot evidence exists.
            """
        }

        if conceptSet.contains("Java") {
            return """
            ### Java Study Material

            The capture appears to be Java reference or tutorial material. Treat it as a seed for syntax, object-oriented structure, collections, exceptions, concurrency, and interview recall prompts.

            ### Durable Use

            Convert any visible examples into a cheat sheet and keep code snippets separate from conceptual distinctions.
            """
        }

        if conceptSet.contains("Deep Learning") || conceptSet.contains("Neural Networks") {
            return """
            ### Learning System

            The capture appears to focus on machine learning or neural network material. Preserve the reusable concept first: inputs, representations, transformations, learned parameters, outputs, and training signal.

            ### Durable Use

            Keep examples as evidence for invariances or mechanisms, not as passive video recap.
            """
        }

        let fallback = visibleText.prefix(8).joined(separator: "; ")
        let context = (sourceIdentity.sourceURL ?? session.sourceURL ?? session.sourceHint ?? fallback)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        ### Captured Context

        The capture produced enough source context to create a seed note, but not enough structured transcript to write a final concept page locally.

        ### Durable Use

        Use this as a source-bound draft. The Codex enrichment pass should turn the source URL, window title, OCR, transcript if present, and screenshots into permanent wiki pages.

        Context: \(context.isEmpty ? "current screen capture" : context)
        """
    }

    private func screenEvidenceSection(_ visibleText: [String]) -> String {
        let items = visibleText.prefix(12)
        guard items.isEmpty == false else {
            return "No useful OCR text was captured. Use the raw screenshots and transcript, if available, for enrichment."
        }
        return items.map { "- \($0)" }.joined(separator: "\n")
    }

    private func sourceAnchorsSection(frames: [FrameEvidence]) -> String {
        let anchors = frames.compactMap { frame -> String? in
            guard let text = salientVisibleText(from: [frame]).first else {
                return nil
            }
            let elapsed = SessionNoteUpdater.durationString(frame.elapsedSeconds ?? 0)
            return "- \(elapsed) - \(text)"
        }
        .prefix(8)

        guard anchors.isEmpty == false else {
            return "- Raw screenshots are available in the session folder."
        }
        return anchors.joined(separator: "\n")
    }

    private func inferredConcepts(
        session: LearningSession,
        visibleText: [String],
        observations: [SessionContextObservation]
    ) -> [String] {
        let haystack = ([session.title, session.sourceURL, session.sourceHint] +
            visibleText +
            observations.flatMap { [$0.summary] + $0.windowTitles })
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        var concepts: [String] = []
        func add(_ concept: String, when terms: [String]) {
            if terms.contains(where: { haystack.contains($0) }), concepts.contains(concept) == false {
                concepts.append(concept)
            }
        }

        add("System Design", when: ["system design", "load balancer", "database", "sharding", "replication"])
        add("Distributed Queues", when: ["distributed queue", "distributed queues", "design-a-distributed-queue", "message queue", "message broker"])
        add("Database Fundamentals", when: ["database-fundamentals", "database fundamentals", "crud", "replication", "sharding", "transactions"])
        add("Database Schema Design", when: ["schema", "products", "reviews", "customers", "orders", "relational"])
        add("Indexing", when: ["index", "indexes", "indexing"])
        add("Replication", when: ["replication", "replica", "master", "slave", "primary"])
        add("Sharding", when: ["sharding", "shard"])
        add("Java", when: ["java", "jvm", "class", "interface", "arraylist", "hashmap"])
        add("Deep Learning", when: ["deep learning", "neural network", "mnist", "gradient", "weights"])
        add("Neural Networks", when: ["neural network", "weights", "activation"])

        if concepts.isEmpty, let title = session.title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            concepts.append(title)
        }
        return concepts
    }

    private func relatedNotes(for concepts: [String], session: LearningSession) -> [String] {
        var notes: [String] = []
        func add(_ note: String) {
            if notes.contains(note) == false {
                notes.append(note)
            }
        }

        for concept in concepts {
            switch concept {
            case "System Design":
                add("Wiki/topics/system-design.md|System Design")
            case "Distributed Queues":
                add("Wiki/concepts/distributed-queues.md|Distributed Queues")
                add("Wiki/guides/distributed-queues-for-system-design-interviews.md|Distributed Queues for System Design Interviews")
                add("Wiki/topics/system-design.md|System Design")
            case "Database Fundamentals":
                add("Wiki/guides/database-fundamentals-for-system-design-interviews.md|Database Fundamentals for System Design Interviews")
                add("Wiki/topics/system-design.md|System Design")
            case "Database Schema Design":
                add("Wiki/concepts/database-schema-design.md|Database Schema Design")
                add("Wiki/guides/database-schema-design-for-system-design-interviews.md|Database Schema Design for System Design Interviews")
            case "Java":
                add("Wiki/topics/java.md|Java")
                add("Wiki/concepts/java-language-cheat-sheet.md|Java Language Cheat Sheet")
            case "Deep Learning", "Neural Networks":
                add("Wiki/topics/deep-learning.md|Deep Learning")
                add("Wiki/concepts/handwritten-digit-recognition.md|Handwritten Digit Recognition")
            default:
                continue
            }
        }

        if notes.isEmpty, session.sessionType == .code {
            add("Wiki/topics/code-notes.md|Code Notes")
        }
        return notes
    }

    private func navigationTitle(for session: LearningSession, visibleText: [String]) -> String {
        if let sourceURL = session.sourceURL,
           let url = URL(string: sourceURL),
           let host = url.host?.lowercased() {
            let slugTitle = url.pathComponents
                .last(where: { $0 != "/" && $0.isEmpty == false })?
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")

            if host.contains("interviewpen"), let slugTitle, slugTitle.isEmpty == false {
                return "Interview Pen - \(slugTitle)"
            }
            if host.contains("youtube"), let title = session.title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return title.replacingOccurrences(of: " - YouTube", with: "")
            }
            if let slugTitle, slugTitle.isEmpty == false {
                return slugTitle
            }
        }

        if let title = session.title?.trimmingCharacters(in: .whitespacesAndNewlines), title.isEmpty == false {
            return title
        }

        if let firstText = visibleText.first {
            return String(firstText.prefix(80))
        }
        return "Screen Learning Session"
    }

    private func captureRange(
        session: LearningSession,
        observations: [SessionContextObservation],
        frames: [FrameEvidence]
    ) -> String {
        if let endedAt = session.endedAt {
            return "0:00-\(SessionNoteUpdater.durationString(endedAt.timeIntervalSince(session.startedAt)))"
        }
        let maxObservation = observations.map(\.elapsedSeconds).max() ?? 0
        let maxFrame = frames.compactMap(\.elapsedSeconds).max() ?? 0
        return "0:00-\(SessionNoteUpdater.durationString(max(maxObservation, maxFrame)))"
    }

    private func relativeRawPath(_ rawURL: URL, session: LearningSession) -> String {
        if session.rawArtifactRoot.isEmpty == false {
            return session.rawArtifactRoot
        }
        return rawURL.path
    }

    private func loadFrameEvidence(rawURL: URL) -> [FrameEvidence] {
        let framesURL = rawURL.appendingPathComponent("frames.jsonl")
        guard let content = try? String(contentsOf: framesURL, encoding: .utf8) else {
            return []
        }

        return content
            .split(separator: "\n")
            .compactMap { line in
                guard let data = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let dict = object as? [String: Any] else {
                    return nil
                }
                return FrameEvidence(
                    elapsedSeconds: dict["elapsed_seconds"] as? Double,
                    screenshotPath: dict["screenshot_path"] as? String,
                    visibleText: dict["visible_text"] as? [String] ?? []
                )
            }
    }

    private func salientVisibleText(from frames: [FrameEvidence]) -> [String] {
        var seen = Set<String>()
        var results: [String] = []
        for text in frames.flatMap(\.visibleText) {
            let cleaned = cleanVisibleText(text)
            guard isUsefulVisibleText(cleaned), seen.insert(cleaned.lowercased()).inserted else {
                continue
            }
            results.append(cleaned)
            if results.count >= 24 {
                break
            }
        }
        return results
    }

    private func cleanVisibleText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isUsefulVisibleText(_ value: String) -> Bool {
        let lowered = value.lowercased()
        guard value.count >= 3 else {
            return false
        }
        let ignoredExact: Set<String> = [
            "brave", "file", "edit", "view", "history", "bookmarks", "profiles",
            "tab window", "help", "search", "pricing", "home", "courses", "overview"
        ]
        if ignoredExact.contains(lowered) {
            return false
        }
        if lowered.contains("sat ") || lowered.contains("to exit full screen") {
            return false
        }
        return true
    }

    private func escapeYAML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct FrameEvidence {
    var elapsedSeconds: Double?
    var screenshotPath: String?
    var visibleText: [String]
}
