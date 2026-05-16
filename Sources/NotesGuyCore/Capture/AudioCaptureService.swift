import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
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

private final class AsyncResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func set(_ result: Result<Value, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func get() -> Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
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

public final class SystemAudioCaptureService: NSObject, AudioCaptureService, @unchecked Sendable {
    #if canImport(ScreenCaptureKit) && canImport(AVFoundation)
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var currentArtifact: AudioArtifact?
    private let sampleQueue = DispatchQueue(label: "notes-guy.system-audio.samples")
    private var hasStartedWriting = false
    private var isFinishing = false
    #endif

    public override init() {}

    public func startRecording(to outputURL: URL) throws -> AudioArtifact {
        #if canImport(ScreenCaptureKit) && canImport(AVFoundation)
        let result = AsyncResultBox<AudioArtifact>()
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                let artifact = try await self.startRecordingAsync(to: outputURL)
                result.set(.success(artifact))
            } catch {
                result.set(.failure(error))
            }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + .seconds(10)) == .success else {
            throw CaptureError.unavailable("System audio capture setup timed out.")
        }
        return try result.get()?.get() ?? {
            throw CaptureError.unavailable("System audio capture did not return a result.")
        }()
        #else
        throw CaptureError.unavailable("ScreenCaptureKit system audio capture is unavailable on this platform.")
        #endif
    }

    public func stopRecording() throws -> AudioArtifact? {
        #if canImport(ScreenCaptureKit) && canImport(AVFoundation)
        guard let stream else {
            return nil
        }

        let stopResult = AsyncResultBox<Void>()
        let stopSemaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                try await stream.stopCapture()
                stopResult.set(.success(()))
            } catch {
                stopResult.set(.failure(error))
            }
            stopSemaphore.signal()
        }

        guard stopSemaphore.wait(timeout: .now() + .seconds(10)) == .success else {
            throw CaptureError.unavailable("System audio capture stop timed out.")
        }
        try stopResult.get()?.get()

        sampleQueue.sync {
            isFinishing = true
            writerInput?.markAsFinished()
        }

        if let writer, writer.status == .writing || writer.status == .failed || writer.status == .completed {
            let finishSemaphore = DispatchSemaphore(value: 0)
            writer.finishWriting {
                finishSemaphore.signal()
            }
            _ = finishSemaphore.wait(timeout: .now() + .seconds(10))
        }

        defer {
            self.stream = nil
            self.writer = nil
            self.writerInput = nil
            self.currentArtifact = nil
            self.hasStartedWriting = false
            self.isFinishing = false
        }
        return currentArtifact
        #else
        return nil
        #endif
    }

    #if canImport(ScreenCaptureKit) && canImport(AVFoundation)
    private func startRecordingAsync(to outputURL: URL) async throws -> AudioArtifact {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw CaptureError.unavailable("No display is available for system audio capture.")
        }

        let configuration = SCStreamConfiguration()
        configuration.width = max(display.width, 2)
        configuration.height = max(display.height, 2)
        configuration.queueDepth = 3
        configuration.capturesAudio = true
        configuration.sampleRate = 44_100
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw CaptureError.unavailable("System audio writer could not accept an audio input.")
        }
        writer.add(input)

        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()

        self.stream = stream
        self.writer = writer
        self.writerInput = input
        self.currentArtifact = AudioArtifact(mode: .systemAudio, path: outputURL.path)
        self.hasStartedWriting = false
        self.isFinishing = false
        return currentArtifact!
    }
    #endif
}

#if canImport(ScreenCaptureKit) && canImport(AVFoundation)
extension SystemAudioCaptureService: SCStreamOutput {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              CMSampleBufferDataIsReady(sampleBuffer),
              isFinishing == false,
              let writer,
              let writerInput else {
            return
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if writer.status == .unknown {
            guard writer.startWriting() else {
                return
            }
            writer.startSession(atSourceTime: timestamp)
            hasStartedWriting = true
        }

        guard writer.status == .writing, hasStartedWriting, writerInput.isReadyForMoreMediaData else {
            return
        }
        writerInput.append(sampleBuffer)
    }
}
#endif
