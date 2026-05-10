import Foundation

public enum SessionType: String, Codable, CaseIterable, Sendable {
    case youtube
    case blog
    case paper
    case article
    case meeting
    case code
    case general
}

public enum SessionStatus: String, Codable, Sendable {
    case draft
    case recording
    case processing
    case completed
    case failed
}

public struct LearningSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String?
    public var sourceURL: String?
    public var sourceHint: String?
    public var sessionType: SessionType
    public var startedAt: Date
    public var endedAt: Date?
    public var status: SessionStatus
    public var rawArtifactRoot: String
    public var changedWikiPaths: [String]
    public var failureSummary: String?

    public init(
        id: String,
        title: String? = nil,
        sourceURL: String? = nil,
        sourceHint: String? = nil,
        sessionType: SessionType = .general,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: SessionStatus = .draft,
        rawArtifactRoot: String,
        changedWikiPaths: [String] = [],
        failureSummary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.sourceHint = sourceHint
        self.sessionType = sessionType
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.rawArtifactRoot = rawArtifactRoot
        self.changedWikiPaths = changedWikiPaths
        self.failureSummary = failureSummary
    }
}

public struct TranscriptChunk: Codable, Equatable, Sendable {
    public var startSeconds: Double
    public var endSeconds: Double
    public var text: String
    public var confidence: Double?
    public var source: String

    public init(startSeconds: Double, endSeconds: Double, text: String, confidence: Double? = nil, source: String) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.confidence = confidence
        self.source = source
    }
}

public struct ScreenObservation: Codable, Equatable, Sendable {
    public enum Importance: String, Codable, Sendable {
        case low
        case medium
        case high
    }

    public var timestampSeconds: Double
    public var screenshotPath: String
    public var summary: String
    public var visibleText: [String]
    public var concepts: [String]
    public var importance: Importance

    public init(
        timestampSeconds: Double,
        screenshotPath: String,
        summary: String,
        visibleText: [String] = [],
        concepts: [String] = [],
        importance: Importance = .medium
    ) {
        self.timestampSeconds = timestampSeconds
        self.screenshotPath = screenshotPath
        self.summary = summary
        self.visibleText = visibleText
        self.concepts = concepts
        self.importance = importance
    }
}

public struct SessionContextObservation: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var elapsedSeconds: Double
    public var appName: String?
    public var bundleIdentifier: String?
    public var windowTitles: [String]
    public var summary: String

    public init(
        timestamp: Date,
        elapsedSeconds: Double,
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        windowTitles: [String] = [],
        summary: String
    ) {
        self.timestamp = timestamp
        self.elapsedSeconds = elapsedSeconds
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitles = windowTitles
        self.summary = summary
    }
}
