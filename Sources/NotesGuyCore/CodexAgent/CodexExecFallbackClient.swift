import Foundation

public enum CodexExecFallbackError: Error, Equatable {
    case nonZeroExit(Int32, String)
    case noOutput
}

public enum CodexExecutableResolver {
    public static func resolve(
        configuredPath: String? = ProcessInfo.processInfo.environment["NOTES_GUY_CODEX_PATH"],
        candidatePaths: [String] = defaultCandidatePaths()
    ) -> String? {
        if let configured = configuredPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           configured.isEmpty == false,
           FileManager.default.isExecutableFile(atPath: configured) {
            return configured
        }

        return candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    public static func defaultPath() -> String {
        resolve() ?? defaultCandidatePaths().first ?? "codex"
    }

    public static func defaultCandidatePaths() -> [String] {
        var candidates: [String] = []
        func add(_ path: String) {
            guard path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  candidates.contains(path) == false else {
                return
            }
            candidates.append(path)
        }

        add(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".homebrew/bin/codex").path)
        add("/opt/homebrew/bin/codex")
        add("/usr/local/bin/codex")

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":").map(String.init) {
                add(URL(fileURLWithPath: directory).appendingPathComponent("codex").path)
            }
        }

        return candidates
    }
}

public struct CodexExecFallbackClient: WikiAgentClient {
    public var codexExecutablePath: String

    public init(codexExecutablePath: String? = nil) {
        self.codexExecutablePath = codexExecutablePath ?? CodexExecutableResolver.defaultPath()
    }

    public func run(_ request: WikiAgentRequest) async throws -> WikiAgentResult {
        let prompt = try buildPrompt(for: request)
        let output = try runCodex(vaultPath: request.vaultPath, prompt: prompt)
        return try parseResult(output: output, requestID: request.requestID)
    }

    public func processArguments(for request: WikiAgentRequest) throws -> [String] {
        [
            "exec",
            "--skip-git-repo-check",
            "--json",
            "-C",
            request.vaultPath,
            try buildPrompt(for: request)
        ]
    }

    public func buildPrompt(for request: WikiAgentRequest) throws -> String {
        let data = try JSONEncoder.notesGuyPretty.encode(request)
        let json = String(decoding: data, as: UTF8.self)
        return """
        You are the notes-guy wiki agent.

        Follow the schema file before writing. Preserve raw artifacts. Write only inside allowed_write_roots.
        Return the final answer as a single JSON object matching WikiAgentResult.

        <wiki_agent_request>
        \(json)
        </wiki_agent_request>
        """
    }

    private func runCodex(vaultPath: String, prompt: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexExecutablePath)
        process.arguments = [
            "exec",
            "--skip-git-repo-check",
            "--json",
            "-C",
            vaultPath,
            prompt
        ]

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-guy-codex-agent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let stdoutURL = outputDirectory.appendingPathComponent("stdout.log")
        let stderrURL = outputDirectory.appendingPathComponent("stderr.log")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        process.waitUntilExit()

        stdoutHandle.synchronizeFile()
        stderrHandle.synchronizeFile()
        let output = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let errorOutput = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""

        guard process.terminationStatus == 0 else {
            throw CodexExecFallbackError.nonZeroExit(process.terminationStatus, errorOutput)
        }

        guard output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw CodexExecFallbackError.noOutput
        }

        return output
    }

    public func parseResult(output: String, requestID: String) throws -> WikiAgentResult {
        let lines = output
            .split(separator: "\n")
            .map(String.init)
            .reversed()

        for line in lines {
            guard let data = line.data(using: .utf8) else {
                continue
            }
            if let result = try? JSONDecoder.notesGuy.decode(WikiAgentResult.self, from: data) {
                return result
            }
            if
                let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let message = event["message"] as? String,
                let messageData = message.data(using: .utf8),
                let result = try? JSONDecoder.notesGuy.decode(WikiAgentResult.self, from: messageData)
            {
                return result
            }
        }

        return WikiAgentResult(
            requestID: requestID,
            status: .completed,
            summary: output.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
