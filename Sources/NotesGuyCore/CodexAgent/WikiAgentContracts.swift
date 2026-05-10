import Foundation

public enum WikiAgentOperation: String, Codable, Sendable {
    case bootstrapWorkspace
    case ingestSession
    case fileFollowUp
    case lintWiki
}

public enum WikiAgentStatus: String, Codable, Sendable {
    case completed
    case failed
}

public struct WikiAgentRequest: Codable, Equatable, Sendable {
    public var requestID: String
    public var operation: WikiAgentOperation
    public var vaultPath: String
    public var schemaPath: String
    public var indexPath: String
    public var logPath: String
    public var sessionManifestPath: String?
    public var inputPaths: [String]
    public var selectedPages: [String]
    public var discussionText: String?
    public var userInstruction: String
    public var allowedWriteRoots: [String]

    public init(
        requestID: String = UUID().uuidString,
        operation: WikiAgentOperation,
        vaultPath: String,
        schemaPath: String,
        indexPath: String,
        logPath: String,
        sessionManifestPath: String? = nil,
        inputPaths: [String] = [],
        selectedPages: [String] = [],
        discussionText: String? = nil,
        userInstruction: String,
        allowedWriteRoots: [String] = ["Wiki", ".notes-guy/log.md"]
    ) {
        self.requestID = requestID
        self.operation = operation
        self.vaultPath = vaultPath
        self.schemaPath = schemaPath
        self.indexPath = indexPath
        self.logPath = logPath
        self.sessionManifestPath = sessionManifestPath
        self.inputPaths = inputPaths
        self.selectedPages = selectedPages
        self.discussionText = discussionText
        self.userInstruction = userInstruction
        self.allowedWriteRoots = allowedWriteRoots
    }

    public static func ingestSession(
        workspace: WikiWorkspace,
        sessionManifestPath: String,
        userInstruction: String = "Compile this session into useful wiki pages."
    ) -> WikiAgentRequest {
        WikiAgentRequest(
            operation: .ingestSession,
            vaultPath: workspace.vaultURL.path,
            schemaPath: workspace.configuration.schemaPath,
            indexPath: workspace.configuration.indexPath,
            logPath: workspace.configuration.logPath,
            sessionManifestPath: sessionManifestPath,
            userInstruction: userInstruction
        )
    }
}

public struct WikiAgentResult: Codable, Equatable, Sendable {
    public var requestID: String
    public var status: WikiAgentStatus
    public var changedFiles: [String]
    public var createdPages: [String]
    public var updatedPages: [String]
    public var logEntryPath: String?
    public var summary: String
    public var errors: [String]

    public init(
        requestID: String,
        status: WikiAgentStatus,
        changedFiles: [String] = [],
        createdPages: [String] = [],
        updatedPages: [String] = [],
        logEntryPath: String? = nil,
        summary: String,
        errors: [String] = []
    ) {
        self.requestID = requestID
        self.status = status
        self.changedFiles = changedFiles
        self.createdPages = createdPages
        self.updatedPages = updatedPages
        self.logEntryPath = logEntryPath
        self.summary = summary
        self.errors = errors
    }
}
