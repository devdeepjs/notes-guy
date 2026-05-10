import Foundation

public struct ImageFingerprint: Equatable, Sendable {
    public var bits: UInt64

    public init(bits: UInt64) {
        self.bits = bits
    }

    public static func averageHash(samples: [UInt8]) -> ImageFingerprint {
        guard samples.isEmpty == false else {
            return ImageFingerprint(bits: 0)
        }

        let targetCount = 64
        let stride = max(1, samples.count / targetCount)
        var reduced: [UInt8] = []
        reduced.reserveCapacity(targetCount)

        var index = 0
        while index < samples.count && reduced.count < targetCount {
            reduced.append(samples[index])
            index += stride
        }

        while reduced.count < targetCount {
            reduced.append(reduced.last ?? 0)
        }

        let total = reduced.reduce(0) { $0 + Int($1) }
        let average = total / reduced.count
        var bits: UInt64 = 0

        for sample in reduced {
            bits <<= 1
            if Int(sample) >= average {
                bits |= 1
            }
        }

        return ImageFingerprint(bits: bits)
    }

    public func distance(to other: ImageFingerprint) -> Int {
        Int((bits ^ other.bits).nonzeroBitCount)
    }
}

public struct DuplicateFrameDetector: Sendable {
    public var threshold: Int
    private var previous: ImageFingerprint?

    public init(threshold: Int = 4) {
        self.threshold = threshold
        self.previous = nil
    }

    public mutating func shouldProcess(samples: [UInt8]) -> Bool {
        let current = ImageFingerprint.averageHash(samples: samples)
        defer { previous = current }

        guard let previous else {
            return true
        }

        return previous.distance(to: current) > threshold
    }
}
