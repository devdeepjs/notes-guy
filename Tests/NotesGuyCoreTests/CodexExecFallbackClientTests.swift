import XCTest
@testable import NotesGuyCore

final class CodexExecFallbackClientTests: XCTestCase {
    func testBuildPromptContainsSchemaAndRawArtifactRules() throws {
        let client = CodexExecFallbackClient(codexExecutablePath: "/usr/local/bin/codex")
        let request = WikiAgentRequest(
            requestID: "req-1",
            operation: .ingestSession,
            vaultPath: "/tmp/vault",
            schemaPath: ".notes-guy/schema.md",
            indexPath: "Wiki/index.md",
            logPath: ".notes-guy/log.md",
            sessionManifestPath: ".notes-guy/raw/session-1/manifest.json",
            userInstruction: "Compile this session."
        )

        let prompt = try client.buildPrompt(for: request)

        XCTAssertTrue(prompt.contains("Follow the schema file before writing"))
        XCTAssertTrue(prompt.contains("Preserve raw artifacts"))
        XCTAssertTrue(prompt.contains(#""operation" : "ingestSession""#))
        XCTAssertTrue(prompt.contains(#""request_id" : "req-1""#))
    }

    func testParsePlainOutputFallsBackToCompletedResult() throws {
        let result = try CodexExecFallbackClient().parseResult(
            output: "Updated Wiki/index.md",
            requestID: "req-2"
        )

        XCTAssertEqual(result.requestID, "req-2")
        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(result.summary, "Updated Wiki/index.md")
    }

    func testCodexResolverPrefersConfiguredExecutableThenCandidatesInOrder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-guy-codex-resolver-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let configured = root.appendingPathComponent("configured-codex")
        let newer = root.appendingPathComponent("newer-codex")
        let stale = root.appendingPathComponent("stale-codex")
        for url in [configured, newer, stale] {
            try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        XCTAssertEqual(
            CodexExecutableResolver.resolve(
                configuredPath: configured.path,
                candidatePaths: [stale.path, newer.path]
            ),
            configured.path
        )
        XCTAssertEqual(
            CodexExecutableResolver.resolve(
                configuredPath: nil,
                candidatePaths: [newer.path, stale.path]
            ),
            newer.path
        )
    }
}
