import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

public final class ScreenCaptureKitScreenCaptureService: ScreenCaptureService, @unchecked Sendable {
    private var isRecording = false

    public init() {}

    public func preStartContext() async -> ScreenSourceContext {
        #if canImport(ScreenCaptureKit) && canImport(AppKit)
        let frontmost = await MainActor.run {
            NSWorkspace.shared.frontmostApplication
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            let titles = content.windows
                .compactMap { $0.title?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .prefix(8)

            return ScreenSourceContext(
                permissionStatus: .available,
                frontmostApplicationName: frontmost?.localizedName,
                frontmostBundleIdentifier: frontmost?.bundleIdentifier,
                visibleWindowTitles: Array(titles),
                displayCount: content.displays.count
            )
        } catch {
            return ScreenSourceContext(
                permissionStatus: .denied,
                frontmostApplicationName: frontmost?.localizedName,
                frontmostBundleIdentifier: frontmost?.bundleIdentifier,
                errorMessage: error.localizedDescription
            )
        }
        #else
        return ScreenSourceContext(
            permissionStatus: .unavailable,
            errorMessage: "ScreenCaptureKit is unavailable on this platform."
        )
        #endif
    }

    public func start(configuration: ScreenCaptureConfiguration) async throws {
        guard configuration.intervalSeconds > 0 else {
            throw CaptureError.invalidInput("Screenshot interval must be greater than zero.")
        }
        isRecording = true
    }

    public func stop() async throws {
        isRecording = false
    }

    public var recording: Bool {
        isRecording
    }
}
