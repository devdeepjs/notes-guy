import Foundation

public struct SourceIdentity: Equatable, Sendable {
    public var title: String
    public var sourceURL: String?

    public init(title: String, sourceURL: String?) {
        self.title = title
        self.sourceURL = sourceURL
    }
}

public enum SourceIdentityResolver {
    public static func resolve(
        browserURL: String? = nil,
        browserTitle: String? = nil,
        fallbackTitle: String? = nil,
        sourceHint: String? = nil,
        context: ScreenSourceContext? = nil,
        visibleText: [String] = []
    ) -> SourceIdentity {
        let sourceURL = cleanSourceURL(browserURL) ??
            extractFirstURL(from: sourceSearchText(sourceHint: sourceHint, context: context, visibleText: visibleText))

        if let browserTitle = cleanTitle(browserTitle),
           isGenericSourceTitle(browserTitle) == false {
            return SourceIdentity(title: browserTitle, sourceURL: sourceURL)
        }

        if let sourceURL, let urlTitle = titleFromSourceURL(sourceURL) {
            return SourceIdentity(title: urlTitle, sourceURL: sourceURL)
        }

        if let fallbackTitle = cleanTitle(fallbackTitle),
           isGenericSourceTitle(fallbackTitle) == false {
            return SourceIdentity(title: fallbackTitle, sourceURL: sourceURL)
        }

        if let contextTitle = context?.visibleWindowTitles.compactMap(cleanTitle).first(where: { isGenericSourceTitle($0) == false }) {
            return SourceIdentity(title: contextTitle, sourceURL: sourceURL)
        }

        return SourceIdentity(title: "Screen learning session", sourceURL: sourceURL)
    }

    public static func cleanSourceURL(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
            return nil
        }
        while let last = value.unicodeScalars.last,
              CharacterSet(charactersIn: ".,);]}>\"'").contains(last) {
            value.removeLast()
        }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return value
    }

    public static func extractFirstURL(from value: String) -> String? {
        let pattern = #"https?://[^\s<>"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range, in: value) else {
            return nil
        }
        return cleanSourceURL(String(value[range]))
    }

    public static func titleFromSourceURL(_ sourceURL: String) -> String? {
        guard let url = URL(string: sourceURL),
              let host = url.host?.lowercased() else {
            return nil
        }
        guard let lastComponent = url.pathComponents
            .last(where: { component in
                let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed != "/" && trimmed.isEmpty == false
            }) else {
            return nil
        }

        if host.contains("youtube.com"), lastComponent.lowercased() == "watch" {
            return nil
        }

        let title = titleCaseSlug(lastComponent)
        guard title.isEmpty == false else {
            return nil
        }
        if host.contains("interviewpen.com") {
            return "Interview Pen - \(title)"
        }
        return title
    }

    public static func isGenericSourceTitle(_ title: String) -> Bool {
        let normalized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let exact: Set<String> = [
            "interview pen | system design",
            "interview pen",
            "brave browser",
            "google chrome",
            "safari",
            "firefox",
            "microsoft edge",
            "notes guy",
            "screen learning session"
        ]
        return exact.contains(normalized)
    }

    private static func sourceSearchText(
        sourceHint: String?,
        context: ScreenSourceContext?,
        visibleText: [String]
    ) -> String {
        ([sourceHint, context?.visibleWindowTitles.joined(separator: " ")] + visibleText)
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private static func cleanTitle(_ value: String?) -> String? {
        guard let cleaned = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " "),
              cleaned.isEmpty == false else {
            return nil
        }
        return cleaned
    }

    private static func titleCaseSlug(_ slug: String) -> String {
        slug
            .removingPercentEncoding?
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                let lowercased = word.lowercased()
                return lowercased.prefix(1).uppercased() + lowercased.dropFirst()
            }
            .joined(separator: " ") ?? ""
    }
}
