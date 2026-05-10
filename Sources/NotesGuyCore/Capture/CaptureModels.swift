import Foundation

public enum CapturePermissionStatus: String, Codable, Equatable, Sendable {
    case unknown
    case available
    case denied
    case unavailable
}

public enum CaptureError: Error, Equatable {
    case permissionDenied(String)
    case unavailable(String)
    case invalidInput(String)
}

public struct ScreenSourceContext: Codable, Equatable, Sendable {
    public var capturedAt: Date
    public var permissionStatus: CapturePermissionStatus
    public var frontmostApplicationName: String?
    public var frontmostBundleIdentifier: String?
    public var visibleWindowTitles: [String]
    public var displayCount: Int
    public var errorMessage: String?

    public init(
        capturedAt: Date = Date(),
        permissionStatus: CapturePermissionStatus = .unknown,
        frontmostApplicationName: String? = nil,
        frontmostBundleIdentifier: String? = nil,
        visibleWindowTitles: [String] = [],
        displayCount: Int = 0,
        errorMessage: String? = nil
    ) {
        self.capturedAt = capturedAt
        self.permissionStatus = permissionStatus
        self.frontmostApplicationName = frontmostApplicationName
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.visibleWindowTitles = visibleWindowTitles
        self.displayCount = displayCount
        self.errorMessage = errorMessage
    }
}

public struct ScreenCaptureConfiguration: Codable, Equatable, Sendable {
    public var sessionID: String
    public var outputDirectory: String
    public var intervalSeconds: TimeInterval
    public var duplicateThreshold: Int

    public init(
        sessionID: String,
        outputDirectory: String,
        intervalSeconds: TimeInterval = 5,
        duplicateThreshold: Int = 4
    ) {
        self.sessionID = sessionID
        self.outputDirectory = outputDirectory
        self.intervalSeconds = intervalSeconds
        self.duplicateThreshold = duplicateThreshold
    }
}

public protocol ScreenCaptureService {
    func preStartContext() async -> ScreenSourceContext
    func start(configuration: ScreenCaptureConfiguration) async throws
    func stop() async throws
}
