import Foundation

public enum SessionStoreError: Error, Equatable {
    case sessionNotFound(String)
}

public struct SessionStore {
    public var workspace: WikiWorkspace
    public var fileManager: FileManager

    public init(workspace: WikiWorkspace, fileManager: FileManager = .default) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    public func loadSessions() throws -> [LearningSession] {
        guard fileManager.fileExists(atPath: workspace.sessionsURL.path) else {
            return []
        }
        let data = try Data(contentsOf: workspace.sessionsURL)
        if data.isEmpty {
            return []
        }
        return try JSONDecoder.notesGuy.decode([LearningSession].self, from: data)
    }

    public func saveSessions(_ sessions: [LearningSession]) throws {
        try fileManager.createDirectory(
            at: workspace.sessionsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.notesGuyPretty.encode(sessions)
        try data.write(to: workspace.sessionsURL, options: .atomic)
    }

    @discardableResult
    public func upsert(_ session: LearningSession) throws -> [LearningSession] {
        var sessions = try loadSessions()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        sessions.sort { $0.startedAt < $1.startedAt }
        try saveSessions(sessions)
        return sessions
    }

    public func createSession(
        id: String,
        title: String? = nil,
        sourceURL: String? = nil,
        sourceHint: String? = nil,
        sessionType: SessionType = .general,
        startedAt: Date = Date()
    ) throws -> LearningSession {
        let rawRoot = "\(workspace.configuration.rawRoot)/\(id)"
        let rawURL = workspace.rawSessionURL(sessionID: id)
        try fileManager.createDirectory(at: rawURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rawURL.appendingPathComponent("screenshots", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rawURL.appendingPathComponent("audio", isDirectory: true), withIntermediateDirectories: true)

        let session = LearningSession(
            id: id,
            title: title,
            sourceURL: sourceURL,
            sourceHint: sourceHint,
            sessionType: sessionType,
            startedAt: startedAt,
            status: .recording,
            rawArtifactRoot: rawRoot
        )
        try upsert(session)
        try writeManifest(for: session)
        return session
    }

    public func updateStatus(
        sessionID: String,
        status: SessionStatus,
        endedAt: Date? = nil,
        changedWikiPaths: [String]? = nil,
        failureSummary: String? = nil
    ) throws -> LearningSession {
        var sessions = try loadSessions()
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw SessionStoreError.sessionNotFound(sessionID)
        }
        sessions[index].status = status
        sessions[index].endedAt = endedAt ?? sessions[index].endedAt
        sessions[index].changedWikiPaths = changedWikiPaths ?? sessions[index].changedWikiPaths
        sessions[index].failureSummary = failureSummary
        try saveSessions(sessions)
        try writeManifest(for: sessions[index])
        return sessions[index]
    }

    public func writeManifest(for session: LearningSession) throws {
        let manifestURL = workspace.rawSessionURL(sessionID: session.id).appendingPathComponent("manifest.json")
        try fileManager.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.notesGuyPretty.encode(session)
        try data.write(to: manifestURL, options: .atomic)
    }
}
