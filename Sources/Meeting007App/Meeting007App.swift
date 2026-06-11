import AppKit
import AVFoundation
import SwiftUI
import Meeting007Core

@main
struct Meeting007App: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            RecordingShellView(viewModel: RecordingShellViewModel())
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowStyle(.titleBar)
    }
}

@MainActor
final class RecordingShellViewModel: ObservableObject {
    @Published var meetingTitle = ""
    @Published var quickNote = ""
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var elapsedText = "00:00"
    @Published private(set) var errorMessage: String?
    @Published private(set) var previewSegments: [TranscriptSegment] = []
    @Published private(set) var hasStartedPreview = false
    @Published private(set) var recentSessions: [CompletedRecordingSession] = []
    @Published private(set) var copyFeedbackText: String?
    @Published private(set) var markdownExportFeedbackText: String?
    @Published private(set) var transcriptFolderURL: URL
    @Published private(set) var transcriptStorageFeedbackText: String?
    @Published private(set) var microphoneStatus: MicrophoneCaptureStatus = .idle
    @Published private(set) var transcriptionStatusText = "Local transcription ready"
    @Published private(set) var transcriptionModelAvailability: LocalSTTModelAvailability = .missing
    @Published private(set) var transcriptionModelInstallState: LocalSTTModelInstallState = .notInstalled

    private let microphoneStatusModel: MicrophoneCaptureStatusModel
    private let modelManager: any LocalSTTModelManaging
    private let modelInstaller: LocalSTTModelInstaller
    private let controller: RecordingSessionController
    private let transcriptPreviewController: LiveTranscriptPreviewController
    private let sttPipeline: LocalSTTPipeline
    private let recordingStore: any RecordingSessionStore
    private let clipboardWriter: any ClipboardWriting
    private let transcriptFolderSettings: MarkdownTranscriptFolderSettings
    private var transcriptFileWriter: any TranscriptFileWriting
    private let copyRecentWindowSeconds: TimeInterval = 300
    private var pendingMarkdownExportSession: CompletedRecordingSession?
    private var timer: Timer?
    private var transcriptPreviewTimer: Timer?

    init(
        controller: RecordingSessionController? = nil,
        microphoneStatusModel: MicrophoneCaptureStatusModel = MicrophoneCaptureStatusModel(),
        modelManager: (any LocalSTTModelManaging)? = nil,
        modelInstaller: LocalSTTModelInstaller? = nil,
        transcriptPreviewController: LiveTranscriptPreviewController = LiveTranscriptPreviewController(),
        sttPipeline: LocalSTTPipeline? = nil,
        recordingStore: any RecordingSessionStore = InMemoryRecordingSessionStore(),
        clipboardWriter: any ClipboardWriting = PasteboardClipboardWriter(),
        transcriptFolderSettings: MarkdownTranscriptFolderSettings = MarkdownTranscriptFolderSettings(),
        transcriptFileWriter: (any TranscriptFileWriting)? = nil
    ) {
        self.microphoneStatusModel = microphoneStatusModel
        let defaultModelStore = LocalSTTModelStore()
        let resolvedModelManager = modelManager ?? defaultModelStore
        self.modelManager = resolvedModelManager
        self.modelInstaller = modelInstaller ?? LocalSTTModelInstaller(
            downloader: UnconfiguredModelDownloader(),
            store: defaultModelStore
        )
        let effectiveSTTPipeline = sttPipeline ?? LocalSTTPipeline(
            transcriber: FakeRussianSpeechTranscriber()
        )
        self.controller = controller ?? RecordingSessionController(
            captureDriver: MicrophoneRecordingCaptureDriver(
                microphone: AVAudioEngineMicrophoneCaptureDriver(statusModel: microphoneStatusModel),
                consumer: RuntimeOnlyAudioChunkConsumer(speechChunkConsumer: effectiveSTTPipeline)
            )
        )
        self.transcriptPreviewController = transcriptPreviewController
        self.sttPipeline = effectiveSTTPipeline
        self.recordingStore = recordingStore
        self.clipboardWriter = clipboardWriter
        self.transcriptFolderSettings = transcriptFolderSettings
        let folderURL = transcriptFolderSettings.folderURL
        self.transcriptFolderURL = folderURL
        self.transcriptFileWriter = transcriptFileWriter ?? LocalMarkdownTranscriptFileWriter(folderURL: folderURL)
        self.microphoneStatus = microphoneStatusModel.status
        self.microphoneStatusModel.onChange = { [weak self] status in
            self?.microphoneStatus = status
        }
        Task {
            await refreshTranscriptionModelAvailability()
        }
    }

    var statusText: String {
        switch state {
        case .idle:
            return "Ready to record"
        case .starting:
            return "Starting recording..."
        case .recording:
            return "Recording"
        case .stopping:
            return "Stopping recording..."
        case .stopped:
            return "Recording stopped"
        case .failed:
            return "Recording needs attention"
        }
    }

    var canUsePrimaryAction: Bool {
        switch state {
        case .starting, .stopping:
            return false
        case .idle, .recording, .stopped, .failed:
            return true
        }
    }

    var displayTitle: String {
        meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled meeting" : meetingTitle
    }

    var lastCompletedSession: CompletedRecordingSession? {
        recentSessions.first
    }

    var canCopyRecentContext: Bool {
        state.isRecording && !previewSegments.isEmpty
    }

    var canCopyFullTranscript: Bool {
        state.isRecording && previewSegments.contains { $0.state == .final }
    }

    var canOpenMicrophoneSettings: Bool {
        if case let .failed(failure) = state {
            return failure.code == "microphone_permission_denied" || failure.code == "microphone_permission_restricted"
        }

        return false
    }

    func primaryAction() {
        if state.isRecording {
            stop()
        } else {
            start()
        }
    }

    func start() {
        errorMessage = nil
        copyFeedbackText = nil
        markdownExportFeedbackText = nil
        pendingMarkdownExportSession = nil
        microphoneStatus = .requestingPermission
        state = .starting
        elapsedText = "00:00"

        Task {
            let title = displayTitle
            let nextState = await controller.startManualRecording(title: title)
            apply(nextState)

            if nextState.isRecording {
                await startLocalTranscription()
                startTimer()
            }
        }
    }

    func stop() {
        errorMessage = nil
        copyFeedbackText = nil
        markdownExportFeedbackText = nil
        state = .stopping
        stopTimer()
        stopTranscriptPreviewTimer()

        Task {
            let currentSessionID = await controller.currentSession()?.id
            let frozenSegments: [TranscriptSegment]
            if let currentSessionID {
                frozenSegments = await sttPipeline.stop(sessionID: currentSessionID)
            } else {
                frozenSegments = previewSegments
            }
            await transcriptPreviewController.stop()
            previewSegments = frozenSegments
            let nextState = await controller.stopManualRecording()
            apply(nextState)
            if nextState == .stopped {
                microphoneStatusModel.update(.idle)
            }
            await saveCompletedSessionIfNeeded(state: nextState, segments: frozenSegments)
        }
    }

    func openMicrophonePrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func revealMarkdownFile(for session: CompletedRecordingSession) {
        guard let markdownFileURL = session.markdownFileURL else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([markdownFileURL])
    }

    func copyMarkdownPath(for session: CompletedRecordingSession) {
        guard let markdownFileURL = session.markdownFileURL else {
            markdownExportFeedbackText = "Markdown path is not available yet."
            return
        }

        if clipboardWriter.write(markdownFileURL.path) {
            markdownExportFeedbackText = "Markdown path copied."
        } else {
            markdownExportFeedbackText = "Could not copy Markdown path. Try again."
        }
    }

    func chooseTranscriptFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = transcriptFolderURL
        panel.prompt = "Use Folder"
        panel.message = "Choose where Meeting007 saves new Markdown transcripts. Existing files will stay where they are."

        guard panel.runModal() == .OK, let selectedFolderURL = panel.url else {
            return
        }

        applyTranscriptFolder(selectedFolderURL)
    }

    func revealTranscriptFolder() {
        do {
            try MarkdownTranscriptFolderSettings.validateWritableFolder(transcriptFolderURL)
            NSWorkspace.shared.activateFileViewerSelecting([transcriptFolderURL])
        } catch {
            transcriptStorageFeedbackText = "This folder is not available. Choose another folder."
        }
    }

    func copyTranscriptFolderPath() {
        if clipboardWriter.write(transcriptFolderURL.path) {
            transcriptStorageFeedbackText = "Transcript folder path copied."
        } else {
            transcriptStorageFeedbackText = "Could not copy transcript folder path. Try again."
        }
    }

    func resetTranscriptFolderToDefault() {
        transcriptFolderSettings.resetToDefault()
        refreshTranscriptFolderWriter(feedback: "New Markdown transcripts will use the default folder.")
    }

    func refreshTranscriptionModelAvailability() async {
        transcriptionModelAvailability = await modelManager.availability(for: .defaultRussian)
        transcriptionModelInstallState = await modelInstaller.state()
    }

    func prepareTranscriptionModelInstall() {
        Task {
            await modelInstaller.prepareInstall(policy: .defaultRussian)
            transcriptionModelInstallState = await modelInstaller.state()
        }
    }

    func cancelTranscriptionModelInstallConsent() {
        Task {
            await modelInstaller.cancelConsent()
            transcriptionModelInstallState = await modelInstaller.state()
        }
    }

    func confirmTranscriptionModelInstall() {
        Task {
            await modelInstaller.confirmInstall(policy: .defaultRussian)
            await refreshTranscriptionModelAvailability()
        }
    }

    func cancelTranscriptionModelInstall() {
        Task {
            await modelInstaller.cancelInstall()
            await refreshTranscriptionModelAvailability()
        }
    }

    func retryMarkdownExport() {
        guard let pendingMarkdownExportSession else {
            return
        }

        Task {
            let exportedSession = await exportMarkdownIfPossible(for: pendingMarkdownExportSession)
            await recordingStore.save(exportedSession)
            recentSessions = await recordingStore.recentSessions(limit: 8)
        }
    }

    func saveMeetingTitleFromCurrentField() {
        guard state == .stopped,
              let lastCompletedSession,
              meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines) != lastCompletedSession.title,
              let renamedSession = lastCompletedSession.renamed(
                to: meetingTitle,
                markdownFileURL: lastCompletedSession.markdownFileURL
              ) else {
            return
        }

        markdownExportFeedbackText = "Saving title and updating Markdown..."
        Task {
            let exportedSession = await exportMarkdownIfPossible(for: renamedSession)
            await recordingStore.save(exportedSession)
            recentSessions = await recordingStore.recentSessions(limit: 8)
        }
    }

    func copyLastFiveMinutes() {
        guard canCopyRecentContext else {
            copyFeedbackText = "No transcript text to copy yet."
            return
        }

        let transcript = MeetingTranscript(meetingID: previewSegments.first?.meetingID ?? UUID(), segments: previewSegments)
        let latestTranscriptTime = previewSegments.map(\.endTime).max() ?? 0
        let copiedText = transcript.contextTextForLast(
            seconds: copyRecentWindowSeconds,
            from: latestTranscriptTime,
            meetingTitle: displayTitle,
            language: "ru",
            copiedAtText: Date().formatted(date: .omitted, time: .shortened)
        )

        guard !copiedText.isEmpty else {
            copyFeedbackText = "No transcript text to copy yet."
            return
        }

        if clipboardWriter.write(copiedText) {
            copyFeedbackText = "Copied last 5 minutes, including live preview lines."
        } else {
            copyFeedbackText = "Could not copy context. Try again."
        }
    }

    func copyFullTranscript() {
        guard canCopyFullTranscript else {
            copyFeedbackText = "No finalized transcript text to copy yet."
            return
        }

        let transcript = MeetingTranscript(meetingID: previewSegments.first?.meetingID ?? UUID(), segments: previewSegments)
        let copiedText = transcript.contextTextForFullTranscript(
            meetingTitle: displayTitle,
            language: "ru",
            copiedAtText: Date().formatted(date: .omitted, time: .shortened)
        )

        guard !copiedText.isEmpty else {
            copyFeedbackText = "No finalized transcript text to copy yet."
            return
        }

        if clipboardWriter.write(copiedText) {
            copyFeedbackText = "Copied full transcript from finalized lines."
        } else {
            copyFeedbackText = "Could not copy transcript. Try again."
        }
    }

    private func apply(_ nextState: RecordingState) {
        state = nextState

        if case let .failed(failure) = nextState {
            errorMessage = failure.message
            if failure.code == "microphone_permission_denied" || failure.code == "microphone_permission_restricted" {
                microphoneStatusModel.update(.blocked)
            } else if failure.code.hasPrefix("microphone_") {
                microphoneStatusModel.update(.failed(failure.message))
            }
        }

        if case .failed = nextState {
            stopTranscriptPreviewTimer()
        }

        updateElapsed()
    }

    private func startTimer() {
        stopTimer()
        updateElapsed()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsed()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func startTranscriptPreview() async {
        guard let session = await controller.currentSession() else {
            return
        }

        hasStartedPreview = true
        previewSegments = []
        await transcriptPreviewController.start(meetingID: session.id)
        await advanceTranscriptPreview()

        stopTranscriptPreviewTimer()
        transcriptPreviewTimer = Timer.scheduledTimer(withTimeInterval: 1.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.advanceTranscriptPreview()
            }
        }
    }

    private func advanceTranscriptPreview() async {
        previewSegments = await transcriptPreviewController.advance()
    }

    private func startLocalTranscription() async {
        guard let session = await controller.currentSession() else {
            return
        }

        hasStartedPreview = true
        previewSegments = []
        transcriptionStatusText = "Loading Russian speech model..."

        let startResult = await sttPipeline.start(STTSessionConfig(sessionID: session.id))
        guard startResult == .ready else {
            transcriptionStatusText = "Local transcription unavailable"
            if case let .unavailable(failure) = startResult {
                errorMessage = failure.message
            }
            return
        }

        transcriptionStatusText = "Transcribing locally"
        previewSegments = await sttPipeline.visibleSegments()

        stopTranscriptPreviewTimer()
        transcriptPreviewTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      await self.controller.currentSession()?.id != nil else {
                    return
                }

                self.previewSegments = await self.sttPipeline.visibleSegments()
            }
        }
    }

    private func stopTranscriptPreviewTimer() {
        transcriptPreviewTimer?.invalidate()
        transcriptPreviewTimer = nil
    }

    private func saveCompletedSessionIfNeeded(state: RecordingState, segments: [TranscriptSegment]) async {
        guard state == .stopped,
              let session = await controller.currentSession() else {
            return
        }

        let transcript = MeetingTranscript(meetingID: session.id, segments: segments)
        guard let completedSession = CompletedRecordingSession(
            session: session,
            transcript: transcript,
            note: quickNote
        ) else {
            return
        }

        let exportedSession = await exportMarkdownIfPossible(for: completedSession)
        await recordingStore.save(exportedSession)
        recentSessions = await recordingStore.recentSessions(limit: 8)
        meetingTitle = exportedSession.title
    }

    private func exportMarkdownIfPossible(for completedSession: CompletedRecordingSession) async -> CompletedRecordingSession {
        do {
            let result = try await transcriptFileWriter.write(completedSession)
            pendingMarkdownExportSession = nil
            markdownExportFeedbackText = completedSession.markdownFileURL == nil ? "Markdown saved locally." : "Title saved and Markdown updated locally."
            return CompletedRecordingSession(
                session: completedSession.session,
                transcript: completedSession.transcript,
                note: completedSession.note,
                completedAt: completedSession.completedAt,
                isPrototypeOnly: completedSession.isPrototypeOnly,
                markdownFileURL: result.fileURL
            ) ?? completedSession
        } catch {
            pendingMarkdownExportSession = completedSession
            markdownExportFeedbackText = "Markdown was not saved to \(transcriptFolderURL.path). Your transcript preview is still available in this window."
            return completedSession
        }
    }

    private func applyTranscriptFolder(_ folderURL: URL) {
        do {
            try transcriptFolderSettings.setFolderURL(folderURL)
            refreshTranscriptFolderWriter(feedback: "New Markdown transcripts will be saved here.")
        } catch {
            transcriptStorageFeedbackText = "This folder is not writable. Choose another folder."
        }
    }

    private func refreshTranscriptFolderWriter(feedback: String) {
        transcriptFolderURL = transcriptFolderSettings.folderURL
        transcriptFileWriter = LocalMarkdownTranscriptFileWriter(folderURL: transcriptFolderURL)
        transcriptStorageFeedbackText = feedback
    }

    private func updateElapsed() {
        Task {
            await updateElapsedFromController()
        }
    }

    private func updateElapsedFromController() async {
        guard let session = await controller.currentSession(), let startedAt = session.startedAt else {
            elapsedText = "00:00"
            return
        }

        let end = session.endedAt ?? Date()
        elapsedText = TimestampFormatter.format(end.timeIntervalSince(startedAt))
    }
}

protocol ClipboardWriting: Sendable {
    func write(_ text: String) -> Bool
}

struct PasteboardClipboardWriter: ClipboardWriting {
    func write(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }
}

@MainActor
final class MicrophoneCaptureStatusModel: ObservableObject {
    @Published private(set) var status: MicrophoneCaptureStatus = .idle
    var onChange: ((MicrophoneCaptureStatus) -> Void)?

    func update(_ status: MicrophoneCaptureStatus) {
        self.status = status
        onChange?(status)
    }
}

final class AVAudioEngineMicrophoneCaptureDriver: MicrophoneCaptureDriver, @unchecked Sendable {
    private let statusModel: MicrophoneCaptureStatusModel
    private let stateLock = NSLock()
    private var engine: AVAudioEngine?
    private var activeSessionID: UUID?
    private var emittedSampleCount = 0

    init(statusModel: MicrophoneCaptureStatusModel) {
        self.statusModel = statusModel
    }

    func start(session: RecordingSession, consumer: any AudioChunkConsumer) async throws {
        await updateStatus(.requestingPermission)
        let permission = await requestMicrophoneAccess()

        guard permission else {
            await updateStatus(.blocked)
            throw RecordingFailure(
                code: "microphone_permission_denied",
                message: "Microphone access is off. Turn it on in macOS Settings, then start recording again."
            )
        }

        await updateStatus(.starting)

        let nextEngine = AVAudioEngine()
        let inputNode = nextEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            await updateStatus(.unavailable("No microphone signal detected. Check your input device or mute state."))
            throw RecordingFailure(
                code: "microphone_input_unavailable",
                message: "No microphone signal detected. Check your input device or mute state."
            )
        }

        stateLock.withLock {
            emittedSampleCount = 0
        }
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            guard let self else {
                return
            }

            let level = Self.normalizedLevel(from: buffer)
            let normalizedSamples = Self.normalizedSamples(from: buffer)
            let duration = Double(normalizedSamples.frameCount) / normalizedSamples.sampleRate
            let startedAtOffset = self.stateLock.withLock {
                let offset = Double(self.emittedSampleCount) / normalizedSamples.sampleRate
                self.emittedSampleCount += normalizedSamples.frameCount
                return offset
            }
            Task {
                await consumer.receive(CapturedAudioChunk(
                    sessionID: session.id,
                    lane: .mic,
                    startedAt: startedAtOffset,
                    duration: duration,
                    sampleRate: normalizedSamples.sampleRate,
                    channelCount: normalizedSamples.channelCount,
                    byteCount: normalizedSamples.byteCount,
                    samples: normalizedSamples
                ))
                await self.updateStatus(level > 0.03 ? .listening(level: level) : .quiet)
            }
        }

        do {
            try nextEngine.start()
            stateLock.withLock {
                engine = nextEngine
                activeSessionID = session.id
            }
        } catch {
            inputNode.removeTap(onBus: 0)
            nextEngine.stop()
            await updateStatus(.failed("Microphone capture stopped unexpectedly. Your current transcript is still local."))
            throw RecordingFailure(
                code: "microphone_capture_start_failed",
                message: "Microphone capture stopped unexpectedly. Your current transcript is still local."
            )
        }
    }

    func stop(sessionID: UUID) async throws {
        let stopState = stateLock.withLock {
            let shouldStop = activeSessionID == sessionID
            let engineToStop = engine
            engine = nil
            activeSessionID = nil
            emittedSampleCount = 0
            return (shouldStop, engineToStop)
        }

        guard stopState.0 else {
            await updateStatus(.idle)
            return
        }

        stopState.1?.inputNode.removeTap(onBus: 0)
        stopState.1?.stop()
        await updateStatus(.idle)
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    @MainActor
    private func updateStatus(_ status: MicrophoneCaptureStatus) {
        statusModel.update(status)
    }

    private static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else {
            return 0
        }

        let channelCount = max(Int(buffer.format.channelCount), 1)
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                let sample = samples[frame]
                sum += sample * sample
            }
        }

        let meanSquare = sum / Float(frameLength * channelCount)
        let rms = sqrt(meanSquare)
        return min(max(Double(rms) * 12, 0), 1)
    }

    private static func normalizedSamples(from buffer: AVAudioPCMBuffer) -> RuntimeAudioSamples {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else {
            return RuntimeAudioSamples(sampleRate: RuntimeAudioFrameNormalizer.defaultTargetSampleRate, channelCount: 1, samples: [])
        }

        let channelCount = max(Int(buffer.format.channelCount), 1)
        let frameLength = Int(buffer.frameLength)
        var interleavedSamples: [Float] = []
        interleavedSamples.reserveCapacity(frameLength * channelCount)

        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                interleavedSamples.append(channelData[channel][frame])
            }
        }

        return RuntimeAudioFrameNormalizer.normalizedMonoSamples(
            interleavedSamples,
            sourceSampleRate: buffer.format.sampleRate,
            sourceChannelCount: channelCount
        )
    }
}

struct RecordingShellView: View {
    @ObservedObject var viewModel: RecordingShellViewModel
    @State private var selectedSection: ShellSection = .recording

    var body: some View {
        HStack(spacing: 0) {
            RecentRecordingsSidebar(
                sessions: viewModel.recentSessions,
                activeTitle: viewModel.displayTitle,
                isRecording: viewModel.state.isRecording,
                selectedSection: $selectedSection,
                onRevealMarkdown: viewModel.revealMarkdownFile,
                onCopyMarkdownPath: viewModel.copyMarkdownPath
            )
                .frame(width: 280)

            Divider()

            switch selectedSection {
            case .recording:
                recordingContent
            case .settings:
                SettingsView(
                    folderURL: viewModel.transcriptFolderURL,
                    feedbackText: viewModel.transcriptStorageFeedbackText,
                    modelAvailability: viewModel.transcriptionModelAvailability,
                    modelInstallState: viewModel.transcriptionModelInstallState,
                    modelPolicy: .defaultRussian,
                    onChooseFolder: viewModel.chooseTranscriptFolder,
                    onRevealFolder: viewModel.revealTranscriptFolder,
                    onCopyPath: viewModel.copyTranscriptFolderPath,
                    onResetToDefault: viewModel.resetTranscriptFolderToDefault,
                    onRefreshModelStatus: {
                        Task {
                            await viewModel.refreshTranscriptionModelAvailability()
                        }
                    },
                    onPrepareModelInstall: viewModel.prepareTranscriptionModelInstall,
                    onConfirmModelInstall: viewModel.confirmTranscriptionModelInstall,
                    onCancelModelInstallConsent: viewModel.cancelTranscriptionModelInstallConsent,
                    onCancelModelInstall: viewModel.cancelTranscriptionModelInstall
                )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var recordingContent: some View {
        VStack(spacing: 0) {
            recordingHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    quickNoteDisclosure
                    errorMessage(
                        canOpenMicrophoneSettings: viewModel.canOpenMicrophoneSettings,
                        onOpenMicrophoneSettings: viewModel.openMicrophonePrivacySettings
                    )
                    if let lastCompletedSession = viewModel.lastCompletedSession {
                        transcriptPanel
                        CompletedSessionSummary(
                            session: lastCompletedSession,
                            markdownExportFeedbackText: viewModel.markdownExportFeedbackText,
                            onRetryMarkdownExport: viewModel.retryMarkdownExport
                        )
                    } else {
                        transcriptPanel
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
        }
    }

    private var recordingHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            recordingStatePill

            TextField("Meeting title", text: $viewModel.meetingTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
                .accessibilityLabel("Meeting title")
                .onSubmit {
                    viewModel.saveMeetingTitleFromCurrentField()
                }

            Spacer(minLength: 16)

            Text(viewModel.elapsedText)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .trailing)
                .accessibilityLabel("Elapsed recording time \(viewModel.elapsedText)")

            RecordingIconButton(
                isRecording: viewModel.state.isRecording,
                isEnabled: viewModel.canUsePrimaryAction,
                action: viewModel.primaryAction
            )
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var recordingStatePill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(viewModel.state.isRecording ? Color.red : Color.secondary)
                .frame(width: 8, height: 8)
            Text(viewModel.statusText)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }

    private var quickNoteDisclosure: some View {
        DisclosureGroup {
            TextField("Add a quick note for yourself", text: $viewModel.quickNote, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Quick note")
                .padding(.top, 8)
        } label: {
            Label("Quick note", systemImage: "note.text")
                .font(.callout.weight(.semibold))
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func errorMessage(
        canOpenMicrophoneSettings: Bool,
        onOpenMicrophoneSettings: @escaping () -> Void
    ) -> some View {
        if let errorMessage = viewModel.errorMessage {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .font(.callout)
                Spacer()
                if canOpenMicrophoneSettings {
                    Button("Open Privacy Settings", action: onOpenMicrophoneSettings)
                        .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var transcriptPanel: some View {
        TranscriptPanel(
            state: viewModel.state,
            microphoneStatus: viewModel.microphoneStatus,
            transcriptionStatusText: viewModel.transcriptionStatusText,
            hasStartedPreview: viewModel.hasStartedPreview,
            segments: viewModel.previewSegments,
            canCopyRecentContext: viewModel.canCopyRecentContext,
            canCopyFullTranscript: viewModel.canCopyFullTranscript,
            copyFeedbackText: viewModel.copyFeedbackText,
            onCopyLastFiveMinutes: viewModel.copyLastFiveMinutes,
            onCopyFullTranscript: viewModel.copyFullTranscript
        )
    }
}

enum ShellSection: Equatable {
    case recording
    case settings
}

struct SettingsView: View {
    let folderURL: URL
    let feedbackText: String?
    let modelAvailability: LocalSTTModelAvailability
    let modelInstallState: LocalSTTModelInstallState
    let modelPolicy: WhisperModelPolicy
    let onChooseFolder: () -> Void
    let onRevealFolder: () -> Void
    let onCopyPath: () -> Void
    let onResetToDefault: () -> Void
    let onRefreshModelStatus: () -> Void
    let onPrepareModelInstall: () -> Void
    let onConfirmModelInstall: () -> Void
    let onCancelModelInstallConsent: () -> Void
    let onCancelModelInstall: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 26, weight: .semibold))
                    Text("Local storage and app preferences.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Transcript Storage")
                        .font(.headline)

                    TranscriptFolderSettingRow(
                        folderURL: folderURL,
                        feedbackText: feedbackText,
                        onChooseFolder: onChooseFolder,
                        onRevealFolder: onRevealFolder,
                        onCopyPath: onCopyPath,
                        onResetToDefault: onResetToDefault
                    )
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 14) {
                    Text("Transcription")
                        .font(.headline)

                    TranscriptionModelSettingRow(
                        availability: modelAvailability,
                        policy: modelPolicy,
                        installState: modelInstallState,
                        onRefresh: onRefreshModelStatus,
                        onPrepareInstall: onPrepareModelInstall,
                        onConfirmInstall: onConfirmModelInstall,
                        onCancelConsent: onCancelModelInstallConsent,
                        onCancelInstall: onCancelModelInstall
                    )
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
    }
}

struct TranscriptionModelSettingRow: View {
    let availability: LocalSTTModelAvailability
    let policy: WhisperModelPolicy
    let installState: LocalSTTModelInstallState
    let onRefresh: () -> Void
    let onPrepareInstall: () -> Void
    let onConfirmInstall: () -> Void
    let onCancelConsent: () -> Void
    let onCancelInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Russian speech model", systemImage: "waveform.and.magnifyingglass")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(availability.userFacingTitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(statusColor)
            }

            Text("Meeting007 will use the Russian transcription model for local transcription. The model artifact is about \(formattedSize) and stays on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("The model download fetches only the transcription model artifact. Meeting007 does not upload audio, transcripts, meeting titles, participants, or debug content. After the model is installed, Russian transcription works offline on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            installStateContent

            HStack(spacing: 8) {
                Button("Refresh Status", action: onRefresh)
                    .buttonStyle(.bordered)
                primaryAction
            }
        }
        .alert("Install Russian transcription model?", isPresented: consentBinding) {
            Button("Install", action: onConfirmInstall)
            Button("Cancel", role: .cancel, action: onCancelConsent)
        } message: {
            Text("Meeting007 will download about \(formattedSize) to this Mac. The model runs locally, so meeting audio is not uploaded and transcription can work offline after installation.")
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var installStateContent: some View {
        switch installState {
        case .notInstalled, .awaitingConsent:
            Text("Install the Russian model to enable local transcription.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress.fractionCompleted ?? 0)
                    .progressViewStyle(.linear)
                Text(progressText(for: progress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .verifying:
            ProgressView("Verifying local model")
                .font(.caption)
        case .ready:
            Text("Local Russian transcription is ready. Audio stays on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let failure):
            Text(failure.userFacingMessage)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch installState {
        case .notInstalled:
            Button("Install Model", action: onPrepareInstall)
                .buttonStyle(.borderedProminent)
        case .awaitingConsent:
            Button("Install Model", action: onPrepareInstall)
                .buttonStyle(.borderedProminent)
        case .downloading, .verifying:
            Button("Cancel", action: onCancelInstall)
                .buttonStyle(.bordered)
        case .ready:
            Text("Ready")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
        case .failed:
            Button("Retry", action: onPrepareInstall)
                .buttonStyle(.borderedProminent)
        }
    }

    private var consentBinding: Binding<Bool> {
        Binding(
            get: {
                if case .awaitingConsent = installState {
                    return true
                }
                return false
            },
            set: { isPresented in
                if !isPresented {
                    onCancelConsent()
                }
            }
        )
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(policy.approximateSizeInBytes), countStyle: .file)
    }

    private var statusColor: Color {
        switch availability {
        case .ready:
            return .green
        case .missing, .invalid, .downloadFailed:
            return .orange
        case .downloading:
            return .accentColor
        }
    }

    private func progressText(for progress: ModelDownloadProgress) -> String {
        let phaseText: String
        switch progress.phase {
        case .preparing:
            phaseText = "Preparing download"
        case .downloading:
            phaseText = "Downloading Russian model"
        case .verifying:
            phaseText = "Verifying model"
        case .installing:
            phaseText = "Installing model"
        }

        guard let fraction = progress.fractionCompleted else {
            return phaseText
        }

        return "\(phaseText) \(Int((fraction * 100).rounded()))%"
    }
}

struct RecordingIconButton: View {
    let isRecording: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isRecording ? Color.red : Color.accentColor)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .help(isRecording ? "Stop recording" : "Start recording")
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .accessibilityHint(isRecording ? "Stops the current meeting recording." : "Starts a local meeting recording.")
    }
}

struct TranscriptFolderSettingRow: View {
    let folderURL: URL
    let feedbackText: String?
    let onChooseFolder: () -> Void
    let onRevealFolder: () -> Void
    let onCopyPath: () -> Void
    let onResetToDefault: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Transcript folder", systemImage: "folder")
                    .font(.callout.weight(.semibold))
                Spacer()
            }

            Text(folderURL.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
                .accessibilityLabel("Current Markdown transcript folder \(folderURL.path)")

            HStack(spacing: 8) {
                Button {
                    onChooseFolder()
                } label: {
                    Label("Change", systemImage: "folder.badge.gearshape")
                }
                .help("Choose a different folder for new Markdown transcripts.")

                Button {
                    onRevealFolder()
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .help("Show the current transcript folder in Finder.")

                Button {
                    onCopyPath()
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }
                .help("Copy the current transcript folder path.")

                Spacer()

                Button {
                    onResetToDefault()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .help("Use the default Meeting007 transcript folder for new exports.")
            }

            if let feedbackText {
                Text(feedbackText)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text("Changing this folder affects new Markdown exports only. Existing transcript files stay where they are.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct CompletedSessionSummary: View {
    let session: CompletedRecordingSession
    let markdownExportFeedbackText: String?
    let onRetryMarkdownExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session completed")
                        .font(.headline)
                    Text(session.title)
                        .font(.title3.weight(.semibold))
                }

                Spacer()

                Text(TimestampFormatter.format(session.duration))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .accessibilityLabel("Completed recording duration \(TimestampFormatter.format(session.duration))")
            }

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150), alignment: .leading)
            ], alignment: .leading, spacing: 10) {
                CompletedSessionMetric(label: "Started", value: session.startedAt?.formatted(date: .omitted, time: .shortened) ?? "Unknown")
                CompletedSessionMetric(label: "Ended", value: session.endedAt?.formatted(date: .omitted, time: .shortened) ?? "Unknown")
                CompletedSessionMetric(label: "Language", value: session.primaryLanguage.uppercased())
                CompletedSessionMetric(label: "Transcript preview", value: "\(session.finalSegmentCount) final, \(session.partialSegmentCount) live")
            }

            if let stablePreviewText = session.stablePreviewText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest stable line")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(stablePreviewText)
                        .lineLimit(2)
                }
            }

            if !session.note.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(session.note)
                        .lineLimit(2)
                }
            }

            MarkdownExportSummary(
                session: session,
                feedbackText: markdownExportFeedbackText,
                onRetryMarkdownExport: onRetryMarkdownExport
            )
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MarkdownExportSummary: View {
    let session: CompletedRecordingSession
    let feedbackText: String?
    let onRetryMarkdownExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let markdownFileURL = session.markdownFileURL {
                Text(feedbackText ?? "Markdown saved locally.")
                    .font(.callout.weight(.semibold))
                Text("This file was generated from the transcript preview currently shown here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Saved to: \(markdownFileURL.path)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text(feedbackText ?? "Markdown was not saved")
                    .font(.callout.weight(.semibold))
                Text("Your transcript preview is still available in this window. Try saving again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Save Markdown") {
                    onRetryMarkdownExport()
                }
            }
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CompletedSessionMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
        }
        .accessibilityElement(children: .combine)
    }
}

struct RecentRecordingsSidebar: View {
    let sessions: [CompletedRecordingSession]
    let activeTitle: String
    let isRecording: Bool
    @Binding var selectedSection: ShellSection
    let onRevealMarkdown: (CompletedRecordingSession) -> Void
    let onCopyMarkdownPath: (CompletedRecordingSession) -> Void
    @State private var isSessionGroupExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Meeting007")
                    .font(.headline)
                Text("Local transcripts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
                .padding(.horizontal, 14)
                .padding(.top, 18)

            Button {
                selectedSection = .recording
            } label: {
                Label("Current meeting", systemImage: isRecording ? "record.circle.fill" : "waveform")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isRecording ? Color.red : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(selectedSection == .recording ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 8)
            .accessibilityLabel("Current meeting")

            if isRecording {
                ActiveRecordingSidebarRow(title: activeTitle)
                    .padding(.horizontal, 10)
            }

            if sessions.isEmpty {
                Text("Completed sessions will appear here after you stop recording.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            } else {
                DisclosureGroup(isExpanded: $isSessionGroupExpanded) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(sessions) { session in
                            RecentRecordingTreeRow(
                                session: session,
                                onRevealMarkdown: onRevealMarkdown,
                                onCopyMarkdownPath: onCopyMarkdownPath
                            )
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("This app session")
                        .font(.callout.weight(.semibold))
                }
                .padding(.horizontal, 14)
            }

            Spacer()

            Button {
                selectedSection = .settings
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selectedSection == .settings ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 8)
            .accessibilityLabel("Settings")

            Text("Available until the app closes in this prototype slice.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }
}

struct ActiveRecordingSidebarRow: View {
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text("Recording now")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

struct RecentRecordingTreeRow: View {
    let session: CompletedRecordingSession
    let onRevealMarkdown: (CompletedRecordingSession) -> Void
    let onCopyMarkdownPath: (CompletedRecordingSession) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.secondary.opacity(0.55))
                .frame(width: 6, height: 6)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("\(session.endedAt?.formatted(date: .omitted, time: .shortened) ?? "Unknown") - \(session.segmentCount) preview segments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Show in Finder") {
                onRevealMarkdown(session)
            }
            .disabled(session.markdownFileURL == nil)

            Button("Copy path") {
                onCopyMarkdownPath(session)
            }
            .disabled(session.markdownFileURL == nil)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TranscriptPanel: View {
    let state: RecordingState
    let microphoneStatus: MicrophoneCaptureStatus
    let transcriptionStatusText: String
    let hasStartedPreview: Bool
    let segments: [TranscriptSegment]
    let canCopyRecentContext: Bool
    let canCopyFullTranscript: Bool
    let copyFeedbackText: String?
    let onCopyLastFiveMinutes: () -> Void
    let onCopyFullTranscript: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("Transcript")
                    .font(.headline)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        onCopyFullTranscript()
                    } label: {
                        Label("Copy Full Transcript", systemImage: "doc.on.doc.fill")
                    }
                    .disabled(!canCopyFullTranscript)
                    .help(canCopyFullTranscript ? "Copy all finalized transcript text captured so far." : "Final transcript lines will be available after speech stabilizes.")
                    .accessibilityLabel("Copy full transcript")
                    .accessibilityHint("Copies all finalized transcript text captured so far to the clipboard")

                    Button {
                        onCopyLastFiveMinutes()
                    } label: {
                        Label("Copy Last 5 Minutes", systemImage: "doc.on.doc")
                    }
                    .disabled(!canCopyRecentContext)
                    .help(canCopyRecentContext ? "Copy recent meeting context." : "Transcript lines will appear here before you can copy context.")
                    .accessibilityLabel("Copy last five minutes of transcript")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                if let copyFeedbackText {
                    Text(copyFeedbackText)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                MicrophoneLaneIndicator(status: microphoneStatus, isRecording: state.isRecording)
                LocalTranscriptionStatusRow(statusText: transcriptionStatusText, isRecording: state.isRecording)

                if shouldShowPreview {
                    TranscriptPreviewBanner(isRecording: state.isRecording)

                    if segments.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Preview transcript segments will appear here.")
                            Text("Copy becomes available after there is meeting context.")
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(segments) { segment in
                                    TranscriptSegmentRow(segment: segment)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 170, maxHeight: 230)
                    }
                } else {
                    TranscriptEmptyState()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var shouldShowPreview: Bool {
        state.isRecording || hasStartedPreview
    }
}

struct TranscriptEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your transcript will appear here")
                .font(.headline)
            Text("Start recording to see a live transcript preview. Russian transcription is the primary path for v1.")
                .foregroundStyle(.secondary)
        }
    }
}

struct MicrophoneLaneIndicator: View {
    let status: MicrophoneCaptureStatus
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            Text(status.userFacingLabel)
                .font(.callout.weight(.semibold))

            if isRecording {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.14))
                        Capsule()
                            .fill(tint.opacity(0.74))
                            .frame(width: max(8, proxy.size.width * status.level))
                    }
                }
                .frame(width: 72, height: 5)
                .accessibilityHidden(true)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Microphone lane \(status.userFacingLabel)")
    }

    private var iconName: String {
        switch status {
        case .blocked, .unavailable, .failed:
            return "mic.slash.fill"
        case .requestingPermission, .starting:
            return "mic.badge.plus"
        case .listening, .quiet:
            return "mic.fill"
        case .idle:
            return "mic"
        }
    }

    private var tint: Color {
        switch status {
        case .listening:
            return .green
        case .blocked, .unavailable, .failed:
            return .red
        case .requestingPermission, .starting:
            return .accentColor
        case .quiet, .idle:
            return .secondary
        }
    }
}

struct LocalTranscriptionStatusRow: View {
    let statusText: String
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isRecording ? Color.accentColor : Color.secondary)
                .frame(width: 18)
            Text(isRecording ? statusText : "Transcription runs locally on this Mac")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isRecording ? statusText : "Transcription runs locally on this Mac")
    }
}

struct TranscriptPreviewBanner: View {
    let isRecording: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isRecording ? Color.red : Color.secondary)
                    .frame(width: 8, height: 8)
                Text("Preview transcript")
                    .font(.subheadline.weight(.semibold))
            }
            Text(isRecording ? "Local Russian transcription is connected through the STT pipeline. WhisperKit runtime wiring is the next adapter slice." : "This transcript was generated by the local STT pipeline for the current session.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(segment.state == .partial ? Color.accentColor : Color.clear)
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(segment.speakerLabel)
                        .font(.caption.weight(.semibold))
                    Text(segment.state == .partial ? "live" : TimestampFormatter.format(segment.startTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if segment.state == .partial {
                        Text("partial")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.16))
                            .clipShape(Capsule())
                    }
                }

                Text(segment.text)
                    .font(.body)
                    .italic(segment.state == .partial)
                    .foregroundStyle(segment.state == .partial ? .secondary : .primary)
            }
        }
        .padding(10)
        .background(Color(nsColor: segment.state == .partial ? .controlBackgroundColor : .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(segment.speakerLabel), \(segment.state == .partial ? "live partial transcript" : "final transcript"), \(segment.text)")
    }
}
