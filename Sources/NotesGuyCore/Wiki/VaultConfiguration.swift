import Foundation

public struct VaultConfiguration: Codable, Equatable, Sendable {
    public static let defaultRawRoot = ".notes-guy/raw"
    public static let defaultWikiRoot = "Wiki"
    public static let defaultSchemaPath = ".notes-guy/schema.md"
    public static let defaultIndexPath = "Wiki/index.md"
    public static let defaultLogPath = ".notes-guy/log.md"
    public static let defaultSessionsPath = ".notes-guy/sessions.json"
    public static let defaultConfigPath = ".notes-guy/config.json"

    public var vaultPath: String
    public var rawRoot: String
    public var wikiRoot: String
    public var schemaPath: String
    public var indexPath: String
    public var logPath: String
    public var sessionsPath: String
    public var configPath: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        vaultPath: String,
        rawRoot: String = Self.defaultRawRoot,
        wikiRoot: String = Self.defaultWikiRoot,
        schemaPath: String = Self.defaultSchemaPath,
        indexPath: String = Self.defaultIndexPath,
        logPath: String = Self.defaultLogPath,
        sessionsPath: String = Self.defaultSessionsPath,
        configPath: String = Self.defaultConfigPath,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.vaultPath = URL(fileURLWithPath: vaultPath).standardizedFileURL.path
        self.rawRoot = rawRoot
        self.wikiRoot = wikiRoot
        self.schemaPath = schemaPath
        self.indexPath = indexPath
        self.logPath = logPath
        self.sessionsPath = sessionsPath
        self.configPath = configPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(
        vaultURL: URL = Self.defaultVaultURL(),
        rawRoot: String = Self.defaultRawRoot,
        wikiRoot: String = Self.defaultWikiRoot,
        schemaPath: String = Self.defaultSchemaPath,
        indexPath: String = Self.defaultIndexPath,
        logPath: String = Self.defaultLogPath,
        sessionsPath: String = Self.defaultSessionsPath,
        configPath: String = Self.defaultConfigPath,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.init(
            vaultPath: vaultURL.path,
            rawRoot: rawRoot,
            wikiRoot: wikiRoot,
            schemaPath: schemaPath,
            indexPath: indexPath,
            logPath: logPath,
            sessionsPath: sessionsPath,
            configPath: configPath,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public var vaultURL: URL {
        URL(fileURLWithPath: vaultPath, isDirectory: true)
    }

    public static func defaultVaultURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Notes Guy Vault", isDirectory: true)
    }

    public func url(for relativePath: String) -> URL {
        vaultURL.appendingPathComponent(relativePath)
    }

    public func replacingVaultURL(_ vaultURL: URL) -> VaultConfiguration {
        var copy = self
        copy.vaultPath = vaultURL.standardizedFileURL.path
        copy.updatedAt = Date()
        return copy
    }
}
