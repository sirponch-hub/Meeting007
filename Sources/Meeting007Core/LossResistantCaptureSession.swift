import Foundation

public actor LossResistantCaptureSession: AudioChunkConsumer {
    private let spool: any CaptureSessionSpooling
    private let markers: CaptureLatencyMarkers
    private let liveConsumer: RuntimeOnlyAudioChunkConsumer?
    private var activeSessionID: UUID?
    private var acceptsAudio = false
    private var pendingSpoolChunks: [CapturedAudioChunk] = []
    private var spoolDrainTask: Task<Void, Never>?
    private var pendingLiveChunks: [CapturedAudioChunk] = []
    private var liveDrainTask: Task<Void, Never>?
    private var stickyFailure: CaptureSessionSpoolError?
    private var liveBacklogOverflowed = false
    private var stopRequested = false
    private var receivedFirstAudio = false
    private var spooledFirstAudio = false
    private let maximumPendingSpoolChunks = 256
    private let maximumPendingLiveChunks = 64

    public init(
        spool: any CaptureSessionSpooling = LocalCaptureSessionSpool(),
        markers: CaptureLatencyMarkers = CaptureLatencyMarkers(),
        liveConsumer: RuntimeOnlyAudioChunkConsumer? = nil
    ) {
        self.spool = spool
        self.markers = markers
        self.liveConsumer = liveConsumer
    }

    public func begin(sessionID: UUID) async throws {
        await markers.mark(sessionID: sessionID, event: .startRequested)
        try await spool.begin(sessionID: sessionID)
        await markers.mark(sessionID: sessionID, event: .spoolReady)
        await liveConsumer?.begin(sessionID: sessionID)
        activeSessionID = sessionID
        acceptsAudio = true
        stickyFailure = nil
        liveBacklogOverflowed = false
        stopRequested = false
        receivedFirstAudio = false
        spooledFirstAudio = false
        pendingSpoolChunks.removeAll()
        pendingLiveChunks.removeAll()
    }

    public func receive(_ chunk: CapturedAudioChunk) async {
        guard acceptsAudio, activeSessionID == chunk.sessionID, stickyFailure == nil else {
            return
        }
        if !receivedFirstAudio {
            receivedFirstAudio = true
            await markers.mark(sessionID: chunk.sessionID, event: .firstAudioReceived)
        }
        guard pendingSpoolChunks.count < maximumPendingSpoolChunks else {
            stickyFailure = .backlogOverflow
            acceptsAudio = false
            return
        }
        pendingSpoolChunks.append(chunk)
        startSpoolDrainIfNeeded()
    }

    public func requestStop(sessionID: UUID) async {
        guard activeSessionID == sessionID, !stopRequested else {
            return
        }
        stopRequested = true
        await markers.mark(sessionID: sessionID, event: .stopRequested)
    }

    public func close(sessionID: UUID) async throws {
        guard activeSessionID == sessionID else {
            throw CaptureSessionSpoolError.wrongSession
        }
        await requestStop(sessionID: sessionID)
        acceptsAudio = false
        await markers.mark(sessionID: sessionID, event: .captureStopped)
        if let spoolDrainTask {
            await spoolDrainTask.value
        }

        if let stickyFailure {
            try? await spool.close(sessionID: sessionID)
            activeSessionID = nil
            await markers.mark(sessionID: sessionID, event: .spoolFailed)
            throw stickyFailure
        }

        try await spool.close(sessionID: sessionID)
        await markers.mark(sessionID: sessionID, event: .spoolClosed)
        activeSessionID = nil

        if let liveConsumer {
            let pendingLiveDrain = liveDrainTask
            Task {
                await pendingLiveDrain?.value
                await liveConsumer.end(sessionID: sessionID)
            }
        }
    }

    public func failure() -> CaptureSessionSpoolError? {
        stickyFailure
    }

    public func shouldPreserveSpool() -> Bool {
        stickyFailure != nil || liveBacklogOverflowed
    }

    public func cleanup(sessionID: UUID) async throws {
        try await spool.cleanup(sessionID: sessionID)
        await markers.clear(sessionID: sessionID)
    }

    public func recoveredChunks(sessionID: UUID) async throws -> [CapturedAudioChunk] {
        let snapshot = try await spool.readSession(sessionID)
        var chunks: [CapturedAudioChunk] = []
        chunks.reserveCapacity(snapshot.chunks.count)
        for metadata in snapshot.chunks.sorted(by: { $0.sequence < $1.sequence }) {
            let samples = try await spool.readSamples(for: metadata)
            chunks.append(CapturedAudioChunk(
                sessionID: metadata.sessionID,
                lane: metadata.lane,
                startedAt: metadata.startedAt,
                duration: metadata.duration,
                sampleRate: metadata.sampleRate,
                channelCount: metadata.channelCount,
                byteCount: metadata.byteCount,
                samples: samples
            ))
        }
        return chunks
    }

    public func finalizationSpool() -> any CaptureSessionSpooling {
        spool
    }

    private func startSpoolDrainIfNeeded() {
        guard spoolDrainTask == nil else {
            return
        }
        spoolDrainTask = Task {
            await self.drainSpoolQueue()
        }
    }

    private func drainSpoolQueue() async {
        while !pendingSpoolChunks.isEmpty, stickyFailure == nil {
            let chunk = pendingSpoolChunks.removeFirst()
            do {
                _ = try await spool.append(chunk)
                if !spooledFirstAudio {
                    spooledFirstAudio = true
                    await markers.mark(sessionID: chunk.sessionID, event: .firstAudioSpooled)
                }
                if pendingLiveChunks.count >= maximumPendingLiveChunks {
                    pendingLiveChunks.removeFirst()
                    liveBacklogOverflowed = true
                }
                pendingLiveChunks.append(chunk)
                startLiveDrainIfNeeded()
            } catch {
                stickyFailure = (error as? CaptureSessionSpoolError) ?? .storageFailure
                pendingSpoolChunks.removeAll()
            }
        }
        spoolDrainTask = nil
    }

    private func startLiveDrainIfNeeded() {
        guard liveConsumer != nil, liveDrainTask == nil else {
            return
        }
        liveDrainTask = Task {
            await self.drainLiveQueue()
        }
    }

    private func drainLiveQueue() async {
        while !pendingLiveChunks.isEmpty {
            let chunk = pendingLiveChunks.removeFirst()
            await liveConsumer?.receive(chunk)
        }
        liveDrainTask = nil
    }
}
