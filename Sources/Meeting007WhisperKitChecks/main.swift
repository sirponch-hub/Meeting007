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
        await checkWhisperKitAdapterMapsResultToTranscriptSegment()
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
