import Foundation

public struct SpoolTranscriptionFinalizationResult: Equatable, Sendable {
    public let segments: [TranscriptSegment]
    public let processedFrameCount: Int

    public init(segments: [TranscriptSegment], processedFrameCount: Int) {
        self.segments = segments
        self.processedFrameCount = processedFrameCount
    }
}

public struct SpoolTranscriptFinalizer: Sendable {
    private let decoder: any RollingWindowTranscribing
    private let maximumWindowDuration: TimeInterval

    public init(
        decoder: any RollingWindowTranscribing,
        maximumWindowDuration: TimeInterval = 20
    ) {
        self.decoder = decoder
        self.maximumWindowDuration = max(maximumWindowDuration, 1)
    }

    public func finalize(
        sessionID: UUID,
        lane: CaptureLane = .mic,
        chunks: [CapturedAudioChunk]
    ) async throws -> SpoolTranscriptionFinalizationResult {
        let ordered = chunks
            .filter { $0.sessionID == sessionID && $0.lane == lane }
            .sorted { $0.startedAt < $1.startedAt }
        guard let first = ordered.first else {
            return SpoolTranscriptionFinalizationResult(segments: [], processedFrameCount: 0)
        }

        let sampleRate = first.sampleRate
        guard sampleRate > 0,
              ordered.allSatisfy({
                  $0.sampleRate == sampleRate
                      && $0.channelCount == 1
                      && $0.samples.channelCount == 1
              }) else {
            throw CaptureSessionSpoolError.invalidAudio
        }

        var samples: ContiguousArray<Float> = []
        samples.reserveCapacity(ordered.reduce(0) { $0 + $1.samples.samples.count })
        for chunk in ordered {
            samples.append(contentsOf: chunk.samples.samples)
        }

        let maximumFrames = max(1, Int(maximumWindowDuration * sampleRate))
        var segments: [TranscriptSegment] = []
        var frameOffset = 0

        while frameOffset < samples.count {
            let frameEnd = min(frameOffset + maximumFrames, samples.count)
            let windowStart = first.startedAt + (Double(frameOffset) / sampleRate)
            let windowDuration = Double(frameEnd - frameOffset) / sampleRate
            let window = RollingAudioWindow(
                sessionID: sessionID,
                lane: lane,
                startedAt: windowStart,
                duration: windowDuration,
                sampleRate: sampleRate,
                samples: ContiguousArray(samples[frameOffset..<frameEnd])
            )
            let hypothesis = try await decoder.transcribe(window: window, prompt: "")
            let text = hypothesis.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                segments.append(TranscriptSegment(
                    meetingID: sessionID,
                    lane: lane == .mic ? .me : .others,
                    state: .final,
                    startTime: windowStart,
                    endTime: windowStart + windowDuration,
                    text: text
                ))
            }
            frameOffset = frameEnd
        }

        return SpoolTranscriptionFinalizationResult(
            segments: segments,
            processedFrameCount: samples.count
        )
    }

    public func finalize(
        sessionID: UUID,
        lane: CaptureLane = .mic,
        spool: any CaptureSessionSpooling
    ) async throws -> SpoolTranscriptionFinalizationResult {
        let snapshot = try await spool.readSession(sessionID)
        let metadata = snapshot.chunks
            .filter { $0.lane == lane }
            .sorted { $0.sequence < $1.sequence }
        guard let first = metadata.first else {
            return SpoolTranscriptionFinalizationResult(segments: [], processedFrameCount: 0)
        }

        let sampleRate = first.sampleRate
        guard sampleRate > 0,
              metadata.allSatisfy({ $0.sampleRate == sampleRate && $0.channelCount == 1 }) else {
            throw CaptureSessionSpoolError.invalidAudio
        }

        let maximumFrames = max(1, Int(maximumWindowDuration * sampleRate))
        var pendingSamples: ContiguousArray<Float> = []
        pendingSamples.reserveCapacity(maximumFrames + 4_096)
        var processedFrameCount = 0
        var segments: [TranscriptSegment] = []

        for chunkMetadata in metadata {
            let audio = try await spool.readSamples(for: chunkMetadata)
            pendingSamples.append(contentsOf: audio.samples)

            while pendingSamples.count >= maximumFrames {
                let windowSamples = ContiguousArray(pendingSamples.prefix(maximumFrames))
                pendingSamples.removeFirst(maximumFrames)
                if let segment = try await decodeFinalSegment(
                    sessionID: sessionID,
                    lane: lane,
                    sampleRate: sampleRate,
                    baseStartedAt: first.startedAt,
                    frameOffset: processedFrameCount,
                    samples: windowSamples
                ) {
                    segments.append(segment)
                }
                processedFrameCount += windowSamples.count
            }
        }

        if !pendingSamples.isEmpty {
            let finalSamples = pendingSamples
            if let segment = try await decodeFinalSegment(
                sessionID: sessionID,
                lane: lane,
                sampleRate: sampleRate,
                baseStartedAt: first.startedAt,
                frameOffset: processedFrameCount,
                samples: finalSamples
            ) {
                segments.append(segment)
            }
            processedFrameCount += finalSamples.count
        }

        return SpoolTranscriptionFinalizationResult(
            segments: segments,
            processedFrameCount: processedFrameCount
        )
    }

    private func decodeFinalSegment(
        sessionID: UUID,
        lane: CaptureLane,
        sampleRate: Double,
        baseStartedAt: TimeInterval,
        frameOffset: Int,
        samples: ContiguousArray<Float>
    ) async throws -> TranscriptSegment? {
        let startedAt = baseStartedAt + (Double(frameOffset) / sampleRate)
        let duration = Double(samples.count) / sampleRate
        let hypothesis = try await decoder.transcribe(
            window: RollingAudioWindow(
                sessionID: sessionID,
                lane: lane,
                startedAt: startedAt,
                duration: duration,
                sampleRate: sampleRate,
                samples: samples
            ),
            prompt: ""
        )
        let text = hypothesis.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        return TranscriptSegment(
            meetingID: sessionID,
            lane: lane == .mic ? .me : .others,
            state: .final,
            startTime: startedAt,
            endTime: startedAt + duration,
            text: text
        )
    }
}
