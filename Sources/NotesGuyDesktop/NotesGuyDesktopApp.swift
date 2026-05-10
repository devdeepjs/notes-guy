import SwiftUI
import NotesGuyCore

#if canImport(AppKit)
import AppKit
#endif

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(Speech)
import Speech
#endif

#if canImport(Vision)
import Vision
#endif

@main
struct NotesGuyDesktopApp: App {
    @StateObject private var model = NotesGuyViewModel()

    var body: some Scene {
        #if canImport(AppKit)
        MenuBarExtra("Notes Guy", systemImage: "note.text") {
            NotesGuyMenuView(model: model)
        }
        #endif

        Settings {
            NotesGuyRootView(model: model)
        }
    }
}

@MainActor
final class NotesGuyViewModel: ObservableObject {
    @Published var vaultPath: String
    @Published var statusText: String = "Ready"
    @Published var changedFiles: [String] = []
    @Published var lastSessionID: String?
    @Published var currentNotePath: String?
    @Published var detectedContext: ScreenSourceContext?
    @Published var suggestedTitle: String = ""
    @Published var suggestedSourceHint: String = ""
    @Published var suggestedSessionType: SessionType = .general
    @Published var isCheckingScreen = false
    @Published var proactiveWatchingEnabled: Bool
    @Published var proactivePromptVisible = false
    @Published var proactiveReason: String?
    @Published var lastCheckedContextDescription = "Not checked yet"
    @Published var permissionMessage: String?
    @Published var noteToastVisible = false
    @Published var isSessionActive = false
    @Published var activeObservationCount = 0
    @Published var activeFrameCount = 0

    private var watchTask: Task<Void, Never>?
    private var sessionRecorderTask: Task<Void, Never>?
    private var transcriptTasks: [Task<Void, Never>] = []
    private var captionTasks: [Task<Void, Never>] = []
    private var codexRunInProgress = false
    private var pendingCodexStates: [ActiveSessionState] = []
    private var activeSession: ActiveSessionState?
    private var lastUsableContext: ScreenSourceContext?
    private let audioRecorder = MicrophoneAudioCaptureService()
    private var lastPromptFingerprint: String?
    private var attentionRequestID: Int?
    private let classifier = ScreenContextClassifier()
    private static let proactiveWatchingDefaultsKey = "NotesGuyProactiveWatchingEnabled"
    #if canImport(AppKit)
    private let floatingPromptController = FloatingPromptController()
    #endif

    init() {
        self.vaultPath = VaultConfiguration.defaultVaultURL().path
        self.proactiveWatchingEnabled = UserDefaults.standard.object(forKey: Self.proactiveWatchingDefaultsKey) as? Bool ?? false
        bootstrapVault()
        startProactiveWatcherIfNeeded()
    }

    deinit {
        watchTask?.cancel()
        sessionRecorderTask?.cancel()
        transcriptTasks.forEach { $0.cancel() }
        captionTasks.forEach { $0.cancel() }
        #if canImport(AppKit)
        Task { @MainActor [floatingPromptController] in
            floatingPromptController.hide()
        }
        #endif
    }

    func bootstrapVault() {
        do {
            let configuration = VaultConfiguration(vaultPath: vaultPath)
            let result = try VaultStore(configuration: configuration).bootstrap()
            changedFiles = result.changedFiles
            statusText = result.changedFiles.isEmpty ? "Vault already initialized" : "Vault initialized"
        } catch {
            statusText = "Vault setup failed: \(error.localizedDescription)"
        }
    }

    func createPlaceholderSession() {
        startSession(
            title: "Manual test session",
            sourceHint: "Desktop shell placeholder",
            sessionType: .general
        )
    }

    func checkCurrentScreen() {
        isCheckingScreen = true
        statusText = "Checking current screen..."
        let context = usableContextForManualStart()
        detectedContext = context
        isCheckingScreen = false

        guard let context else {
            proactivePromptVisible = false
            statusText = "Switch to the video, then start notes"
            syncFloatingPrompt()
            return
        }

        let suggestion = classifier.classify(context)
        applySuggestion(suggestion, context: context, proactive: false)
        proactivePromptVisible = true
        proactiveReason = suggestion.shouldPrompt ? suggestion.reason : "Start notes for the current screen"
        statusText = "Take notes on this?"
        syncFloatingPrompt()
    }

    func startNoteForCurrentScreen() {
        let context = usableContextForManualStart()
        if let context {
            detectedContext = context
            applySuggestion(classifier.classify(context), context: context, proactive: false)
        } else if detectedContext == nil || Self.isOwnAppContext(detectedContext) {
            statusText = "Switch to the video, then start notes"
            syncFloatingPrompt()
            return
        }
        takeNotesOnDetectedContext()
    }

    func takeNotesOnDetectedContext() {
        if detectedContext == nil || Self.isOwnAppContext(detectedContext) {
            guard let context = lastUsableContext else {
                statusText = "Switch to the video, then start notes"
                proactivePromptVisible = false
                syncFloatingPrompt()
                return
            }
            detectedContext = context
            applySuggestion(classifier.classify(context), context: context, proactive: false)
        }

        let title = suggestedTitle.isEmpty ? "Screen learning session" : suggestedTitle
        let sourceHint = suggestedSourceHint.isEmpty ? detectedContextSummary : suggestedSourceHint
        startSession(
            title: title,
            sourceHint: sourceHint,
            sessionType: suggestedSessionType
        )
        proactivePromptVisible = false
        cancelAttentionRequest()
        if let detectedContext {
            lastPromptFingerprint = ScreenContextClassifier.fingerprint(for: detectedContext)
        }
        statusText = "Taking notes..."
        noteToastVisible = false
        syncFloatingPrompt()
    }

    func stopCurrentSession() {
        guard activeSession != nil else {
            statusText = "No active session"
            return
        }

        guard let state = activeSession else {
            statusText = "No active session"
            return
        }
        sessionRecorderTask?.cancel()
        sessionRecorderTask = nil
        let audioArtifact = try? audioRecorder.stopRecording()

        do {
            let configuration = VaultConfiguration(vaultPath: vaultPath)
            let workspace = WikiWorkspace(configuration: configuration)
            let store = SessionStore(workspace: workspace)
            let completed = try store.updateStatus(
                sessionID: state.session.id,
                status: .completed,
                endedAt: Date(),
                changedWikiPaths: [state.noteRelativePath]
            )
            try SessionNoteUpdater().finalize(
                noteURL: state.noteURL,
                session: completed,
                observations: state.observations,
                endedAt: completed.endedAt ?? Date()
            )
            do {
                try ImmediateSourceNoteDraftWriter().writeDraft(
                    noteURL: state.noteURL,
                    session: completed,
                    rawURL: state.rawURL,
                    observations: state.observations
                )
            } catch {
                try? SessionNoteUpdater().upsertCaptureStatus(
                    ["Immediate source draft failed: \(error.localizedDescription). Starter note and raw evidence were preserved."],
                    to: state.noteURL
                )
            }
            activeSession = nil
            isSessionActive = false
            activeObservationCount = 0
            activeFrameCount = 0
            noteToastVisible = false
            syncFloatingPrompt()
            if let audioArtifact {
                statusText = "Transcribing audio, then writing wiki note..."
                startAudioTranscription(
                    audioArtifact: audioArtifact,
                    state: state,
                    rerunCodexAfterTranscript: true
                )
            } else {
                statusText = "Writing wiki note from screen context..."
                startCodexSynthesis(state: state)
            }
        } catch {
            statusText = "Stop failed: \(error.localizedDescription)"
        }
    }

    func startProactiveWatcherIfNeeded() {
        guard watchTask == nil else {
            return
        }

        watchTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(4))
                guard Task.isCancelled == false else {
                    return
                }
                let enabled = await MainActor.run {
                    self?.proactiveWatchingEnabled ?? false
                }
                guard enabled else {
                    continue
                }

                let context = await MainActor.run {
                    self?.passiveScreenContext()
                }
                await MainActor.run {
                    if let context {
                        self?.handleProactiveContext(context)
                    }
                }
            }
        }
    }

    func setProactiveWatching(_ enabled: Bool) {
        proactiveWatchingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.proactiveWatchingDefaultsKey)
        if enabled {
            permissionMessage = nil
            statusText = "Ask to take notes enabled"
            startProactiveWatcherIfNeeded()
        } else {
            statusText = "Ask to take notes paused"
            proactivePromptVisible = false
            cancelAttentionRequest()
            syncFloatingPrompt()
        }
    }

    func dismissProactivePrompt() {
        setProactiveWatching(false)
        proactivePromptVisible = false
        cancelAttentionRequest()
        if let detectedContext {
            lastPromptFingerprint = ScreenContextClassifier.fingerprint(for: detectedContext)
        }
        statusText = "Ask to take notes paused"
        syncFloatingPrompt()
    }

    func dismissNoteToast() {
        noteToastVisible = false
        syncFloatingPrompt()
    }

    func copyCurrentNotePath() {
        guard let currentNotePath else {
            return
        }
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentNotePath, forType: .string)
        statusText = "Note path copied"
        #endif
    }

    func openCurrentNote() {
        guard let currentNotePath else {
            return
        }
        #if canImport(AppKit)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: currentNotePath)])
        #endif
    }

    func openVaultFolder() {
        #if canImport(AppKit)
        NSWorkspace.shared.open(URL(fileURLWithPath: vaultPath, isDirectory: true))
        #endif
    }

    func openWikiIndex() {
        #if canImport(AppKit)
        let indexURL = URL(fileURLWithPath: vaultPath, isDirectory: true)
            .appendingPathComponent("Wiki")
            .appendingPathComponent("index.md")
        NSWorkspace.shared.activateFileViewerSelecting([indexURL])
        #endif
    }

    func requestCapturePermissionsOnce() {
        statusText = "Requesting permissions..."
        Task {
            let permissions = await Self.requestPermissions()
            await MainActor.run {
                self.permissionMessage = [
                    "Screen: \(permissions.screenRecordingAuthorized ? "granted" : "not granted")",
                    "Microphone: \(permissions.microphoneAuthorized ? "granted" : "not granted")",
                    "Speech: \(permissions.speechAuthorized ? "granted" : "not granted")"
                ].joined(separator: " | ")
                self.statusText = "Permission check complete"
            }
        }
    }

    private func handleProactiveContext(_ context: ScreenSourceContext) {
        lastCheckedContextDescription = context.frontmostApplicationName ?? context.visibleWindowTitles.first ?? "Unknown screen context"
        guard proactiveWatchingEnabled else {
            return
        }
        guard isSessionActive == false else {
            return
        }

        let suggestion = classifier.classify(context)
        if Self.isOwnAppContext(context) == false {
            lastUsableContext = context
        }
        guard proactivePromptVisible == false else {
            return
        }
        guard suggestion.shouldPrompt else {
            if proactivePromptVisible == false {
                statusText = "Watching for videos..."
            }
            return
        }

        guard suggestion.fingerprint != lastPromptFingerprint else {
            return
        }

        detectedContext = context
        applySuggestion(suggestion, context: context, proactive: true)
        proactivePromptVisible = true
        proactiveReason = suggestion.reason
        statusText = "Video detected. Take notes?"
        syncFloatingPrompt()
    }

    private func pauseForPermissionProblem(_ context: ScreenSourceContext) {
        setProactiveWatching(false)
        proactivePromptVisible = false
        cancelAttentionRequest()
        let message = context.errorMessage ?? "Screen permission is not available. Watching paused."
        permissionMessage = message
        statusText = "Permission needed. Watching paused."
        syncFloatingPrompt()
    }

    private func requestAttention() {
        #if canImport(AppKit)
        if attentionRequestID == nil {
            attentionRequestID = NSApp.requestUserAttention(.informationalRequest)
        }
        #endif
    }

    private func passiveScreenContext() -> ScreenSourceContext {
        #if canImport(AppKit)
        let frontmost = NSWorkspace.shared.frontmostApplication
        return ScreenSourceContext(
            permissionStatus: .available,
            frontmostApplicationName: frontmost?.localizedName,
            frontmostBundleIdentifier: frontmost?.bundleIdentifier,
            visibleWindowTitles: Self.visibleWindowTitles(for: frontmost?.processIdentifier),
            displayCount: NSScreen.screens.count
        )
        #else
        return ScreenSourceContext(permissionStatus: .unavailable)
        #endif
    }

    private func usableContextForManualStart() -> ScreenSourceContext? {
        let context = passiveScreenContext()
        if Self.isOwnAppContext(context) {
            return lastUsableContext
        }
        lastUsableContext = context
        return context
    }

    private static func isOwnAppContext(_ context: ScreenSourceContext?) -> Bool {
        guard let context else {
            return false
        }
        let values = [
            context.frontmostApplicationName,
            context.frontmostBundleIdentifier
        ] + context.visibleWindowTitles
        let combined = values
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return combined.contains("dev.notesguy.desktop") ||
            combined.contains("notes-guy") ||
            combined.contains("notes guy") ||
            combined.contains("notes-guy")
    }

    #if canImport(AppKit)
    private static func visibleWindowTitles(for processID: pid_t?) -> [String] {
        guard let processID,
              let infoList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]] else {
            return []
        }

        return infoList
            .filter { info in
                (info[kCGWindowOwnerPID as String] as? pid_t) == processID
            }
            .compactMap { info in
                info[kCGWindowName as String] as? String
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .prefix(8)
            .map { $0 }
    }

    private func currentBrowserSource(bundleID preferredBundleID: String? = nil) -> BrowserSource? {
        guard let bundleID = preferredBundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return nil
        }
        guard let script = Self.browserURLScript(for: bundleID) else {
            return recentBrowserHistorySource(for: bundleID)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let lines = output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
            if let url = lines.first {
                return BrowserSource(url: url, title: lines.dropFirst().first)
            }
        } catch {
        }
        return recentBrowserHistorySource(for: bundleID)
    }

    private func recentBrowserHistorySource(for bundleID: String) -> BrowserSource? {
        let historyPaths = Self.browserHistoryPaths(for: bundleID)
        for historyPath in historyPaths where FileManager.default.fileExists(atPath: historyPath) {
            let copyDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("notes-guy-history-\(UUID().uuidString)", isDirectory: true)
            let copyURL = copyDirectory.appendingPathComponent("History")
            do {
                try FileManager.default.createDirectory(at: copyDirectory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: URL(fileURLWithPath: historyPath), to: copyURL)
                copyHistorySidecar(historyPath: historyPath, suffix: "-wal", copyDirectory: copyDirectory)
                copyHistorySidecar(historyPath: historyPath, suffix: "-shm", copyDirectory: copyDirectory)
                defer { try? FileManager.default.removeItem(at: copyDirectory) }
                if let source = Self.queryRecentYouTubeURL(historyURL: copyURL) {
                    return source
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func copyHistorySidecar(historyPath: String, suffix: String, copyDirectory: URL) {
        let source = "\(historyPath)\(suffix)"
        guard FileManager.default.fileExists(atPath: source) else {
            return
        }
        let destination = copyDirectory.appendingPathComponent("History\(suffix)")
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: source), to: destination)
    }

    private static func browserHistoryPaths(for bundleID: String) -> [String] {
        let home = NSHomeDirectory()
        switch bundleID {
        case "com.google.Chrome":
            return [
                "\(home)/Library/Application Support/Google/Chrome/Default/History",
                "\(home)/Library/Application Support/Google/Chrome/Profile 1/History"
            ]
        case "com.brave.Browser":
            return [
                "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/Default/History",
                "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/Profile 1/History"
            ]
        case "com.microsoft.edgemac":
            return [
                "\(home)/Library/Application Support/Microsoft Edge/Default/History",
                "\(home)/Library/Application Support/Microsoft Edge/Profile 1/History"
            ]
        case "company.thebrowser.Browser":
            return [
                "\(home)/Library/Application Support/Arc/User Data/Default/History",
                "\(home)/Library/Application Support/Arc/User Data/Profile 1/History"
            ]
        default:
            return []
        }
    }

    private static func queryRecentYouTubeURL(historyURL: URL) -> BrowserSource? {
        let query = """
        select url, coalesce(title, '') from urls
        where (url like '%youtube.com/watch%' or url like '%youtu.be/%' or url like '%youtube.com/live/%')
        and last_visit_time > ((strftime('%s','now') - 7200 + 11644473600) * 1000000)
        order by last_visit_time desc
        limit 1;
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-separator", "\t", historyURL.path, query]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let fields = output
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\t")
            guard let url = fields.first, url.isEmpty == false else {
                return nil
            }
            let title = fields.dropFirst().first?.isEmpty == false ? fields.dropFirst().first : nil
            return BrowserSource(url: url, title: title)
        } catch {
            return nil
        }
    }

    private static func browserURLScript(for bundleID: String) -> String? {
        switch bundleID {
        case "com.apple.Safari":
            return """
            tell application id "com.apple.Safari"
              if (count of windows) = 0 then return ""
              return (URL of front document) & linefeed & (name of front document)
            end tell
            """
        case "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser":
            return """
            tell application id "\(bundleID)"
              if (count of windows) = 0 then return ""
              set currentTab to active tab of front window
              return (URL of currentTab) & linefeed & (title of currentTab)
            end tell
            """
        default:
            return nil
        }
    }
    #else
    private func currentBrowserSource() -> BrowserSource? {
        nil
    }
    #endif

    private func cancelAttentionRequest() {
        #if canImport(AppKit)
        if let attentionRequestID {
            NSApp.cancelUserAttentionRequest(attentionRequestID)
            self.attentionRequestID = nil
        }
        #endif
    }

    private func applySuggestion(_ suggestion: ScreenPromptSuggestion, context: ScreenSourceContext, proactive: Bool) {
        detectedContext = context
        suggestedTitle = suggestion.title
        suggestedSourceHint = suggestion.sourceHint
        suggestedSessionType = suggestion.sessionType
        proactiveReason = proactive ? suggestion.reason : nil
    }

    private func startSession(title: String, sourceHint: String, sessionType: SessionType) {
        do {
            let configuration = VaultConfiguration(vaultPath: vaultPath)
            let workspace = WikiWorkspace(configuration: configuration)
            _ = try workspace.bootstrap()
            let store = SessionStore(workspace: workspace)
            let id = Self.sessionID()
            let browserSource = currentBrowserSource(bundleID: detectedContext?.frontmostBundleIdentifier)
            let sourceIdentity = SourceIdentityResolver.resolve(
                browserURL: browserSource?.url,
                browserTitle: browserSource?.title,
                fallbackTitle: title,
                sourceHint: sourceHint,
                context: detectedContext
            )
            let effectiveSourceURL = sourceIdentity.sourceURL
            let sourceURLHintLine: String?
            if let effectiveSourceURL, sourceHint.contains(effectiveSourceURL) == false {
                sourceURLHintLine = "URL: \(effectiveSourceURL)"
            } else {
                sourceURLHintLine = nil
            }
            let effectiveSourceHint = [
                sourceHint,
                sourceURLHintLine
            ]
                .compactMap { $0 }
                .filter { $0.isEmpty == false }
                .joined(separator: "\n")
            let session = try store.createSession(
                id: id,
                title: sourceIdentity.title,
                sourceURL: effectiveSourceURL,
                sourceHint: effectiveSourceHint,
                sessionType: effectiveSourceURL?.isYouTubeURL == true ? .youtube : sessionType
            )
            let noteRelativePath = try StarterNoteWriter().writeStarterNote(for: session, workspace: workspace)
            let noteURL = workspace.configuration.url(for: noteRelativePath)
            let rawURL = workspace.rawSessionURL(sessionID: session.id)
            _ = try store.updateStatus(
                sessionID: session.id,
                status: .recording,
                changedWikiPaths: [noteRelativePath]
            )
            lastSessionID = session.id
            currentNotePath = noteURL.path
            changedFiles = [noteRelativePath]
            noteToastVisible = false
            isSessionActive = true
            activeObservationCount = 0
            let permissions = Self.capturePermissions()
            activeSession = ActiveSessionState(
                session: session,
                noteURL: noteURL,
                noteRelativePath: noteRelativePath,
                rawURL: rawURL,
                permissions: permissions
            )
            writeCaptureStatus(permissions: permissions, noteURL: noteURL)
            startCaptionFetchIfPossible(sourceURL: session.sourceURL)
            startAudioCapture(rawURL: rawURL, noteURL: noteURL)
            startSessionRecorderLoop()
            scheduleInitialCaptureAfterMenuDismissal()
            statusText = "Taking notes..."
            syncFloatingPrompt()
        } catch {
            statusText = "Session creation failed: \(error.localizedDescription)"
        }
    }

    private func scheduleInitialCaptureAfterMenuDismissal() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                guard self?.isSessionActive == true else {
                    return
                }
                self?.recordActiveObservation(force: true)
                self?.captureActiveFrame(force: true)
            }
        }
    }

    private func startSessionRecorderLoop() {
        sessionRecorderTask?.cancel()
        sessionRecorderTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(5))
                await MainActor.run {
                    self?.recordActiveObservation(force: false)
                    self?.captureActiveFrame(force: false)
                }
            }
        }
    }

    private func startAudioCapture(rawURL: URL, noteURL: URL) {
        guard let permissions = activeSession?.permissions, permissions.microphoneAuthorized else {
            try? SessionNoteUpdater().upsertTranscriptStatus(
                "Microphone recording skipped because permission is not already granted.",
                to: noteURL
            )
            return
        }

        let audioURL = rawURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("microphone.m4a")
        do {
            let artifact = try audioRecorder.startRecording(to: audioURL)
            if var state = activeSession {
                state.audioArtifact = artifact
                activeSession = state
            }
            try SessionNoteUpdater().upsertAudioArtifact(
                relativeRawPath(for: audioURL),
                to: noteURL
            )
        } catch {
            try? SessionNoteUpdater().upsertTranscriptStatus(
                "Microphone recording could not start: \(error.localizedDescription)",
                to: noteURL
            )
        }
    }

    private func recordActiveObservation(force: Bool) {
        guard var state = activeSession else {
            return
        }

        let context = passiveScreenContext()
        guard Self.isOwnAppContext(context) == false else {
            return
        }
        let fingerprint = ScreenContextClassifier.fingerprint(for: context)
        if force == false, fingerprint == state.lastObservationFingerprint {
            return
        }

        let observation = SessionContextObservation(
            timestamp: Date(),
            elapsedSeconds: Date().timeIntervalSince(state.session.startedAt),
            appName: context.frontmostApplicationName,
            bundleIdentifier: context.frontmostBundleIdentifier,
            windowTitles: context.visibleWindowTitles,
            summary: observationSummary(for: context)
        )

        do {
            try appendObservationJSONL(observation, to: state.rawURL)
            try SessionNoteUpdater().appendObservation(observation, to: state.noteURL)
            state.observations.append(observation)
            state.lastObservationFingerprint = fingerprint
            activeSession = state
            activeObservationCount = state.observations.count
        } catch {
            statusText = "Observation write failed: \(error.localizedDescription)"
        }
    }

    private func captureActiveFrame(force: Bool) {
        guard var state = activeSession else {
            return
        }
        let context = passiveScreenContext()
        guard Self.isOwnAppContext(context) == false else {
            return
        }
        guard state.permissions.screenRecordingAuthorized else {
            if force {
                try? SessionNoteUpdater().appendVisualObservation(
                    elapsedSeconds: Date().timeIntervalSince(state.session.startedAt),
                    screenshotRelativePath: "screen capture skipped",
                    visibleText: ["Screen capture skipped because permission is not already granted."],
                    to: state.noteURL
                )
            }
            return
        }

        let screenshotDirectory = state.rawURL.appendingPathComponent("screenshots", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
            let timestamp = Self.fileTimestamp()
            let screenshotURL = screenshotDirectory.appendingPathComponent("frame-\(timestamp).png")
            try Self.captureScreenshot(to: screenshotURL)
            let visibleText = Self.recognizeText(in: screenshotURL)
            let relativePath = relativeRawPath(for: screenshotURL)
            try SessionNoteUpdater().appendVisualObservation(
                elapsedSeconds: Date().timeIntervalSince(state.session.startedAt),
                screenshotRelativePath: relativePath,
                visibleText: visibleText,
                to: state.noteURL
            )
            state.frameCount += 1
            activeSession = state
            activeFrameCount = state.frameCount
            try appendFrameJSON(
                screenshotRelativePath: relativePath,
                visibleText: visibleText,
                elapsedSeconds: Date().timeIntervalSince(state.session.startedAt),
                to: state.rawURL
            )
        } catch {
            if force {
                try? SessionNoteUpdater().appendVisualObservation(
                    elapsedSeconds: Date().timeIntervalSince(state.session.startedAt),
                    screenshotRelativePath: "capture failed",
                    visibleText: ["Screen capture failed: \(error.localizedDescription)"],
                    to: state.noteURL
                )
            }
        }
    }

    private func appendObservationJSONL(_ observation: SessionContextObservation, to rawURL: URL) throws {
        try FileManager.default.createDirectory(at: rawURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.notesGuyPretty.encode(observation)
        let line = String(data: data, encoding: .utf8)?.replacingOccurrences(of: "\n", with: " ") ?? "{}"
        let observationsURL = rawURL.appendingPathComponent("observations.jsonl")
        let output = "\(line)\n"
        if FileManager.default.fileExists(atPath: observationsURL.path) {
            let handle = try FileHandle(forWritingTo: observationsURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(output.utf8))
            try handle.close()
        } else {
            try output.write(to: observationsURL, atomically: true, encoding: .utf8)
        }
    }

    private func appendFrameJSON(
        screenshotRelativePath: String,
        visibleText: [String],
        elapsedSeconds: Double,
        to rawURL: URL
    ) throws {
        let payload: [String: Any] = [
            "elapsed_seconds": elapsedSeconds,
            "screenshot_path": screenshotRelativePath,
            "visible_text": visibleText,
            "captured_at": ISO8601DateFormatter().string(from: Date())
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let line = String(data: data, encoding: .utf8) ?? "{}"
        let framesURL = rawURL.appendingPathComponent("frames.jsonl")
        let output = "\(line)\n"
        if FileManager.default.fileExists(atPath: framesURL.path) {
            let handle = try FileHandle(forWritingTo: framesURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(output.utf8))
            try handle.close()
        } else {
            try output.write(to: framesURL, atomically: true, encoding: .utf8)
        }
    }

    private func startAudioTranscription(
        audioArtifact: AudioArtifact,
        state: ActiveSessionState,
        rerunCodexAfterTranscript: Bool
    ) {
        guard state.permissions.speechAuthorized else {
            try? SessionNoteUpdater().upsertTranscriptStatus(
                "Audio was recorded, but speech transcription was skipped because permission is not already granted.",
                to: state.noteURL
            )
            if rerunCodexAfterTranscript {
                statusText = "Writing wiki note from screen context..."
                startCodexSynthesis(state: state)
            }
            return
        }

        let audioURL = URL(fileURLWithPath: audioArtifact.path)
        let noteURL = state.noteURL
        let rawURL = state.rawURL
        let task = Task { [weak self] in
            do {
                let chunks = try await Self.transcribeAudioWithTimeout(audioURL: audioURL)
                let hasSourceTranscript = FileManager.default.fileExists(
                    atPath: rawURL.appendingPathComponent("transcript.txt").path
                )
                let transcriptJSONURL = rawURL.appendingPathComponent(hasSourceTranscript ? "microphone-transcript.json" : "transcript.json")
                let transcriptTextURL = rawURL.appendingPathComponent(hasSourceTranscript ? "microphone-transcript.txt" : "transcript.txt")
                try TranscriptWriter().write(chunks, jsonURL: transcriptJSONURL, textURL: transcriptTextURL)
                try SessionNoteUpdater().upsertTranscript(chunks, to: noteURL)
                await MainActor.run {
                    self?.statusText = "Note finalized with transcript"
                    if rerunCodexAfterTranscript {
                        self?.startCodexSynthesis(state: state)
                    }
                }
            } catch {
                try? SessionNoteUpdater().upsertTranscriptStatus(
                    "Audio was recorded but automatic transcription failed: \(error.localizedDescription)",
                    to: noteURL
                )
                await MainActor.run {
                    self?.statusText = "Audio saved; transcription failed. Wiki note still writes from screen context."
                    if rerunCodexAfterTranscript {
                        self?.startCodexSynthesis(state: state)
                    }
                }
            }
        }
        transcriptTasks.append(task)
    }

    nonisolated private static func transcribeAudioWithTimeout(audioURL: URL, timeoutSeconds: UInt64 = 120) async throws -> [TranscriptChunk] {
        try await withThrowingTaskGroup(of: [TranscriptChunk].self) { group in
            group.addTask {
                try await MacOSSpeechTranscriptionService().transcribe(
                    TranscriptionRequest(sourceURL: audioURL, source: "microphone")
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                throw AudioTranscriptionTimeoutError.timeout(seconds: Int(timeoutSeconds))
            }

            guard let result = try await group.next() else {
                group.cancelAll()
                throw AudioTranscriptionTimeoutError.timeout(seconds: Int(timeoutSeconds))
            }
            group.cancelAll()
            return result
        }
    }

    private func startCodexSynthesis(state: ActiveSessionState) {
        if codexRunInProgress {
            if pendingCodexStates.contains(where: { $0.session.id == state.session.id }) == false {
                pendingCodexStates.append(state)
            }
            statusText = "Wiki writer running. Queued \(pendingCodexStates.count) note job\(pendingCodexStates.count == 1 ? "" : "s")."
            return
        }

        codexRunInProgress = true
        let vaultPath = self.vaultPath
        let notePath = state.noteURL.path
        let rawPath = state.rawURL.path
        let sessionID = state.session.id
        let images = Self.selectedScreenshotPaths(rawURL: state.rawURL)
        statusText = "Codex is writing the source note and wiki pages..."

        Task.detached { [vaultPath, notePath, rawPath, sessionID, images] in
            let result = CodexSessionNoteWriter.writeNote(
                vaultPath: vaultPath,
                notePath: notePath,
                rawPath: rawPath,
                sessionID: sessionID,
                imagePaths: images
            )
            await MainActor.run {
                switch result {
                case .success(.completed):
                    self.statusText = "Wiki note ready"
                    self.currentNotePath = notePath
                    self.noteToastVisible = true
                    self.syncFloatingPrompt()
                case .success(.sourceReadyEnrichmentFailed(let message)):
                    self.statusText = "Source note ready; wiki enrichment failed"
                    self.currentNotePath = notePath
                    self.noteToastVisible = true
                    try? SessionNoteUpdater().upsertCaptureStatus(
                        ["Source note was saved. Wiki enrichment failed: \(message)"],
                        to: URL(fileURLWithPath: notePath)
                    )
                    self.syncFloatingPrompt()
                case .failure(let error):
                    self.statusText = "Source note draft saved; Codex failed"
                    self.currentNotePath = notePath
                    self.noteToastVisible = true
                    try? SessionNoteUpdater().upsertCaptureStatus(
                        ["Codex synthesis failed: \(error.localizedDescription)"],
                        to: URL(fileURLWithPath: notePath)
                    )
                    self.syncFloatingPrompt()
                }
                self.codexRunInProgress = false
                if self.pendingCodexStates.isEmpty == false {
                    let pendingState = self.pendingCodexStates.removeFirst()
                    self.startCodexSynthesis(state: pendingState)
                }
            }
        }
    }

    private func relativeRawPath(for url: URL) -> String {
        let vaultURL = URL(fileURLWithPath: vaultPath, isDirectory: true)
        let vaultPath = vaultURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        if filePath.hasPrefix(vaultPath) {
            return String(filePath.dropFirst(vaultPath.count + 1))
        }
        return filePath
    }

    private func writeCaptureStatus(permissions: CapturePermissionSnapshot, noteURL: URL) {
        let lines = [
            "Screen capture: \(permissions.screenRecordingAuthorized ? "available" : "not granted; skipped to avoid permission prompt")",
            "Microphone: \(permissions.microphoneAuthorized ? "available" : "not granted; skipped to avoid permission prompt")",
            "Speech transcription: \(permissions.speechAuthorized ? "available" : "not granted; skipped to avoid permission prompt")"
        ]
        try? SessionNoteUpdater().upsertCaptureStatus(lines, to: noteURL)
    }

    private func observationSummary(for context: ScreenSourceContext) -> String {
        let app = context.frontmostApplicationName ?? "Current app"
        guard let title = context.visibleWindowTitles.first else {
            return "\(app) active"
        }
        return "\(app): \(title)"
    }

    private func likelyYouTubeContext(title: String, sourceHint: String) -> Bool {
        let value = "\(title) \(sourceHint) \(detectedContextSummary)".lowercased()
        return value.contains("youtube") ||
            value.contains("youtu.be") ||
            value.contains("watch?") ||
            value.contains("video detected")
    }

    private func startCaptionFetchIfPossible(sourceURL: String?) {
        guard let sourceURL, sourceURL.isYouTubeURL, let state = activeSession else {
            return
        }

        statusText = "Fetching YouTube captions..."
        let task = Task { [weak self, sourceURL, rawURL = state.rawURL, noteURL = state.noteURL] in
            do {
                let notes = try await YouTubeCaptionNoteService().fetchNotes(
                    videoURL: sourceURL,
                    rawSessionURL: rawURL
                )
                await MainActor.run {
                    do {
                        try SessionNoteUpdater().upsertTranscriptNotes(notes, to: noteURL)
                        self?.statusText = self?.isSessionActive == true ? "Taking notes... captions added" : "Caption notes added"
                    } catch {
                        self?.statusText = "Caption note write failed: \(error.localizedDescription)"
                    }
                }
            } catch {
                await MainActor.run {
                    if self?.isSessionActive == true {
                        self?.statusText = "Taking notes..."
                    } else {
                        self?.statusText = "Captions unavailable; used captured audio"
                    }
                }
            }
        }
        captionTasks.append(task)
    }

    private func syncFloatingPrompt() {
        #if canImport(AppKit)
        floatingPromptController.sync(model: self)
        #endif
    }

    var detectedContextSummary: String {
        guard let detectedContext else {
            return "No screen context checked yet."
        }

        var parts: [String] = []
        if let app = detectedContext.frontmostApplicationName {
            parts.append("App: \(app)")
        }
        if detectedContext.visibleWindowTitles.isEmpty == false {
            parts.append("Windows: \(detectedContext.visibleWindowTitles.joined(separator: " | "))")
        }
        if let error = detectedContext.errorMessage {
            parts.append("Error: \(error)")
        }
        return parts.isEmpty ? "No source context detected." : parts.joined(separator: "\n")
    }

    private static func sessionID() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }

    private static func capturePermissions() -> CapturePermissionSnapshot {
        var screenRecordingAuthorized = false
        var microphoneAuthorized = false
        var speechAuthorized = false

        #if canImport(CoreGraphics)
        screenRecordingAuthorized = CGPreflightScreenCaptureAccess()
        #endif

        #if canImport(AVFoundation)
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        #endif

        #if canImport(Speech)
        speechAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
        #endif

        return CapturePermissionSnapshot(
            screenRecordingAuthorized: screenRecordingAuthorized,
            microphoneAuthorized: microphoneAuthorized,
            speechAuthorized: speechAuthorized
        )
    }

    private static func requestPermissions() async -> CapturePermissionSnapshot {
        #if canImport(CoreGraphics)
        if CGPreflightScreenCaptureAccess() == false {
            _ = CGRequestScreenCaptureAccess()
        }
        #endif

        #if canImport(AVFoundation)
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        #endif

        #if canImport(Speech)
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
        #endif

        return capturePermissions()
    }

    private static func captureScreenshot(to outputURL: URL) throws {
        #if canImport(AppKit)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", outputURL.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: outputURL.path) else {
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw CaptureError.permissionDenied(error.isEmpty ? "Screen capture failed." : error)
        }
        #else
        throw CaptureError.unavailable("Screen capture is unavailable.")
        #endif
    }

    private static func recognizeText(in imageURL: URL) -> [String] {
        #if canImport(Vision)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(url: imageURL)
        do {
            try handler.perform([request])
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .prefix(16)
                .map { $0 }
        } catch {
            return []
        }
        #else
        return []
        #endif
    }

    private static func selectedScreenshotPaths(rawURL: URL) -> [String] {
        let screenshotsURL = rawURL.appendingPathComponent("screenshots", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: screenshotsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let sorted = files
            .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate < rhsDate
            }

        guard sorted.count > 8 else {
            return sorted.map(\.path)
        }

        let step = Double(sorted.count - 1) / 7.0
        var selected: [String] = []
        var seen = Set<String>()
        for index in 0..<8 {
            let item = sorted[Int((Double(index) * step).rounded())].path
            if seen.insert(item).inserted {
                selected.append(item)
            }
        }
        return selected
    }

}

private enum CodexSessionNoteWriterError: Error, LocalizedError {
    case codexNotFound
    case failed(Int32, String)
    case enrichmentFailed(String)
    case timedOut(seconds: Int)

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "codex executable was not found."
        case .failed(let code, let output):
            return "codex exited with \(code): \(Self.shortError(output))"
        case .enrichmentFailed(let output):
            return "source note was written, but wiki enrichment failed: \(Self.shortError(output))"
        case .timedOut(let seconds):
            return "codex did not finish within \(seconds) seconds."
        }
    }

    private static func shortError(_ value: String) -> String {
        var cleaned = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in ["-------- user", "exec /bin/", "exec\n/bin/"] {
            if let range = cleaned.range(of: marker) {
                cleaned = String(cleaned[..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if cleaned.count > 700 {
            return String(cleaned.prefix(700)) + "..."
        }
        return cleaned.isEmpty ? "no error output" : cleaned
    }
}

private enum CodexWriteOutcome {
    case completed
    case sourceReadyEnrichmentFailed(String)
}

private enum AudioTranscriptionTimeoutError: Error, LocalizedError {
    case timeout(seconds: Int)

    var errorDescription: String? {
        switch self {
        case .timeout(let seconds):
            return "Speech transcription did not finish within \(seconds) seconds."
        }
    }
}

private struct CodexSessionNoteWriter {
    private static let codexTimeoutSeconds = 600

    static func writeNote(
        vaultPath: String,
        notePath: String,
        rawPath: String,
        sessionID: String,
        imagePaths: [String]
    ) -> Result<CodexWriteOutcome, Error> {
        do {
            let outcome = try run(vaultPath: vaultPath, notePath: notePath, rawPath: rawPath, sessionID: sessionID, imagePaths: imagePaths)
            return .success(outcome)
        } catch {
            return .failure(error)
        }
    }

    private static func run(
        vaultPath: String,
        notePath: String,
        rawPath: String,
        sessionID: String,
        imagePaths: [String]
    ) throws -> CodexWriteOutcome {
        let codex = try codexPath()
        try runCodex(
            codex: codex,
            vaultPath: vaultPath,
            imagePaths: imagePaths,
            prompt: sourceNotePrompt(notePath: notePath, rawPath: rawPath, sessionID: sessionID)
        )

        let workspace = WikiWorkspace(configuration: VaultConfiguration(vaultPath: vaultPath))
        _ = try? workspace.bootstrap()
        do {
            _ = try LocalWikiEnrichmentSeedWriter().writeSeeds(
                sourceNoteURL: URL(fileURLWithPath: notePath),
                sourceNoteRelativePath: relativePath(notePath, rootPath: vaultPath),
                workspace: workspace,
                sessionID: sessionID
            )
        } catch {
            try? appendEnrichmentFailure(
                vaultPath: vaultPath,
                notePath: notePath,
                rawPath: rawPath,
                sessionID: sessionID,
                error: error
            )
        }

        do {
            try runCodex(
                codex: codex,
                vaultPath: vaultPath,
                imagePaths: [],
                prompt: enrichmentPrompt(notePath: notePath, rawPath: rawPath, sessionID: sessionID)
            )
        } catch {
            try? appendEnrichmentFailure(
                vaultPath: vaultPath,
                notePath: notePath,
                rawPath: rawPath,
                sessionID: sessionID,
                error: error
            )
            return .sourceReadyEnrichmentFailed(error.localizedDescription)
        }
        return .completed
    }

    private static func sourceNotePrompt(notePath: String, rawPath: String, sessionID: String) -> String {
        """
        You are writing the source note for a personal Obsidian-style technical wiki.

        This is stage 1 of 2.
        Stage 1 writes only the source-bound note.
        Stage 2 will enrich durable concept/topic/synthesis/guide pages.

        Write directly to this note file:
        \(notePath)

        Raw session folder:
        \(rawPath)

        Session id:
        \(sessionID)

        Input evidence you should read if present:
        - the existing note file
        - manifest.json
        - observations.jsonl
        - frames.jsonl
        - transcript.txt or transcript.json
        - microphone-transcript.txt or microphone-transcript.json
        - audio/microphone.m4a may exist but you may not be able to listen to it directly
        - attached screenshots are visual evidence from the session

        Important:
        Do NOT write a video recap.
        Do NOT write "the segment introduces..." unless absolutely necessary.
        Do NOT summarize passively.
        Do NOT keep capture-status failure blocks, raw transcript dumps, starter-note scaffolding, or HTML marker blocks.
        Do NOT leave `## Visual Timeline`, `## Audio Transcript`, `## Observed Timeline`, `## Capture Status`, or `## Session Summary`.
        Do NOT produce one bullet per spoken line, caption chunk, screenshot, or timestamp.
        Do NOT preserve malformed speech-recognition phrasing when the intended technical concept is clear from transcript and screenshots.

        Job:
        Turn this session into a clean source note that preserves what was learned and points toward reusable wiki pages. Keep it close enough to the source for audit, but useful enough to read later.

        Writing style:
        - crisp
        - dense but readable
        - concept-first
        - explanatory
        - no fluff
        - no generic summary
        - prefer "X is..." over "The video shows..."
        - write like an engineer building a permanent learning wiki

        Linking rule:
        - Use explicit Obsidian path links when linking to wiki pages, for example `[[Wiki/topics/system-design.md|System Design]]`.
        - Do not use bare links like `[[System Design]]`; they create empty root notes in this vault.

        Source note format:

        ---
        title: "{{navigation_friendly_source_title}}"
        date: "{{YYYY-MM-DD}}"
        type: "source-note"
        source_type: "{{youtube | blog | paper | article | meeting | code | general}}"
        source_url: "{{source_url}}"
        source_title: "{{source_title}}"
        captured_range: "{{start_time}}-{{end_time}}"
        primary_concepts:
          - "{{Concept Name}}"
        related_notes:
          - "[[Wiki/concepts/concept-slug.md|Concept Name]]"
          - "[[Wiki/topics/topic-slug.md|Topic Name]]"
        status: "source-ready"
        ---

        # {{Navigation Friendly Source Title}}

        ## Why This Matters

        Write 1-3 sentences that capture the durable value of this source for the wiki.

        ## Source Notes

        Extract reusable ideas from the source. Write concept-first or reference-first, not recap-first.

        For conceptual material, use short subsections:

        ### {{Concept Name}}

        - Atomic idea:
        - Mental model:
        - Problem it solves:
        - Mechanism:
        - Concrete example:
        - Key distinctions:

        For coding/tutorial sources, use this shape when it fits better:

        ## Core Mental Model
        ## Cheat Sheet
        ## Syntax Patterns
        ## When To Use What
        ## Pitfalls
        ## Recall Prompts

        For system-design or interview sources, use this shape when it fits better:

        ## Core Mental Model
        ## Design Problem
        ## Mechanism
        ## Tradeoffs
        ## Failure Modes
        ## Interview Prompts

        For research papers, articles, blogs, docs, or meetings, choose useful sections instead of forcing a template.

        ## Links Into The Wiki

        Link to concept/topic/synthesis/guide pages that exist or should exist:

        - [[Wiki/concepts/concept-slug.md|Concept Name]] - why this source matters for that concept
        - [[Wiki/topics/topic-slug.md|Topic Name]] - why this source belongs there

        ## Open Questions

        List sharp technical questions that should drive future notes or discussion.

        ## Codex / Implementation Prompts

        Create concrete prompts that would help implement, simulate, test, or explore the ideas in code.

        ## Source Anchors

        Include only useful source anchors.
        Format:
        - {{timestamp}} - {{short description of what was shown/explained}}

        ## Raw Evidence

        Include raw file paths from the session metadata if available.

        If the evidence is too thin, write `status: "needs-recapture"` and say exactly what evidence is missing. Do not hallucinate.
        """
    }

    private static func enrichmentPrompt(notePath: String, rawPath: String, sessionID: String) -> String {
        """
        You are maintaining a personal Obsidian-style technical wiki.

        This is stage 2 of 2.
        Stage 1 already wrote a source note.
        Your job is to enrich the durable wiki so the user's knowledge base compounds over time.

        Source note:
        \(notePath)

        Raw session folder:
        \(rawPath)

        Session id:
        \(sessionID)

        Read before writing:
        - the source note above
        - `.notes-guy/schema.md`
        - `Wiki/index.md`
        - `.notes-guy/log.md`
        - existing related notes under `Wiki/concepts/`, `Wiki/topics/`, `Wiki/syntheses/`, `Wiki/guides/`, and recent `Wiki/sources/`
        - raw transcript, observations, OCR, and screenshots only when the source note is too thin

        Required writes:
        1. Create or update at least one durable wiki page when evidence supports it:
           - `Wiki/concepts/*.md` for atomic ideas.
           - `Wiki/topics/*.md` for domain maps.
           - `Wiki/syntheses/*.md` for cross-source learning maps.
           - `Wiki/guides/*.md` for study, interview, reference, paper, or implementation guides.
        2. Update `Wiki/index.md` with touched pages.
        3. Append an `enrich` entry to `.notes-guy/log.md`.
        4. Optionally update the source note status or related links without destroying source evidence.

        Living wiki behavior:
        - Do not create random isolated notes.
        - Do not create empty placeholder pages.
        - Use explicit Obsidian path links such as `[[Wiki/concepts/load-balancing.md|Load Balancing]]`, never bare root links such as `[[Load Balancing]]`.
        - Prefer updating existing related pages over creating duplicates.
        - If this is the sixth source in a topic, five or six source notes are fine, but the higher-level topic/guide/synthesis page should become better.
        - Preserve existing source-backed content. Make targeted additions or section updates.
        - Use stable navigation titles, not noisy source titles.

        External research:
        - If the Codex runtime exposes web/search/research tools, use them for enrichment when helpful.
        - Prefer primary, official, or authoritative sources.
        - Keep external claims separate from captured-source claims when that distinction matters.
        - If external research is unavailable, do not fake it. Add a short `External Research` or log note saying it was not performed and continue from local evidence plus existing wiki context.

        Generic guide shapes:
        - Coding/tutorial guide: mental model, cheat sheet, syntax patterns, examples, pitfalls, interview/recall prompts, implementation prompts.
        - System-design/interview guide: problem shape, constraints, core mechanism, tradeoffs, failure modes, scaling concerns, interview questions with crisp answers.
        - Research-paper guide: thesis, method, assumptions, results, limitations, relation to existing concepts, open research questions.
        - Blog/article/docs guide: concept explanation, API/reference facts, tradeoffs, examples, related notes, follow-up prompts.
        - Meeting guide: decisions, rationale, action items, unresolved questions, related notes.
        - General source: choose the smallest useful durable page type.

        Page quality:
        - The enriched page must stand alone without the source.
        - Do not write a video recap.
        - Do not write "the source explains" when direct concept prose works.
        - Do not paste raw transcript, captions, or screenshot timelines.
        - Include Obsidian links for related concepts.
        - Include source anchors, raw evidence paths, or source links for verification.
        - Include open questions where the evidence is incomplete.

        Minimum useful page shape:

        ---
        title: "{{stable_wiki_title}}"
        type: "{{concept-note | topic-note | synthesis-note | guide}}"
        status: "{{seed | maturing}}"
        tags:
          - notes-guy
          - "{{domain_tag}}"
        sources:
          - "[[source note title]]"
        ---

        # {{Stable Wiki Title}}

        ## Atomic Idea
        ## Mental Model
        ## Mechanism Or Structure
        ## Concrete Examples
        ## Tradeoffs And Pitfalls
        ## Related Concepts
        ## Questions To Grow This Note
        ## Source Anchors

        Quality checklist before finalizing:
        1. Does at least one durable page now exist or improve?
        2. Did you connect the source note to existing related notes?
        3. Did you update index/log?
        4. Did you avoid raw transcript/timeline/caption structure?
        5. Did you avoid pretending to do external research if it was unavailable?
        6. Would this be useful as part of a long-term Obsidian wiki?
        """
    }

    private static func runCodex(
        codex: String,
        vaultPath: String,
        imagePaths: [String],
        prompt: String
    ) throws {
        var arguments = [
            "exec",
            "--skip-git-repo-check",
            "--sandbox", "workspace-write",
            "-C", vaultPath
        ]
        for imagePath in imagePaths {
            arguments.append(contentsOf: ["--image", imagePath])
        }

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-guy-codex-\(UUID().uuidString)", isDirectory: true)
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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codex)
        process.arguments = arguments
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        try process.run()
        stdin.fileHandleForWriting.write(Data(prompt.utf8))
        stdin.fileHandleForWriting.closeFile()

        let completion = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            completion.signal()
        }

        guard completion.wait(timeout: .now() + .seconds(Self.codexTimeoutSeconds)) == .success else {
            process.terminate()
            _ = completion.wait(timeout: .now() + .seconds(5))
            throw CodexSessionNoteWriterError.timedOut(seconds: Self.codexTimeoutSeconds)
        }

        guard process.terminationStatus == 0 else {
            stdoutHandle.synchronizeFile()
            stderrHandle.synchronizeFile()
            let out = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
            let err = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
            throw CodexSessionNoteWriterError.failed(process.terminationStatus, (err + "\n" + out).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func appendEnrichmentFailure(
        vaultPath: String,
        notePath: String,
        rawPath: String,
        sessionID: String,
        error: Error
    ) throws {
        let vaultURL = URL(fileURLWithPath: vaultPath, isDirectory: true)
        let logURL = vaultURL.appendingPathComponent(".notes-guy/log.md")
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: logURL.path) {
            try "# Notes Guy Log\n\nAppend-only timeline of ingest, enrich, follow-up, lint, repair, and failure actions.\n\n"
                .write(to: logURL, atomically: true, encoding: .utf8)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
        let errorText = error.localizedDescription
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let shortErrorText = errorText.count > 700 ? String(errorText.prefix(700)) + "..." : errorText

        let entry = """

        ## [\(timestamp)] failure | Enrichment failed

        - Session: \(sessionID)
        - Source note: `\(relativePath(notePath, rootPath: vaultPath))`
        - Raw folder: `\(relativePath(rawPath, rootPath: vaultPath))`
        - Error: \(shortErrorText)
        - Repair: rerun enrichment from the source note and raw folder.

        """

        let handle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(Data(entry.utf8))
    }

    private static func relativePath(_ path: String, rootPath: String) -> String {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.path
        let file = URL(fileURLWithPath: path).standardizedFileURL.path
        guard file.hasPrefix(root + "/") else {
            return file
        }
        return String(file.dropFirst(root.count + 1))
    }

    private static func codexPath() throws -> String {
        if let configured = ProcessInfo.processInfo.environment["NOTES_GUY_CODEX_PATH"],
           configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           FileManager.default.isExecutableFile(atPath: configured) {
            return configured
        }
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        if let candidate = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return candidate
        }
        throw CodexSessionNoteWriterError.codexNotFound
    }
}

private struct BrowserSource {
    var url: String?
    var title: String?
}

private struct CapturePermissionSnapshot {
    var screenRecordingAuthorized: Bool
    var microphoneAuthorized: Bool
    var speechAuthorized: Bool
}

private struct ActiveSessionState {
    var session: LearningSession
    var noteURL: URL
    var noteRelativePath: String
    var rawURL: URL
    var permissions: CapturePermissionSnapshot
    var observations: [SessionContextObservation] = []
    var lastObservationFingerprint: String?
    var frameCount: Int = 0
    var audioArtifact: AudioArtifact?
}

private extension String {
    var isYouTubeURL: Bool {
        let value = lowercased()
        return value.contains("youtube.com/watch") ||
            value.contains("youtu.be/") ||
            value.contains("youtube.com/live/")
    }
}

struct NotesGuyRootView: View {
    @ObservedObject var model: NotesGuyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                    Text("Notes Guy")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text(model.statusText)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Wiki folder", text: $model.vaultPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Toggle("Ask to take notes", isOn: Binding(
                    get: { model.proactiveWatchingEnabled },
                    set: { model.setProactiveWatching($0) }
                ))
                Spacer()
                Text(model.proactiveWatchingEnabled ? "On" : "Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if model.isSessionActive {
                HStack {
                    Text("Taking notes")
                        .font(.headline)
                    Spacer()
                    Text("\(model.activeFrameCount) frames")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Stop and write note") {
                        model.stopCurrentSession()
                    }
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            if let permissionMessage = model.permissionMessage {
                Text(permissionMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if let notePath = model.currentNotePath {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Latest note")
                        .font(.headline)
                    Text(notePath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    HStack {
                        Button("Copy path") {
                            model.copyCurrentNotePath()
                        }
                        Button("Show note") {
                            model.openCurrentNote()
                        }
                    }
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 260)
    }
}

struct NotesGuyMenuView: View {
    @ObservedObject var model: NotesGuyViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if model.isSessionActive {
            Button("Stop and write note") {
                model.stopCurrentSession()
            }
        } else {
            Button("Grant permissions once") {
                model.requestCapturePermissionsOnce()
            }
            Divider()
            Button("Take note now") {
                model.startNoteForCurrentScreen()
            }
            Button("Show floating prompt") {
                model.checkCurrentScreen()
            }
        }
        if let notePath = model.currentNotePath {
            Button("Copy latest note path") {
                model.copyCurrentNotePath()
            }
            Text(notePath)
        }
        Divider()
        Button("Open notes folder") {
            model.openVaultFolder()
        }
        Button("Open wiki index") {
            model.openWikiIndex()
        }
        Divider()
        Toggle("Ask to take notes", isOn: Binding(
            get: { model.proactiveWatchingEnabled },
            set: { model.setProactiveWatching($0) }
        ))
        Text(model.proactiveWatchingEnabled ? "On" : "Paused")
        Divider()
        Button("Settings...") {
            openSettings()
        }
        Button("Quit") {
            #if canImport(AppKit)
            NSApp.terminate(nil)
            #endif
        }
    }
}

#if canImport(AppKit)
@MainActor
final class FloatingPromptController {
    private var panel: FloatingPromptPanel?

    func sync(model: NotesGuyViewModel) {
        guard model.isSessionActive == false else {
            hide()
            return
        }
        guard model.proactivePromptVisible || model.noteToastVisible else {
            hide()
            return
        }
        show(model: model)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func show(model: NotesGuyViewModel) {
        let targetSize = NSSize(width: 760, height: 96)
        if panel == nil {
            let panel = FloatingPromptPanel(
                contentRect: NSRect(origin: .zero, size: targetSize),
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.level = .statusBar
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .transient,
                .ignoresCycle
            ]
            self.panel = panel
        }

        guard let panel else {
            return
        }

        panel.contentView = NSHostingView(rootView: FloatingPromptView(model: model))
        panel.setContentSize(targetSize)
        position(panel: panel, size: targetSize)
        panel.orderFrontRegardless()
    }

    private func position(panel: NSPanel, size: NSSize) {
        let screen = NSScreen.screens.first { screen in
            screen.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens.first

        guard let screen else {
            panel.center()
            return
        }

        let frame = screen.visibleFrame
        let x = frame.midX - (size.width / 2)
        let y = frame.maxY - size.height - 22
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

final class FloatingPromptPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

struct FloatingPromptView: View {
    @ObservedObject var model: NotesGuyViewModel

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.94))
                    .frame(width: 58, height: 58)
                Image(systemName: model.noteToastVisible ? "doc.text.fill" : "book.closed.fill")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(.black)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            if model.isSessionActive {
                Button {
                    model.stopCurrentSession()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(PillButtonStyle())
            } else if model.noteToastVisible {
                Button {
                    model.copyCurrentNotePath()
                } label: {
                    Label("Copy path", systemImage: "doc.on.doc")
                }
                .buttonStyle(PillButtonStyle())

                Button {
                    model.openCurrentNote()
                    model.dismissNoteToast()
                } label: {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(IconPillButtonStyle())
            } else {
                Button {
                    model.takeNotesOnDetectedContext()
                } label: {
                    Label("Take notes", systemImage: "checkmark")
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
            }

            Button {
                if model.noteToastVisible {
                    model.dismissNoteToast()
                } else {
                    model.dismissProactivePrompt()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(QuietIconButtonStyle())
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(width: 760, height: 96)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 14)
    }

    private var title: String {
        if model.isSessionActive {
            return "Taking notes"
        }
        return model.noteToastVisible ? "Note ready" : "Start Obsidian note"
    }

    private var subtitle: String {
        if model.isSessionActive {
            return "\(model.activeFrameCount) visual frames captured. Audio is recording."
        }
        if model.noteToastVisible {
            return model.currentNotePath ?? "Saved to your notes folder"
        }
        if let reason = model.proactiveReason, reason.isEmpty == false {
            return "\(reason). Saves quietly to Obsidian."
        }
        return "Saves quietly to your Obsidian folder."
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 52)
            .background(
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? Color.blue.opacity(0.78) : Color.blue)
            )
    }
}

struct IconPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                Circle()
                    .fill(configuration.isPressed ? Color.blue.opacity(0.78) : Color.blue)
            )
    }
}

struct QuietIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .background(
                Circle()
                    .fill(configuration.isPressed ? Color.black.opacity(0.10) : Color.black.opacity(0.04))
            )
    }
}
#endif
