import Foundation

public struct ScreenPromptSuggestion: Equatable, Sendable {
    public var shouldPrompt: Bool
    public var title: String
    public var sourceHint: String
    public var sessionType: SessionType
    public var reason: String
    public var fingerprint: String

    public init(
        shouldPrompt: Bool,
        title: String,
        sourceHint: String,
        sessionType: SessionType,
        reason: String,
        fingerprint: String
    ) {
        self.shouldPrompt = shouldPrompt
        self.title = title
        self.sourceHint = sourceHint
        self.sessionType = sessionType
        self.reason = reason
        self.fingerprint = fingerprint
    }
}

public struct ScreenContextClassifier: Sendable {
    public init() {}

    public func classify(_ context: ScreenSourceContext) -> ScreenPromptSuggestion {
        let titles = context.visibleWindowTitles
        let combined = ([context.frontmostApplicationName, context.frontmostBundleIdentifier] + titles)
            .compactMap { $0 }
            .joined(separator: " ")
        let lowercased = combined.lowercased()
        let fingerprint = Self.fingerprint(for: context)

        if isSelfContext(lowercased) {
            return suggestion(
                shouldPrompt: false,
                context: context,
                sessionType: .general,
                reason: "Ignoring Notes Guy window",
                fingerprint: fingerprint
            )
        }

        if containsAny(lowercased, ["youtube", "youtu.be", "ytimg", "watch?"]) {
            return suggestion(
                shouldPrompt: true,
                context: context,
                sessionType: .youtube,
                reason: "YouTube/video page detected",
                fingerprint: fingerprint
            )
        }

        if containsAny(lowercased, [
            "vimeo", "twitch", "coursera", "udemy", "khan academy",
            "lecture", "video", "player", "watch", "recording"
        ]) {
            return suggestion(
                shouldPrompt: true,
                context: context,
                sessionType: .general,
                reason: "Video-like learning context detected",
                fingerprint: fingerprint
            )
        }

        if isBrowserContext(lowercased) {
            return suggestion(
                shouldPrompt: false,
                context: context,
                sessionType: .general,
                reason: "Browser context detected; use Take note now for articles or blogs",
                fingerprint: fingerprint
            )
        }

        if containsAny(lowercased, ["zoom", "google meet", "meet.google", "microsoft teams"]) {
            return suggestion(
                shouldPrompt: true,
                context: context,
                sessionType: .meeting,
                reason: "Meeting/video call detected",
                fingerprint: fingerprint
            )
        }

        if containsAny(lowercased, ["arxiv", "paper", ".pdf", "pdf"]) {
            return suggestion(
                shouldPrompt: false,
                context: context,
                sessionType: .paper,
                reason: "Paper/article context detected; prompt disabled for non-video by default",
                fingerprint: fingerprint
            )
        }

        return suggestion(
            shouldPrompt: false,
            context: context,
            sessionType: .general,
            reason: "No video context detected",
            fingerprint: fingerprint
        )
    }

    private func suggestion(
        shouldPrompt: Bool,
        context: ScreenSourceContext,
        sessionType: SessionType,
        reason: String,
        fingerprint: String
    ) -> ScreenPromptSuggestion {
        let title = bestTitle(from: context)
        let sourceHint = [
            context.frontmostApplicationName.map { "App: \($0)" },
            context.visibleWindowTitles.isEmpty ? nil : "Windows: \(context.visibleWindowTitles.joined(separator: " | "))",
            "Reason: \(reason)"
        ]
            .compactMap { $0 }
            .joined(separator: "\n")

        return ScreenPromptSuggestion(
            shouldPrompt: shouldPrompt,
            title: title,
            sourceHint: sourceHint,
            sessionType: sessionType,
            reason: reason,
            fingerprint: fingerprint
        )
    }

    private func bestTitle(from context: ScreenSourceContext) -> String {
        context.visibleWindowTitles.first { title in
            let lowercased = title.lowercased()
            return lowercased.contains("youtube") ||
                lowercased.contains("vimeo") ||
                lowercased.contains("lecture") ||
                lowercased.contains("video") ||
                lowercased.contains("watch")
        } ?? context.visibleWindowTitles.first ?? context.frontmostApplicationName ?? "Screen learning session"
    }

    private func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }

    private func isSelfContext(_ value: String) -> Bool {
        value.contains("notes-guy") ||
            value.contains("notes guy")
    }

    private func isBrowserContext(_ value: String) -> Bool {
        containsAny(value, [
            "google chrome",
            "com.google.chrome",
            "arc",
            "company.thebrowser.browser",
            "safari",
            "com.apple.safari",
            "brave browser",
            "com.brave.browser",
            "firefox",
            "org.mozilla.firefox",
            "microsoft edge",
            "com.microsoft.edgemac"
        ])
    }

    public static func fingerprint(for context: ScreenSourceContext) -> String {
        ([context.frontmostBundleIdentifier, context.frontmostApplicationName] + context.visibleWindowTitles)
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.isEmpty == false }
            .joined(separator: "|")
    }
}
