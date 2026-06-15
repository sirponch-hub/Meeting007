import Foundation

public enum CaptureLane: String, Codable, Equatable, Sendable {
    case mic
    case system
}

public enum MicrophoneCaptureStatus: Equatable, Sendable {
    case idle
    case requestingPermission
    case starting
    case listening(level: Double)
    case quiet
    case blocked
    case unavailable(String)
    case failed(String)

    public var userFacingLabel: String {
        switch self {
        case .idle:
            return "Me · Ready"
        case .requestingPermission:
            return "Me · Waiting for access"
        case .starting:
            return "Me · Starting"
        case .listening:
            return "Me · Listening"
        case .quiet:
            return "Me · Quiet"
        case .blocked:
            return "Me · Microphone blocked"
        case .unavailable:
            return "Me · Input unavailable"
        case .failed:
            return "Me · Capture stopped"
        }
    }

    public var level: Double {
        if case let .listening(level) = self {
            return min(max(level, 0), 1)
        }

        return 0
    }
}

public struct MicrophoneInputDevice: Identifiable, Equatable, Sendable {
    public let id: UInt32
    public let uid: String
    public let name: String
    public let isSystemDefault: Bool

    public init(id: UInt32, uid: String, name: String, isSystemDefault: Bool = false) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isSystemDefault = isSystemDefault
    }
}

public struct MicrophoneDeviceSelectionSettings {
    public static let defaultStorageKey = "meeting007.microphoneDeviceUID"

    private let defaults: UserDefaults
    private let storageKey: String

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = Self.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public var selectedDeviceUID: String {
        get {
            defaults.string(forKey: storageKey) ?? ""
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                defaults.removeObject(forKey: storageKey)
            } else {
                defaults.set(trimmed, forKey: storageKey)
            }
        }
    }
}

public struct CapturedAudioChunk: Equatable, Sendable {
    public let sessionID: UUID
    public let lane: CaptureLane
    public let startedAt: TimeInterval
    public let duration: TimeInterval
    public let sampleRate: Double
    public let channelCount: Int
    public let byteCount: Int
    public let samples: RuntimeAudioSamples

    public init(
        sessionID: UUID,
        lane: CaptureLane,
        startedAt: TimeInterval,
        duration: TimeInterval,
        sampleRate: Double,
        channelCount: Int,
        byteCount: Int,
        samples: RuntimeAudioSamples? = nil
    ) {
        self.sessionID = sessionID
        self.lane = lane
        self.startedAt = startedAt
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.byteCount = byteCount
        self.samples = samples ?? RuntimeAudioSamples(sampleRate: sampleRate, channelCount: channelCount, samples: [])
    }
}

public protocol AudioChunkConsumer: Sendable {
    func receive(_ chunk: CapturedAudioChunk) async
}

public protocol SpeechChunkConsumer: Sendable {
    @discardableResult
    func receive(_ chunk: SpeechChunk) async -> [TranscriptSegment]
}

public struct RuntimeAudioSamples: Equatable, Sendable {
    public let sampleRate: Double
    public let channelCount: Int
    public let samples: ContiguousArray<Float>

    public init(sampleRate: Double, channelCount: Int, samples: ContiguousArray<Float>) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.samples = samples
    }

    public init(sampleRate: Double, channelCount: Int, samples: [Float]) {
        self.init(sampleRate: sampleRate, channelCount: channelCount, samples: ContiguousArray(samples))
    }

    public var frameCount: Int {
        guard channelCount > 0 else {
            return 0
        }

        return samples.count / channelCount
    }

    public var byteCount: Int {
        samples.count * MemoryLayout<Float>.size
    }
}

public struct SpeechChunk: Equatable, Sendable {
    public let sessionID: UUID
    public let lane: CaptureLane
    public let startedAt: TimeInterval
    public let duration: TimeInterval
    public let sampleRate: Double
    public let samples: ContiguousArray<Float>
    public let isFinalInUtterance: Bool

    public init(
        sessionID: UUID,
        lane: CaptureLane,
        startedAt: TimeInterval,
        duration: TimeInterval,
        sampleRate: Double,
        samples: ContiguousArray<Float>,
        isFinalInUtterance: Bool = true
    ) {
        self.sessionID = sessionID
        self.lane = lane
        self.startedAt = startedAt
        self.duration = duration
        self.sampleRate = sampleRate
        self.samples = samples
        self.isFinalInUtterance = isFinalInUtterance
    }
}

public enum RuntimeAudioFrameNormalizer {
    public static let defaultTargetSampleRate: Double = 16_000

    public static func normalizedMonoSamples(
        _ samples: [Float],
        sourceSampleRate: Double,
        sourceChannelCount: Int,
        targetSampleRate: Double = defaultTargetSampleRate
    ) -> RuntimeAudioSamples {
        guard sourceSampleRate > 0, sourceChannelCount > 0, !samples.isEmpty else {
            return RuntimeAudioSamples(sampleRate: targetSampleRate, channelCount: 1, samples: [])
        }

        let sourceFrameCount = samples.count / sourceChannelCount
        guard sourceFrameCount > 0 else {
            return RuntimeAudioSamples(sampleRate: targetSampleRate, channelCount: 1, samples: [])
        }

        var monoSamples: [Float] = []
        monoSamples.reserveCapacity(sourceFrameCount)

        for frame in 0..<sourceFrameCount {
            var sum: Float = 0
            for channel in 0..<sourceChannelCount {
                sum += samples[(frame * sourceChannelCount) + channel]
            }
            monoSamples.append(sum / Float(sourceChannelCount))
        }

        guard sourceSampleRate != targetSampleRate else {
            return RuntimeAudioSamples(sampleRate: targetSampleRate, channelCount: 1, samples: monoSamples)
        }

        let targetFrameCount = max(1, Int((Double(sourceFrameCount) * targetSampleRate / sourceSampleRate).rounded()))
        var resampled: [Float] = []
        resampled.reserveCapacity(targetFrameCount)

        for targetFrame in 0..<targetFrameCount {
            let sourcePosition = Double(targetFrame) * sourceSampleRate / targetSampleRate
            let lowerIndex = min(Int(sourcePosition), sourceFrameCount - 1)
            let upperIndex = min(lowerIndex + 1, sourceFrameCount - 1)
            let fraction = Float(sourcePosition - Double(lowerIndex))
            let lower = monoSamples[lowerIndex]
            let upper = monoSamples[upperIndex]
            resampled.append(lower + ((upper - lower) * fraction))
        }

        return RuntimeAudioSamples(sampleRate: targetSampleRate, channelCount: 1, samples: resampled)
    }
}

public actor RuntimeOnlyAudioChunkConsumer: AudioChunkConsumer {
    private let speechChunkConsumer: (any SpeechChunkConsumer)?
    private var vad: VADSpeechChunker
    private var activeSessionID: UUID?
    private var pendingSpeechChunks: [SpeechChunk] = []
    private var deliveryTask: Task<Void, Never>?
    private var isEnding = false
    private var chunks: [CapturedAudioChunk] = []

    public init(
        speechChunkConsumer: (any SpeechChunkConsumer)? = nil,
        vadConfiguration: VADSpeechChunker.Configuration = .default
    ) {
        self.speechChunkConsumer = speechChunkConsumer
        self.vad = VADSpeechChunker(configuration: vadConfiguration)
    }

    public func begin(sessionID: UUID) {
        deliveryTask?.cancel()
        deliveryTask = nil
        pendingSpeechChunks.removeAll()
        isEnding = false
        activeSessionID = sessionID
        chunks.removeAll()
        vad.begin(sessionID: sessionID)
    }

    public func end(sessionID: UUID) async {
        guard activeSessionID == sessionID else {
            return
        }

        let speechChunks = vad.end(sessionID: sessionID)
        activeSessionID = nil
        chunks.removeAll()
        enqueueDelivery(for: speechChunks)
        isEnding = true

        if let deliveryTask {
            await deliveryTask.value
        } else {
            isEnding = false
        }
    }

    public func receive(_ chunk: CapturedAudioChunk) async {
        guard activeSessionID == chunk.sessionID else {
            return
        }

        chunks.append(chunk)
        let speechChunks = vad.receive(chunk)
        enqueueDelivery(for: speechChunks)
    }

    public func capturedChunks() -> [CapturedAudioChunk] {
        chunks
    }

    private func enqueueDelivery(for speechChunks: [SpeechChunk]) {
        guard let speechChunkConsumer else {
            return
        }

        pendingSpeechChunks.append(contentsOf: speechChunks)
        pendingSpeechChunks.sort {
            if $0.startedAt == $1.startedAt {
                return $0.lane.rawValue < $1.lane.rawValue
            }
            return $0.startedAt < $1.startedAt
        }

        guard deliveryTask == nil else {
            return
        }

        deliveryTask = Task {
            while let speechChunk = self.nextQueuedSpeechChunk() {
                _ = await speechChunkConsumer.receive(speechChunk)
            }
            self.finishDeliveryIfDrained()
        }
    }

    private func nextQueuedSpeechChunk() -> SpeechChunk? {
        guard !pendingSpeechChunks.isEmpty else {
            return nil
        }
        return pendingSpeechChunks.removeFirst()
    }

    private func finishDeliveryIfDrained() {
        deliveryTask = nil
        if isEnding {
            isEnding = false
        }
    }
}
