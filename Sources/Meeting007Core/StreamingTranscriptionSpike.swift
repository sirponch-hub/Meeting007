import Foundation

public struct RollingAudioWindow: Equatable, Sendable {
    public let sessionID: UUID
    public let lane: CaptureLane
    public let startedAt: TimeInterval
    public let duration: TimeInterval
    public let sampleRate: Double
    public let samples: ContiguousArray<Float>

    public init(
        sessionID: UUID,
        lane: CaptureLane,
        startedAt: TimeInterval,
        duration: TimeInterval,
        sampleRate: Double,
        samples: ContiguousArray<Float>
    ) {
        self.sessionID = sessionID
        self.lane = lane
        self.startedAt = startedAt
        self.duration = duration
        self.sampleRate = sampleRate
        self.samples = samples
    }
}

public struct RollingAudioBuffer: Sendable {
    public let capacityDuration: TimeInterval
    private var chunks: [CapturedAudioChunk] = []

    public init(capacityDuration: TimeInterval) {
        self.capacityDuration = max(capacityDuration, 0)
    }

    public mutating func append(_ chunk: CapturedAudioChunk) {
        guard chunk.samples.sampleRate > 0,
              chunk.samples.channelCount == 1,
              !chunk.samples.samples.isEmpty else {
            return
        }

        chunks.append(chunk)
        trim(keepingSamplesAfter: chunk.startedAt + chunk.duration - capacityDuration)
    }

    public mutating func clear() {
        chunks.removeAll()
    }

    public func recentWindow(
        sessionID: UUID,
        lane: CaptureLane,
        duration requestedDuration: TimeInterval
    ) -> RollingAudioWindow? {
        let laneChunks = chunks
            .filter { $0.sessionID == sessionID && $0.lane == lane }
            .sorted { $0.startedAt < $1.startedAt }
        guard let latest = laneChunks.last else {
            return nil
        }

        let cutoff = latest.startedAt + latest.duration - max(requestedDuration, 0)
        let included = laneChunks.filter { $0.startedAt + $0.duration > cutoff }
        guard let first = included.first else {
            return nil
        }

        var samples: ContiguousArray<Float> = []
        for chunk in included {
            if chunk.startedAt < cutoff {
                let skippedSamples = min(
                    chunk.samples.samples.count,
                    max(0, Int(((cutoff - chunk.startedAt) * chunk.samples.sampleRate).rounded()))
                )
                samples.append(contentsOf: chunk.samples.samples.dropFirst(skippedSamples))
            } else {
                samples.append(contentsOf: chunk.samples.samples)
            }
        }

        let startedAt = max(first.startedAt, cutoff)
        let endAt = latest.startedAt + latest.duration
        return RollingAudioWindow(
            sessionID: sessionID,
            lane: lane,
            startedAt: startedAt,
            duration: max(endAt - startedAt, 0),
            sampleRate: latest.samples.sampleRate,
            samples: samples
        )
    }

    public func bufferedDuration(sessionID: UUID, lane: CaptureLane) -> TimeInterval {
        let laneChunks = chunks
            .filter { $0.sessionID == sessionID && $0.lane == lane }
            .sorted { $0.startedAt < $1.startedAt }
        guard let first = laneChunks.first, let last = laneChunks.last else {
            return 0
        }
        return max((last.startedAt + last.duration) - first.startedAt, 0)
    }

    private mutating func trim(keepingSamplesAfter cutoff: TimeInterval) {
        chunks.removeAll { chunk in
            chunk.startedAt + chunk.duration <= cutoff
        }
    }
}

public struct RollingTranscriptionHypothesis: Equatable, Sendable {
    public let text: String
    public let windowStartedAt: TimeInterval
    public let windowEndedAt: TimeInterval

    public init(text: String, windowStartedAt: TimeInterval, windowEndedAt: TimeInterval) {
        self.text = text
        self.windowStartedAt = windowStartedAt
        self.windowEndedAt = windowEndedAt
    }
}

public protocol RollingWindowTranscribing: Sendable {
    func transcribe(window: RollingAudioWindow, prompt: String) async throws -> RollingTranscriptionHypothesis
}

public struct StreamingTranscriptUpdate: Equatable, Sendable {
    public let committedText: String
    public let partialText: String

    public init(committedText: String, partialText: String) {
        self.committedText = committedText
        self.partialText = partialText
    }
}

public struct LocalAgreementTranscriptStabilizer: Sendable {
    private var previousHypothesis = ""
    private var committedText = ""

    public init() {}

    public mutating func observe(_ hypothesis: String) -> StreamingTranscriptUpdate {
        let normalizedHypothesis = normalize(hypothesis)
        let candidate = commonPrefix(previousHypothesis, normalizedHypothesis)
        let newCommit = trimToLastWord(candidate)

        if newCommit.count > committedText.count {
            committedText = newCommit
        }

        previousHypothesis = normalizedHypothesis
        let partial = normalizedHypothesis.hasPrefix(committedText)
            ? String(normalizedHypothesis.dropFirst(committedText.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            : normalizedHypothesis

        return StreamingTranscriptUpdate(committedText: committedText, partialText: partial)
    }

    public func committedPrompt() -> String {
        committedText
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commonPrefix(_ lhs: String, _ rhs: String) -> String {
        var result = ""
        for (left, right) in zip(lhs, rhs) {
            guard left == right else {
                break
            }
            result.append(left)
        }
        return result
    }

    private func trimToLastWord(_ text: String) -> String {
        guard let lastSpace = text.lastIndex(where: { $0.isWhitespace }) else {
            return ""
        }
        return String(text[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public actor RollingStreamingTranscriptionSession {
    private let sessionID: UUID
    private let lane: CaptureLane
    private let windowDuration: TimeInterval
    private let decoder: any RollingWindowTranscribing
    private var buffer: RollingAudioBuffer
    private var stabilizer = LocalAgreementTranscriptStabilizer()
    private var lastUpdate = StreamingTranscriptUpdate(committedText: "", partialText: "")

    public init(
        sessionID: UUID,
        lane: CaptureLane = .mic,
        bufferDuration: TimeInterval = 30,
        windowDuration: TimeInterval = 20,
        decoder: any RollingWindowTranscribing
    ) {
        self.sessionID = sessionID
        self.lane = lane
        self.windowDuration = windowDuration
        self.decoder = decoder
        self.buffer = RollingAudioBuffer(capacityDuration: bufferDuration)
    }

    public func receive(_ chunk: CapturedAudioChunk) {
        guard chunk.sessionID == sessionID, chunk.lane == lane else {
            return
        }
        buffer.append(chunk)
    }

    public func tick() async throws -> StreamingTranscriptUpdate {
        guard let window = buffer.recentWindow(sessionID: sessionID, lane: lane, duration: windowDuration) else {
            return lastUpdate
        }

        let hypothesis = try await decoder.transcribe(window: window, prompt: stabilizer.committedPrompt())
        lastUpdate = stabilizer.observe(hypothesis.text)
        return lastUpdate
    }

    public func bufferedDuration() -> TimeInterval {
        buffer.bufferedDuration(sessionID: sessionID, lane: lane)
    }

    public func stop() {
        buffer.clear()
        stabilizer = LocalAgreementTranscriptStabilizer()
        lastUpdate = StreamingTranscriptUpdate(committedText: "", partialText: "")
    }
}
