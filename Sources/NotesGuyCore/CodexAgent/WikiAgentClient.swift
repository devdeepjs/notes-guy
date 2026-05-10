import Foundation

public protocol WikiAgentClient: Sendable {
    func run(_ request: WikiAgentRequest) async throws -> WikiAgentResult
}

public struct StubWikiAgentClient: WikiAgentClient {
    public init() {}

    public func run(_ request: WikiAgentRequest) async throws -> WikiAgentResult {
        WikiAgentResult(
            requestID: request.requestID,
            status: .completed,
            changedFiles: [],
            summary: "Stub agent completed \(request.operation.rawValue)."
        )
    }
}
