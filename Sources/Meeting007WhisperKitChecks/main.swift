import Foundation
import Meeting007Core
import Meeting007WhisperKit

@main
struct Meeting007WhisperKitChecks {
    static func main() async {
        checkWhisperKitAdapterDefaultsToRussian()
        checkWhisperKitAdapterAcceptsSpeechChunkBoundary()
        await checkWhisperKitAdapterRequiresInstalledModel()
        await checkWhisperKitAdapterBuildsEngineFromVerifiedModelDirectory()
        await checkWhisperKitAdapterDoesNotBuildEngineForMissingModelDirectory()
        await checkProductionWhisperKitPipelineDoesNotEmitFakeTextWhenModelMissing()
        await checkWhisperKitRuntimeFailureIsReported()
        await checkWhisperKitAdapterMapsResultToTranscriptSegment()
        await checkWhisperKitRollingAdapterBuildsEngineFromVerifiedModelDirectory()
        await checkWhisperKitRollingAdapterReusesPreparedWarmEngine()
        await checkWhisperKitRollingAdapterKeepsWarmEngineAfterStopWhenConfigured()
        await checkWhisperKitRollingAdapterDoesNotBuildEngineForMissingModelDirectory()
        await checkWhisperKitRollingAdapterForwardsPromptAndWindow()
        await checkWhisperKitRollingAdapterDisablesWordTimestampsForLiveDecode()
        await checkWhisperKitRollingAdapterSerializesRuntimeDecode()
        await checkWhisperKitRollingRuntimeFailureIsReported()
        await checkWhisperKitFailureDoesNotBreakFakeRussianSTT()
        checkWhisperKitAdapterDoesNotPersistSpeechChunks()
        print("Meeting007WhisperKitChecks passed")
    }

    private static func checkWhisperKitAdapterDefaultsToRussian() {
        let configuration = WhisperKitAdapterConfiguration()

        require(configuration.language == "ru", "WhisperKit adapter must default to Russian.")
        require(configuration.modelPolicy == .defaultRussian, "WhisperKit adapter must use the pinned Russian model policy.")
        require(!configuration.allowsAutomaticModelDownload, "WhisperKit adapter must not automatically download models.")
    }

    private static func checkWhisperKitAdapterAcceptsSpeechChunkBoundary() {
        let chunk = makeSpeechChunk()
        let accepted = WhisperKitSpeechChunkValidator.accepts(chunk)

        require(accepted, "WhisperKit adapter must accept normalized 16 kHz mono SpeechChunk input.")
    }

    private static func checkWhisperKitAdapterRequiresInstalledModel() async {
        let modelManager = FakeLocalSTTModelManager(availability: .missing)
        let adapter = WhisperKitSpeechTranscriber(
            modelManager: modelManager,
            engine: FakeWhisperKitTranscriptionEngine(result: "не должен вызываться")
        )
        let sessionID = UUID()

        let start = await adapter.start(config: STTSessionConfig(sessionID: sessionID))
        let segments = await adapter.receive(makeSpeechChunk(sessionID: sessionID))
        let downloadAttempts = await adapter.automaticDownloadAttempts()

        require(start == .unavailable(TranscriptionFailure(
            code: "local_stt_model_missing",
            message: "The Russian transcription model is not installed on this Mac."
        )), "Missing local WhisperKit model must return a stable unavailable state.")
        require(segments.isEmpty, "WhisperKit adapter must not transcribe when the model is missing.")
        require(downloadAttempts == 0, "WhisperKit adapter must not start a model download.")
    }

    private static func checkWhisperKitAdapterBuildsEngineFromVerifiedModelDirectory() async {
        let verifiedDirectory = URL(fileURLWithPath: "/tmp/Meeting007VerifiedModel", isDirectory: true)
        let provider = FakeLocalSTTModelPathProvider(result: .ready(verifiedDirectory))
        let factory = WhisperKitEngineFactorySpy(result: "Реальная локальная транскрибация.")
        let adapter = WhisperKitSpeechTranscriber(
            modelPathProvider: provider,
            engineFactory: factory.makeEngine(modelDirectory:)
        )
        let sessionID = UUID()

        let start = await adapter.start(config: STTSessionConfig(sessionID: sessionID))
        let segments = await adapter.receive(makeSpeechChunk(sessionID: sessionID, startedAt: 3, duration: 1))
        let requestedPolicies = await provider.requestedPolicies()

        require(start == .ready, "Verified model directory must allow real WhisperKit adapter start.")
        require(factory.modelDirectories() == [verifiedDirectory], "WhisperKit engine must be built from the verified local model directory.")
        require(factory.prepareCount() == 1, "WhisperKit engine must be prepared once at session start.")
        require(requestedPolicies == [.defaultRussian], "WhisperKit adapter must request the pinned Russian model policy.")
        require(segments.first?.text == "Реальная локальная транскрибация.", "Verified model path adapter must return engine transcript text.")
    }

    private static func checkWhisperKitAdapterDoesNotBuildEngineForMissingModelDirectory() async {
        let provider = FakeLocalSTTModelPathProvider(result: .unavailable(.missing))
        let factory = WhisperKitEngineFactorySpy(result: "не должен вызываться")
        let adapter = WhisperKitSpeechTranscriber(
            modelPathProvider: provider,
            engineFactory: factory.makeEngine(modelDirectory:)
        )

        let start = await adapter.start(config: STTSessionConfig(sessionID: UUID()))
        let downloadAttempts = await adapter.automaticDownloadAttempts()

        require(start == .unavailable(TranscriptionFailure(
            code: "local_stt_model_missing",
            message: "The Russian transcription model is not installed on this Mac."
        )), "Missing verified model directory must return stable unavailable state.")
        require(factory.modelDirectories().isEmpty, "WhisperKit engine must not be built when the model directory is missing.")
        require(downloadAttempts == 0, "Missing model directory must not trigger automatic download.")
    }

    private static func checkProductionWhisperKitPipelineDoesNotEmitFakeTextWhenModelMissing() async {
        let pipeline = WhisperKitTranscriptionPipelineFactory.makeProductionPipeline(
            modelPathProvider: FakeLocalSTTModelPathProvider(result: .unavailable(.missing))
        )
        let sessionID = UUID()

        let start = await pipeline.start(STTSessionConfig(sessionID: sessionID))
        let segments = await pipeline.receive(makeSpeechChunk(sessionID: sessionID, startedAt: 0, duration: 1))

        require(start == .unavailable(TranscriptionFailure(
            code: "local_stt_model_missing",
            message: "The Russian transcription model is not installed on this Mac."
        )), "Production WhisperKit pipeline must report missing local model.")
        require(segments.isEmpty, "Production WhisperKit pipeline must not emit fake transcript text when the model is missing.")
    }

    private static func checkWhisperKitRuntimeFailureIsReported() async {
        let adapter = WhisperKitSpeechTranscriber(
            modelManager: FakeLocalSTTModelManager(availability: .ready),
            engine: ThrowingWhisperKitTranscriptionEngine()
        )
        let sessionID = UUID()

        let start = await adapter.start(config: STTSessionConfig(sessionID: sessionID))
        let segments = await adapter.receive(makeSpeechChunk(sessionID: sessionID, startedAt: 0, duration: 1))
        let failure = await adapter.lastFailure()

        require(start == .ready, "Runtime failure check must start with a ready model.")
        require(segments.isEmpty, "Runtime transcription failure should not emit misleading transcript text.")
        require(failure == TranscriptionFailure(
            code: "local_stt_runtime_failed",
            message: "Local transcription stopped unexpectedly."
        ), "Runtime transcription failure must be observable by the app.")
    }

    private static func checkWhisperKitAdapterMapsResultToTranscriptSegment() async {
        let adapter = WhisperKitSpeechTranscriber(
            modelManager: FakeLocalSTTModelManager(availability: .ready),
            engine: FakeWhisperKitTranscriptionEngine(result: "Привет, это локальная проверка.")
        )
        let sessionID = UUID()

        let start = await adapter.start(config: STTSessionConfig(sessionID: sessionID))
        let segments = await adapter.receive(makeSpeechChunk(sessionID: sessionID, startedAt: 2, duration: 1.5))

        require(start == .ready, "Ready local WhisperKit model must allow adapter start.")
        require(segments.count == 1, "WhisperKit adapter must map one engine result to one transcript segment.")
        require(segments.first?.meetingID == sessionID, "WhisperKit transcript segment must keep meeting ID.")
        require(segments.first?.lane == .me, "Mic SpeechChunk must map to Me lane.")
        require(segments.first?.state == .final, "WhisperKit spike adapter must emit final speech-window segments.")
        require(segments.first?.startTime == 2, "WhisperKit transcript segment must keep SpeechChunk start time.")
        require(segments.first?.endTime == 3.5, "WhisperKit transcript segment must keep SpeechChunk end time.")
        require(segments.first?.text == "Привет, это локальная проверка.", "WhisperKit transcript segment must carry engine text.")
    }

    private static func checkWhisperKitRollingAdapterBuildsEngineFromVerifiedModelDirectory() async {
        let verifiedDirectory = URL(fileURLWithPath: "/tmp/Meeting007VerifiedRollingModel", isDirectory: true)
        let provider = FakeLocalSTTModelPathProvider(result: .ready(verifiedDirectory))
        let factory = WhisperKitRollingEngineFactorySpy(result: "проверка rolling decode")
        let adapter = WhisperKitRollingWindowTranscriber(
            modelPathProvider: provider,
            engineFactory: factory.makeEngine(modelDirectory:)
        )

        let start = await adapter.prepare()
        let hypothesis = try? await adapter.transcribe(window: makeRollingWindow(startedAt: 4, duration: 2), prompt: "")
        let requestedPolicies = await provider.requestedPolicies()

        require(start == .ready, "Verified model directory must allow rolling WhisperKit adapter start.")
        require(factory.modelDirectories() == [verifiedDirectory], "Rolling WhisperKit engine must be built from the verified local model directory.")
        require(factory.prepareCount() == 1, "Rolling WhisperKit engine must be prepared once at session start.")
        require(requestedPolicies == [.defaultRussian], "Rolling WhisperKit adapter must request the pinned Russian model policy.")
        require(hypothesis?.text == "проверка rolling decode", "Rolling WhisperKit adapter must return engine hypothesis text.")
    }

    private static func checkWhisperKitRollingAdapterReusesPreparedWarmEngine() async {
        let verifiedDirectory = URL(fileURLWithPath: "/tmp/Meeting007VerifiedWarmRollingModel", isDirectory: true)
        let provider = FakeLocalSTTModelPathProvider(result: .ready(verifiedDirectory))
        let factory = WhisperKitRollingEngineFactorySpy(result: "готовый warm runtime")
        let adapter = WhisperKitRollingWindowTranscriber(
            modelPathProvider: provider,
            engineFactory: factory.makeEngine(modelDirectory:)
        )

        let prewarm = await adapter.prepare()
        let startPrepare = await adapter.prepare()
        let hypothesis = try? await adapter.transcribe(window: makeRollingWindow(startedAt: 1, duration: 1), prompt: "")

        require(prewarm == .ready, "Warm rolling adapter prewarm must prepare a verified local model.")
        require(startPrepare == .ready, "Start-time rolling prepare must reuse the warm engine.")
        require(factory.modelDirectories() == [verifiedDirectory], "Warm rolling adapter must not rebuild the engine at recording start.")
        require(factory.prepareCount() == 1, "Warm rolling adapter must not prepare WhisperKit twice when already warm.")
        require(hypothesis?.text == "готовый warm runtime", "Warm rolling adapter must remain usable after reused prepare.")
    }

    private static func checkWhisperKitRollingAdapterKeepsWarmEngineAfterStopWhenConfigured() async {
        let verifiedDirectory = URL(fileURLWithPath: "/tmp/Meeting007VerifiedWarmStopModel", isDirectory: true)
        let provider = FakeLocalSTTModelPathProvider(result: .ready(verifiedDirectory))
        let factory = WhisperKitRollingEngineFactorySpy(result: "runtime пережил stop")
        let adapter = WhisperKitRollingWindowTranscriber(
            modelPathProvider: provider,
            keepsEngineWarmAfterStop: true,
            engineFactory: factory.makeEngine(modelDirectory:)
        )

        let prewarm = await adapter.prepare()
        await adapter.stop()
        let nextStart = await adapter.prepare()
        let hypothesis = try? await adapter.transcribe(window: makeRollingWindow(startedAt: 2, duration: 1), prompt: "")

        require(prewarm == .ready, "Warm-stop check must start from a prepared local engine.")
        require(nextStart == .ready, "Warm rolling adapter must remain ready after session stop when configured.")
        require(factory.modelDirectories() == [verifiedDirectory], "Session stop must not rebuild a kept-warm rolling engine.")
        require(factory.prepareCount() == 1, "Session stop must not destroy a kept-warm rolling runtime.")
        require(hypothesis?.text == "runtime пережил stop", "Kept-warm rolling adapter must decode after session stop and next prepare.")
    }

    private static func checkWhisperKitRollingAdapterDoesNotBuildEngineForMissingModelDirectory() async {
        let provider = FakeLocalSTTModelPathProvider(result: .unavailable(.missing))
        let factory = WhisperKitRollingEngineFactorySpy(result: "не должен вызываться")
        let adapter = WhisperKitRollingWindowTranscriber(
            modelPathProvider: provider,
            engineFactory: factory.makeEngine(modelDirectory:)
        )

        let start = await adapter.prepare()

        require(start == .unavailable(TranscriptionFailure(
            code: "local_stt_model_missing",
            message: "The Russian transcription model is not installed on this Mac."
        )), "Missing verified model directory must return stable unavailable state for rolling adapter.")
        require(factory.modelDirectories().isEmpty, "Rolling WhisperKit engine must not be built when the model directory is missing.")
    }

    private static func checkWhisperKitRollingAdapterForwardsPromptAndWindow() async {
        let engine = RecordingRollingWhisperKitEngine(result: "следующий rolling результат")
        let adapter = WhisperKitRollingWindowTranscriber(engine: engine)
        let window = makeRollingWindow(startedAt: 8, duration: 3)

        let start = await adapter.prepare()
        let hypothesis = try? await adapter.transcribe(window: window, prompt: "предыдущий подтвержденный текст")
        let received = await engine.receivedRequests()

        require(start == .ready, "Fake rolling engine must allow adapter start.")
        require(received.count == 1, "Rolling adapter must send one decode request.")
        require(received.first?.window == window, "Rolling adapter must forward the rolling audio window unchanged.")
        require(received.first?.language == "ru", "Rolling adapter must default rolling decode to Russian.")
        require(received.first?.prompt == "предыдущий подтвержденный текст", "Rolling adapter must forward committed transcript prompt to the engine.")
        require(hypothesis?.windowStartedAt == 8, "Rolling adapter must keep window start timing.")
        require(hypothesis?.windowEndedAt == 11, "Rolling adapter must keep window end timing.")
    }

    private static func checkWhisperKitRollingAdapterDisablesWordTimestampsForLiveDecode() async {
        let engine = RecordingRollingWhisperKitEngine(result: "быстрый live decode")
        let adapter = WhisperKitRollingWindowTranscriber(decodeEngine: engine)

        let start = await adapter.prepare()
        _ = try? await adapter.transcribe(window: makeRollingWindow(startedAt: 1, duration: 3), prompt: "")
        let received = await engine.receivedRequests()

        require(start == .ready, "Rolling decode engine must allow adapter start.")
        require(received.first?.requiresWordTimestamps == false, "Live rolling decode must not request word timestamps that the UI does not use.")
    }

    private static func checkWhisperKitRollingAdapterSerializesRuntimeDecode() async {
        let engine = BlockingRollingWhisperKitEngine()
        let adapter = WhisperKitRollingWindowTranscriber(decodeEngine: engine)
        _ = await adapter.prepare()

        let first = Task {
            try? await adapter.transcribe(window: makeRollingWindow(startedAt: 0, duration: 1), prompt: "")
        }
        await engine.waitForCallCount(1)
        let second = Task {
            try? await adapter.transcribe(window: makeRollingWindow(startedAt: 1, duration: 1), prompt: "")
        }
        for _ in 0..<10 {
            await Task.yield()
        }

        let blockedCallCount = await engine.recordedCallCount()
        require(blockedCallCount == 1, "WhisperKit adapter must not enter one runtime concurrently while a decode is blocked.")
        await engine.releaseFirstCall()
        _ = await first.value
        _ = await second.value
        let maximumActive = await engine.recordedMaximumActiveCount()
        require(maximumActive == 1, "WhisperKit runtime decode concurrency must remain one across concurrent callers.")
    }

    private static func checkWhisperKitRollingRuntimeFailureIsReported() async {
        let adapter = WhisperKitRollingWindowTranscriber(engine: ThrowingRollingWhisperKitEngine())

        let start = await adapter.prepare()
        let hypothesis = try? await adapter.transcribe(window: makeRollingWindow(), prompt: "")
        let failure = await adapter.lastFailure()

        require(start == .ready, "Runtime failure check must start with a prepared rolling engine.")
        require(hypothesis == nil, "Runtime rolling failure should not emit misleading hypothesis text.")
        require(failure == TranscriptionFailure(
            code: "local_stt_runtime_failed",
            message: "Local rolling transcription stopped unexpectedly."
        ), "Rolling runtime transcription failure must be observable by the app.")
    }

    private static func checkWhisperKitFailureDoesNotBreakFakeRussianSTT() async {
        let sessionID = UUID()
        let pipeline = LocalSTTPipeline(transcriber: FakeRussianSpeechTranscriber())

        _ = await pipeline.start(STTSessionConfig(sessionID: sessionID))
        let partialSegments = await pipeline.receive(makeSpeechChunk(sessionID: sessionID, startedAt: 0, duration: 1.2))
        let finalSegments = await pipeline.receive(makeSpeechChunk(sessionID: sessionID, startedAt: 1.2, duration: 1.4))

        require(partialSegments.first?.state == .partial, "Fake Russian STT must keep deterministic partial output.")
        require(finalSegments.first?.state == .final, "Fake Russian STT must keep deterministic final output.")
        require(finalSegments.first?.text == "Это локальная русская транскрибация.", "Fake Russian STT text must remain stable.")
    }

    private static func checkWhisperKitAdapterDoesNotPersistSpeechChunks() {
        let chunk = makeSpeechChunk()
        let exportFolder = temporaryExportFolder()
        let audioExtensions = Set(["wav", "caf", "m4a", "pcm", "aiff", "flac", "mp3"])

        do {
            try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
            let before = try FileManager.default.contentsOfDirectory(at: exportFolder, includingPropertiesForKeys: nil)
            _ = WhisperKitSpeechChunkValidator.accepts(chunk)
            let after = try FileManager.default.contentsOfDirectory(at: exportFolder, includingPropertiesForKeys: nil)

            require(before == after, "WhisperKit adapter validation must not create files.")
            require(after.allSatisfy { !audioExtensions.contains($0.pathExtension.lowercased()) }, "WhisperKit adapter must not create raw audio artifacts.")
        } catch {
            require(false, "WhisperKit persistence check must not throw: \(error)")
        }
    }

    private static func makeSpeechChunk(
        sessionID: UUID = UUID(),
        startedAt: TimeInterval = 0,
        duration: TimeInterval = 1
    ) -> SpeechChunk {
        let sampleRate: Double = 16_000
        let sampleCount = max(1, Int(duration * sampleRate))
        return SpeechChunk(
            sessionID: sessionID,
            lane: .mic,
            startedAt: startedAt,
            duration: duration,
            sampleRate: sampleRate,
            samples: ContiguousArray(repeating: 0.2, count: sampleCount)
        )
    }

    private static func makeRollingWindow(
        sessionID: UUID = UUID(),
        startedAt: TimeInterval = 0,
        duration: TimeInterval = 1
    ) -> RollingAudioWindow {
        let sampleRate: Double = 16_000
        let sampleCount = max(1, Int(duration * sampleRate))
        return RollingAudioWindow(
            sessionID: sessionID,
            lane: .mic,
            startedAt: startedAt,
            duration: duration,
            sampleRate: sampleRate,
            samples: ContiguousArray(repeating: 0.2, count: sampleCount)
        )
    }

    private static func temporaryExportFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Meeting007WhisperKitChecks", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("Check failed: \(message)\n", stderr)
            exit(1)
        }
    }
}

private final class WhisperKitEngineFactorySpy: @unchecked Sendable {
    private let lock = NSLock()
    private let result: String
    private var directories: [URL] = []
    private var prepares = 0

    init(result: String) {
        self.result = result
    }

    func makeEngine(modelDirectory: URL) -> any WhisperKitTranscriptionEngine {
        lock.lock()
        directories.append(modelDirectory)
        lock.unlock()
        return PreparedSpyWhisperKitEngine(result: result) { [weak self] in
            self?.recordPrepare()
        }
    }

    func modelDirectories() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return directories
    }

    func prepareCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return prepares
    }

    private func recordPrepare() {
        lock.lock()
        prepares += 1
        lock.unlock()
    }
}

private struct PreparedSpyWhisperKitEngine: WhisperKitTranscriptionEngine {
    let result: String
    let onPrepare: @Sendable () -> Void

    func prepare() async throws {
        onPrepare()
    }

    func transcribe(_ chunk: SpeechChunk, language: String) async throws -> String {
        result
    }
}

private struct ThrowingWhisperKitTranscriptionEngine: WhisperKitTranscriptionEngine {
    func transcribe(_ chunk: SpeechChunk, language: String) async throws -> String {
        throw TranscriptionFailure(
            code: "test_runtime_failure",
            message: "Synthetic runtime failure."
        )
    }
}

private final class WhisperKitRollingEngineFactorySpy: @unchecked Sendable {
    private let lock = NSLock()
    private let result: String
    private var directories: [URL] = []
    private var prepares = 0

    init(result: String) {
        self.result = result
    }

    func makeEngine(modelDirectory: URL) -> any WhisperKitRollingDecodeEngine {
        lock.lock()
        directories.append(modelDirectory)
        lock.unlock()
        return RecordingRollingWhisperKitEngine(result: result) { [weak self] in
            self?.recordPrepare()
        }
    }

    func modelDirectories() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return directories
    }

    func prepareCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return prepares
    }

    private func recordPrepare() {
        lock.lock()
        prepares += 1
        lock.unlock()
    }
}

private actor RecordingRollingWhisperKitEngine: WhisperKitRollingWindowEngine, WhisperKitRollingDecodeEngine {
    struct Request: Equatable {
        let window: RollingAudioWindow
        let language: String
        let prompt: String
        let requiresWordTimestamps: Bool
    }

    private let result: String
    private let onPrepare: (@Sendable () -> Void)?
    private var requests: [Request] = []

    init(result: String, onPrepare: (@Sendable () -> Void)? = nil) {
        self.result = result
        self.onPrepare = onPrepare
    }

    func prepare() async throws {
        onPrepare?()
    }

    func stop() async {}

    func transcribe(window: RollingAudioWindow, language: String, prompt: String) async throws -> RollingTranscriptionHypothesis {
        requests.append(Request(window: window, language: language, prompt: prompt, requiresWordTimestamps: false))
        return RollingTranscriptionHypothesis(
            text: result,
            windowStartedAt: window.startedAt,
            windowEndedAt: window.startedAt + window.duration
        )
    }

    func transcribe(request: WhisperKitRollingDecodeRequest) async throws -> RollingTranscriptionHypothesis {
        requests.append(Request(
            window: request.window,
            language: request.language,
            prompt: request.prompt,
            requiresWordTimestamps: request.requiresWordTimestamps
        ))
        return RollingTranscriptionHypothesis(
            text: result,
            windowStartedAt: request.window.startedAt,
            windowEndedAt: request.window.startedAt + request.window.duration
        )
    }

    func receivedRequests() -> [Request] {
        requests
    }
}

private actor BlockingRollingWhisperKitEngine: WhisperKitRollingDecodeEngine {
    private var callCount = 0
    private var activeCount = 0
    private var maximumActiveCount = 0
    private var firstCallContinuation: CheckedContinuation<Void, Never>?
    private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func transcribe(request: WhisperKitRollingDecodeRequest) async throws -> RollingTranscriptionHypothesis {
        callCount += 1
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        let currentCall = callCount
        resumeSatisfiedWaiters()
        if currentCall == 1 {
            await withCheckedContinuation { continuation in
                firstCallContinuation = continuation
            }
        }
        activeCount -= 1
        return RollingTranscriptionHypothesis(
            text: "serialized \(currentCall)",
            windowStartedAt: request.window.startedAt,
            windowEndedAt: request.window.startedAt + request.window.duration
        )
    }

    func waitForCallCount(_ expected: Int) async {
        guard callCount < expected else {
            return
        }
        await withCheckedContinuation { continuation in
            callWaiters.append((expected, continuation))
        }
    }

    func releaseFirstCall() {
        firstCallContinuation?.resume()
        firstCallContinuation = nil
    }

    func recordedCallCount() -> Int {
        callCount
    }

    func recordedMaximumActiveCount() -> Int {
        maximumActiveCount
    }

    private func resumeSatisfiedWaiters() {
        let satisfied = callWaiters.filter { callCount >= $0.0 }
        callWaiters.removeAll { callCount >= $0.0 }
        for waiter in satisfied {
            waiter.1.resume()
        }
    }
}

private struct ThrowingRollingWhisperKitEngine: WhisperKitRollingWindowEngine {
    func transcribe(window: RollingAudioWindow, language: String, prompt: String) async throws -> RollingTranscriptionHypothesis {
        throw TranscriptionFailure(
            code: "test_rolling_runtime_failure",
            message: "Synthetic rolling runtime failure."
        )
    }
}
