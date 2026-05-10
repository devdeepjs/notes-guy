import XCTest
@testable import NotesGuyCore

final class VaultWorkspaceTests: XCTestCase {
    func testDefaultVaultPathUsesDocumentsNotesGuyVault() {
        let home = URL(fileURLWithPath: "/tmp/test-home", isDirectory: true)
        let defaultURL = VaultConfiguration.defaultVaultURL(homeDirectory: home)

        XCTAssertEqual(defaultURL.path, "/tmp/test-home/Documents/Notes Guy Vault")
    }

    func testVaultStoreUsesEnvironmentOverride() {
        let configuration = VaultStore.configurationFromEnvironment(
            environment: ["NOTES_GUY_VAULT": "/tmp/custom-notes"]
        )

        XCTAssertEqual(configuration.vaultPath, URL(fileURLWithPath: "/tmp/custom-notes").standardizedFileURL.path)
    }

    func testBootstrapCreatesDefaultWorkspaceFiles() throws {
        let root = try temporaryDirectory()
        let vaultURL = root.appendingPathComponent("notes", isDirectory: true)
        let configuration = VaultConfiguration(vaultURL: vaultURL)
        let workspace = WikiWorkspace(configuration: configuration)

        let result = try workspace.bootstrap()

        XCTAssertEqual(result.vaultURL.path, vaultURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.schemaURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.indexURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.logURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.sessionsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.rawRootURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.wikiRootURL.appendingPathComponent("concepts").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.wikiRootURL.appendingPathComponent("topics").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.wikiRootURL.appendingPathComponent("syntheses").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.wikiRootURL.appendingPathComponent("guides").path))
        XCTAssertTrue(result.changedFiles.contains(".notes-guy/schema.md"))
        XCTAssertTrue(result.changedFiles.contains("Wiki/index.md"))

        let schema = try String(contentsOf: workspace.schemaURL, encoding: .utf8)
        XCTAssertTrue(schema.contains("## Navigation Model"))
        XCTAssertTrue(schema.contains("Wiki/sources/"))
        XCTAssertTrue(schema.contains("Wiki/concepts/"))
        XCTAssertTrue(schema.contains("Wiki/guides/"))
        XCTAssertTrue(schema.contains("## Enrichment Rules"))

        let index = try String(contentsOf: workspace.indexURL, encoding: .utf8)
        XCTAssertTrue(index.contains("## Source Notes"))
        XCTAssertTrue(index.contains("## Concepts"))
        XCTAssertTrue(index.contains("## Topics"))
        XCTAssertTrue(index.contains("## Syntheses"))
        XCTAssertTrue(index.contains("## Guides"))
    }

    func testBootstrapIsIdempotent() throws {
        let root = try temporaryDirectory()
        let workspace = WikiWorkspace(configuration: VaultConfiguration(vaultURL: root.appendingPathComponent("notes")))

        let first = try workspace.bootstrap()
        let second = try workspace.bootstrap()

        XCTAssertFalse(first.changedFiles.isEmpty)
        XCTAssertEqual(second.changedFiles, [])
    }

    func testBootstrapMigratesExistingWorkspaceWithGuides() throws {
        let root = try temporaryDirectory()
        let workspace = WikiWorkspace(configuration: VaultConfiguration(vaultURL: root.appendingPathComponent("notes")))
        try FileManager.default.createDirectory(at: workspace.schemaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace.indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Schema\n\n## Navigation Model\n\n- `Wiki/concepts/` contains concepts.\n"
            .write(to: workspace.schemaURL, atomically: true, encoding: .utf8)
        try "# Wiki Index\n\n## Source Notes\n\n## Concepts\n\n## Topics\n\n## Syntheses\n"
            .write(to: workspace.indexURL, atomically: true, encoding: .utf8)

        let result = try workspace.bootstrap()

        XCTAssertTrue(result.changedFiles.contains(".notes-guy/schema.md"))
        XCTAssertTrue(result.changedFiles.contains("Wiki/index.md"))

        let schema = try String(contentsOf: workspace.schemaURL, encoding: .utf8)
        XCTAssertTrue(schema.contains("Wiki/guides/"))

        let index = try String(contentsOf: workspace.indexURL, encoding: .utf8)
        XCTAssertTrue(index.contains("## Guides"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-guy-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
