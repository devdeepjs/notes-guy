import XCTest
@testable import NotesGuyCore

final class WikiAgentContractsTests: XCTestCase {
    func testIngestRequestEncodesSnakeCaseContract() throws {
        let workspace = WikiWorkspace(configuration: VaultConfiguration(vaultPath: "/tmp/vault"))
        let request = WikiAgentRequest.ingestSession(
            workspace: workspace,
            sessionManifestPath: ".notes-guy/raw/session-1/manifest.json"
        )

        let data = try JSONEncoder.notesGuyPretty.encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["operation"] as? String, "ingestSession")
        XCTAssertEqual(json["vault_path"] as? String, URL(fileURLWithPath: "/tmp/vault").standardizedFileURL.path)
        XCTAssertEqual(json["schema_path"] as? String, ".notes-guy/schema.md")
        XCTAssertEqual(json["session_manifest_path"] as? String, ".notes-guy/raw/session-1/manifest.json")
        XCTAssertEqual(json["allowed_write_roots"] as? [String], ["Wiki", ".notes-guy/log.md"])
    }
}
