import Foundation

public struct VaultStore: Sendable {
    public var configuration: VaultConfiguration

    public init(configuration: VaultConfiguration = VaultConfiguration()) {
        self.configuration = configuration
    }

    public init(vaultPath: String?) {
        if let vaultPath, vaultPath.isEmpty == false {
            self.configuration = VaultConfiguration(vaultPath: vaultPath)
        } else {
            self.configuration = VaultConfiguration()
        }
    }

    public static func configurationFromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> VaultConfiguration {
        if let path = environment["NOTES_GUY_VAULT"], path.isEmpty == false {
            return VaultConfiguration(vaultPath: path)
        }
        return VaultConfiguration()
    }

    public func workspace() -> WikiWorkspace {
        WikiWorkspace(configuration: configuration)
    }

    @discardableResult
    public func bootstrap(fileManager: FileManager = .default) throws -> WikiWorkspace.BootstrapResult {
        try workspace().bootstrap(fileManager: fileManager)
    }
}
