import Foundation

public struct VADSpeechChunker: Sendable {
    public struct Configuration: Equatable, Sendable {
        public let speechLevelThreshold: Float
        public let trailingSilenceDuration: TimeInterval
        public let maximumSpeechDuration: TimeInterval

        public init(
            speechLevelThreshold: Float,
            trailingSilenceDuration: TimeInterval,
            maximumSpeechDuration: TimeInterval
        ) {
            self.speechLevelThreshold = speechLevelThreshold
            self.trailingSilenceDuration = trailingSilenceDuration
            self.maximumSpeechDuration = maximumSpeechDuration
        }

        public static let `default` = Configuration(
            speechLevelThreshold: 0.018,
            trailingSilenceDuration: 0.7,
            maximumSpeechDuration: 25
        )
    }

    private struct ActiveSpeechWindow: Equatable, Sendable {
        var sessionID: UUID
        var lane: CaptureLane
        var startedAt: TimeInterval
        var lastSpeechEndAt: TimeInterval
        var sampleRate: Double
        var samples: ContiguousArray<Float>
        var trailingSilence: TimeInterval
    }

    private let configuration: Configuration
    private var activeSessionID: UUID?
    private var activeWindows: [CaptureLane: ActiveSpeechWindow] = [:]

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    public mutating func begin(sessionID: UUID) {
        activeSessionID = sessionID
        activeWindows.removeAll()
    }

    public mutating func receive(_ chunk: CapturedAudioChunk) -> [SpeechChunk] {
        guard activeSessionID == chunk.sessionID,
              chunk.samples.sampleRate > 0,
              chunk.samples.channelCount == 1,
              !chunk.samples.samples.isEmpty else {
            return []
        }

        let level = rmsLevel(chunk.samples.samples)
        let isSpeech = level >= configuration.speechLevelThreshold

        if isSpeech {
            return appendSpeech(chunk)
        }

        return appendSilence(chunk)
    }

    public mutating func end(sessionID: UUID) -> [SpeechChunk] {
        guard activeSessionID == sessionID else {
            return []
        }

        activeSessionID = nil
        let chunks = activeWindows.values
            .sorted { lhs, rhs in
                if lhs.startedAt == rhs.startedAt {
                    return lhs.lane.rawValue < rhs.lane.rawValue
                }
                return lhs.startedAt < rhs.startedAt
            }
            .map(finalize)
        activeWindows.removeAll()
        return chunks
    }

    private mutating func appendSpeech(_ chunk: CapturedAudioChunk) -> [SpeechChunk] {
        var window = activeWindows[chunk.lane] ?? ActiveSpeechWindow(
            sessionID: chunk.sessionID,
            lane: chunk.lane,
            startedAt: chunk.startedAt,
            lastSpeechEndAt: chunk.startedAt,
            sampleRate: chunk.samples.sampleRate,
            samples: [],
            trailingSilence: 0
        )

        window.samples.append(contentsOf: chunk.samples.samples)
        window.lastSpeechEndAt = chunk.startedAt + chunk.duration
        window.trailingSilence = 0
        activeWindows[chunk.lane] = window

        if window.lastSpeechEndAt - window.startedAt >= configuration.maximumSpeechDuration {
            activeWindows[chunk.lane] = nil
            return [finalize(window)]
        }

        return []
    }

    private mutating func appendSilence(_ chunk: CapturedAudioChunk) -> [SpeechChunk] {
        guard var window = activeWindows[chunk.lane] else {
            return []
        }

        window.trailingSilence += chunk.duration
        guard window.trailingSilence >= configuration.trailingSilenceDuration else {
            activeWindows[chunk.lane] = window
            return []
        }

        activeWindows[chunk.lane] = nil
        return [finalize(window)]
    }

    private func finalize(_ window: ActiveSpeechWindow) -> SpeechChunk {
        SpeechChunk(
            sessionID: window.sessionID,
            lane: window.lane,
            startedAt: window.startedAt,
            duration: max(window.lastSpeechEndAt - window.startedAt, 0),
            sampleRate: window.sampleRate,
            samples: window.samples,
            isFinalInUtterance: true
        )
    }

    private func rmsLevel(_ samples: ContiguousArray<Float>) -> Float {
        guard !samples.isEmpty else {
            return 0
        }

        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }

        return sqrt(sum / Float(samples.count))
    }
}
