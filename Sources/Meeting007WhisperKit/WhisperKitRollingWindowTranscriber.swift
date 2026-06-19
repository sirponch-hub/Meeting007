import Foundation
import Meeting007Core
import WhisperKit

public struct WhisperKitRollingWindowConfiguration: Equatable, Sendable {
    public let language: String
    public let modelPolicy: WhisperModelPolicy

    public init(language: String = "ru", modelPolicy: WhisperModelPolicy = .defaultRussian) {
        self.language = language
        self.modelPolicy = modelPolicy
    }
}

public protocol WhisperKitRollingWindowEngine: Sendable {
    func prepare() async throws
    func transcribe(window: RollingAudioWindow, language: String, prompt: String) async throws -> RollingTranscriptionHypothesis
    func stop() async
}

public struct WhisperKitRollingDecodeRequest: Equatable, Sendable {
    public let window: RollingAudioWindow
    public let language: String
    public let prompt: String
    public let requiresWordTimestamps: Bool

    public init(
        window: RollingAudioWindow,
        language: String,
        prompt: String,
        requiresWordTimestamps: Bool
    ) {
        self.window = window
        self.language = language
        self.prompt = prompt
        self.requiresWordTimestamps = requiresWordTimestamps
    }
}

public protocol WhisperKitRollingDecodeEngine: Sendable {
    func prepare() async throws
    func transcribe(request: WhisperKitRollingDecodeRequest) async throws -> RollingTranscriptionHypothesis
    func stop() async
}

public extension WhisperKitRollingWindowEngine {
    func prepare() async throws {}
    func stop() async {}
}

public extension WhisperKitRollingDecodeEngine {
    func prepare() async throws {}
    func stop() async {}
}

public struct LegacyWhisperKitRollingEngineAdapter: WhisperKitRollingDecodeEngine {
    private let engine: any WhisperKitRollingWindowEngine

    public init(engine: any WhisperKitRollingWindowEngine) {
        self.engine = engine
    }

    public func prepare() async throws {
        try await engine.prepare()
    }

    public func transcribe(request: WhisperKitRollingDecodeRequest) async throws -> RollingTranscriptionHypothesis {
        try await engine.transcribe(window: request.window, language: request.language, prompt: request.prompt)
    }

    public func stop() async {
        await engine.stop()
    }
}

public actor WhisperKitRollingWindowTranscriber: RollingWindowTranscribing, RollingTranscriptionLifecycle, TranscriptionFailureReporting {
    private let modelPathProvider: (any LocalSTTModelPathProviding)?
    private let configuration: WhisperKitRollingWindowConfiguration
    private let keepsEngineWarmAfterStop: Bool
    private let fixedEngine: (any WhisperKitRollingDecodeEngine)?
    private let engineFactory: (@Sendable (URL) -> any WhisperKitRollingDecodeEngine)?
    private var activeEngine: (any WhisperKitRollingDecodeEngine)?
    private var runtimeFailure: TranscriptionFailure?
    private var isTranscribing = false
    private var transcriptionWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        modelPathProvider: any LocalSTTModelPathProviding,
        configuration: WhisperKitRollingWindowConfiguration = WhisperKitRollingWindowConfiguration(),
        keepsEngineWarmAfterStop: Bool = false,
        engineFactory: @escaping @Sendable (URL) -> any WhisperKitRollingDecodeEngine = { modelDirectory in
            LocalWhisperKitRollingWindowEngine(modelFolder: modelDirectory.path)
        }
    ) {
        self.modelPathProvider = modelPathProvider
        self.configuration = configuration
        self.keepsEngineWarmAfterStop = keepsEngineWarmAfterStop
        self.fixedEngine = nil
        self.engineFactory = engineFactory
    }

    public init(
        configuration: WhisperKitRollingWindowConfiguration = WhisperKitRollingWindowConfiguration(),
        keepsEngineWarmAfterStop: Bool = false,
        engine: any WhisperKitRollingWindowEngine
    ) {
        self.init(
            configuration: configuration,
            keepsEngineWarmAfterStop: keepsEngineWarmAfterStop,
            decodeEngine: LegacyWhisperKitRollingEngineAdapter(engine: engine)
        )
    }

    public init(
        configuration: WhisperKitRollingWindowConfiguration = WhisperKitRollingWindowConfiguration(),
        keepsEngineWarmAfterStop: Bool = false,
        decodeEngine: any WhisperKitRollingDecodeEngine
    ) {
        self.modelPathProvider = nil
        self.configuration = configuration
        self.keepsEngineWarmAfterStop = keepsEngineWarmAfterStop
        self.fixedEngine = decodeEngine
        self.engineFactory = nil
        self.activeEngine = decodeEngine
    }

    public func prepare() async -> TranscriptionStartResult {
        if activeEngine != nil {
            runtimeFailure = nil
            return .ready
        }

        if let modelPathProvider {
            let directory = await modelPathProvider.verifiedModelDirectory(for: configuration.modelPolicy)
            switch directory {
            case .ready(let modelDirectory):
                guard let engineFactory else {
                    let failure = TranscriptionFailure(
                        code: "local_stt_engine_unavailable",
                        message: "Local rolling transcription could not start."
                    )
                    runtimeFailure = failure
                    return .unavailable(failure)
                }
                let engine = engineFactory(modelDirectory)
                do {
                    try await engine.prepare()
                    activeEngine = engine
                    runtimeFailure = nil
                    return .ready
                } catch {
                    let failure = TranscriptionFailure(
                        code: "local_stt_engine_unavailable",
                        message: "Local rolling transcription could not start."
                    )
                    runtimeFailure = failure
                    return .unavailable(failure)
                }
            case .unavailable(let availability):
                let failure = failure(for: availability)
                runtimeFailure = failure
                return .unavailable(failure)
            }
        }

        do {
            try await fixedEngine?.prepare()
            activeEngine = fixedEngine
            runtimeFailure = nil
            return .ready
        } catch {
            let failure = TranscriptionFailure(
                code: "local_stt_engine_unavailable",
                message: "Local rolling transcription could not start."
            )
            runtimeFailure = failure
            return .unavailable(failure)
        }
    }

    public func transcribe(window: RollingAudioWindow, prompt: String) async throws -> RollingTranscriptionHypothesis {
        await acquireTranscriptionSlot()
        defer { releaseTranscriptionSlot() }

        guard let activeEngine else {
            let failure = TranscriptionFailure(
                code: "local_stt_engine_unavailable",
                message: "Local rolling transcription is not prepared."
            )
            runtimeFailure = failure
            throw failure
        }

        do {
            let hypothesis = try await activeEngine.transcribe(request: WhisperKitRollingDecodeRequest(
                window: window,
                language: configuration.language,
                prompt: prompt,
                requiresWordTimestamps: false
            ))
            runtimeFailure = nil
            return hypothesis
        } catch {
            let failure = TranscriptionFailure(
                code: "local_stt_runtime_failed",
                message: "Local rolling transcription stopped unexpectedly."
            )
            runtimeFailure = failure
            throw failure
        }
    }

    public func stop() async {
        guard !keepsEngineWarmAfterStop else {
            return
        }

        await activeEngine?.stop()
        activeEngine = nil
    }

    public func releaseWarmEngine() async {
        await activeEngine?.stop()
        activeEngine = nil
    }

    public func lastFailure() -> TranscriptionFailure? {
        runtimeFailure
    }

    private func acquireTranscriptionSlot() async {
        if !isTranscribing {
            isTranscribing = true
            return
        }
        await withCheckedContinuation { continuation in
            transcriptionWaiters.append(continuation)
        }
    }

    private func releaseTranscriptionSlot() {
        if transcriptionWaiters.isEmpty {
            isTranscribing = false
        } else {
            transcriptionWaiters.removeFirst().resume()
        }
    }

    private func failure(for availability: LocalSTTModelAvailability) -> TranscriptionFailure {
        switch availability {
        case .ready:
            return TranscriptionFailure(code: "local_stt_engine_unavailable", message: "Local rolling transcription could not start.")
        case .missing:
            return TranscriptionFailure(code: "local_stt_model_missing", message: "The Russian transcription model is not installed on this Mac.")
        case .invalid:
            return TranscriptionFailure(code: "local_stt_model_invalid", message: "The Russian transcription model could not be verified. Download it again.")
        case .downloading:
            return TranscriptionFailure(code: "local_stt_model_downloading", message: "The Russian transcription model is still downloading.")
        case .downloadFailed:
            return TranscriptionFailure(code: "local_stt_model_download_failed", message: "The Russian transcription model download did not finish. Try again.")
        }
    }
}

public actor LocalWhisperKitRollingWindowEngine: WhisperKitRollingDecodeEngine {
    private let modelFolder: String
    private var runtime: WhisperKitRuntimeBox?

    public init(modelFolder: String) {
        self.modelFolder = modelFolder
    }

    public func prepare() async throws {
        runtime = WhisperKitRuntimeBox(whisperKit: try await makeWhisperKit())
    }

    public func transcribe(request: WhisperKitRollingDecodeRequest) async throws -> RollingTranscriptionHypothesis {
        let whisperKit: WhisperKit
        if let runtime {
            whisperKit = runtime.whisperKit
        } else {
            let preparedRuntime = WhisperKitRuntimeBox(whisperKit: try await makeWhisperKit())
            runtime = preparedRuntime
            whisperKit = preparedRuntime.whisperKit
        }

        var options = DecodingOptions(language: request.language, wordTimestamps: request.requiresWordTimestamps)
        let trimmedPrompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty, let tokenizer = whisperKit.tokenizer {
            options.promptTokens = tokenizer.encode(text: " " + trimmedPrompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.usePrefillPrompt = true
        }

        let results = await whisperKit.transcribeWithResults(
            audioArrays: [Array(request.window.samples)],
            decodeOptions: options
        )
        let firstResult = try results.first?.get()
        let text = firstResult?.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return RollingTranscriptionHypothesis(
            text: text,
            windowStartedAt: request.window.startedAt,
            windowEndedAt: request.window.startedAt + request.window.duration
        )
    }

    public func stop() async {
        runtime = nil
    }

    private func makeWhisperKit() async throws -> WhisperKit {
        let config = WhisperKitConfig(
            model: nil,
            modelFolder: modelFolder,
            verbose: false,
            prewarm: false,
            load: true,
            download: false
        )
        return try await WhisperKit(config)
    }
}
