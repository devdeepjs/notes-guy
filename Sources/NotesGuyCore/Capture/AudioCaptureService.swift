import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

public enum AudioCaptureMode: String, Codable, Equatable, Sendable {
    case systemAudio
    case microphone
    case importedAudio
    case importedVideo
    case importedTranscript
}

public struct AudioArtifact: Codable, Equatable, Sendable {
    public var mode: AudioCaptureMode
    public var path: String
    public var createdAt: Date
    public var durationSeconds: Double?

    public init(mode: AudioCaptureMode, path: String, createdAt: Date = Date(), durationSeconds: Double? = nil) {
        self.mode = mode
        self.path = path
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
    }
}

public protocol AudioCaptureService {
    func startRecording(to outputURL: URL) throws -> AudioArtifact
    func stopRecording() throws -> AudioArtifact?
}

public struct AudioImportService {
    public init() {}

    public func importAudioFile(from sourceURL: URL, into sessionAudioDirectory: URL) throws -> AudioArtifact {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw CaptureError.invalidInput("Audio import file does not exist: \(sourceURL.path)")
        }

        try FileManager.default.createDirectory(at: sessionAudioDirectory, withIntermediateDirectories: true)
        let destinationURL = sessionAudioDirectory.appendingPathComponent(sourceURL.lastPathComponent)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        return AudioArtifact(mode: .importedAudio, path: destinationURL.path)
    }
}

public final class MicrophoneAudioCaptureService: AudioCaptureService {
    #if canImport(AVFoundation)
    private var recorder: AVAudioRecorder?
    private var currentArtifact: AudioArtifact?
    #endif

    public init() {}

    public func startRecording(to outputURL: URL) throws -> AudioArtifact {
        #if canImport(AVFoundation)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: outputURL, settings: settings)
        recorder.record()
        self.recorder = recorder
        let artifact = AudioArtifact(mode: .microphone, path: outputURL.path)
        self.currentArtifact = artifact
        return artifact
        #else
        throw CaptureError.unavailable("AVFoundation is unavailable on this platform.")
        #endif
    }

    public func stopRecording() throws -> AudioArtifact? {
        #if canImport(AVFoundation)
        recorder?.stop()
        recorder = nil
        defer { currentArtifact = nil }
        return currentArtifact
        #else
        return nil
        #endif
    }
}
