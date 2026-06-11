import Foundation
import Meeting007Core
import Meeting007WhisperKit

@main
struct Meeting007WhisperKitChecks {
    static func main() async {
        checkWhisperKitAdapterDefaultsToRussian()
        checkWhisperKitAdapterAcceptsSpeechChunkBoundary()
        await checkWhisperKitAdapterRequiresInstalledModel()
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
