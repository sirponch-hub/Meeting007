import AppKit
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

    private let controller: RecordingSessionController
    private let transcriptPreviewController: LiveTranscriptPreviewController
    private let recordingStore: any RecordingSessionStore
    private let clipboardWriter: any ClipboardWriting
    private let transcriptFileWriter: any TranscriptFileWriting
    private let copyRecentWindowSeconds: TimeInterval = 300
    private var pendingMarkdownExportSession: CompletedRecordingSession?
    private var timer: Timer?
    private var transcriptPreviewTimer: Timer?

    init(
        controller: RecordingSessionController = RecordingSessionController(),
        transcriptPreviewController: LiveTranscriptPreviewController = LiveTranscriptPreviewController(),
        recordingStore: any RecordingSessionStore = InMemoryRecordingSessionStore(),
        clipboardWriter: any ClipboardWriting = PasteboardClipboardWriter(),
        transcriptFileWriter: any TranscriptFileWriting = LocalMarkdownTranscriptFileWriter()
    ) {
        self.controller = controller
        self.transcriptPreviewController = transcriptPreviewController
        self.recordingStore = recordingStore
        self.clipboardWriter = clipboardWriter
        self.transcriptFileWriter = transcriptFileWriter
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
        state = .starting
        elapsedText = "00:00"

        Task {
            let title = displayTitle
            let nextState = await controller.startManualRecording(title: title)
            apply(nextState)

            if nextState.isRecording {
                await startTranscriptPreview()
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
            let frozenSegments = await transcriptPreviewController.visibleSegments()
            await transcriptPreviewController.stop()
            previewSegments = frozenSegments
            let nextState = await controller.stopManualRecording()
            apply(nextState)
            await saveCompletedSessionIfNeeded(state: nextState, segments: frozenSegments)
        }
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

    private func apply(_ nextState: RecordingState) {
        state = nextState

        if case let .failed(failure) = nextState {
            errorMessage = failure.message
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
            markdownExportFeedbackText = "Markdown was not saved. Your transcript preview is still available in this window."
            return completedSession
        }
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

struct RecordingShellView: View {
    @ObservedObject var viewModel: RecordingShellViewModel

    var body: some View {
        HStack(spacing: 0) {
            RecentRecordingsSidebar(
                sessions: viewModel.recentSessions,
                activeTitle: viewModel.displayTitle,
                isRecording: viewModel.state.isRecording,
                onRevealMarkdown: viewModel.revealMarkdownFile,
                onCopyMarkdownPath: viewModel.copyMarkdownPath
            )
                .frame(width: 280)

            Divider()

            VStack(spacing: 0) {
                recordingHeader

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        quickNoteDisclosure
                        errorMessage
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
        .background(Color(nsColor: .windowBackgroundColor))
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
    private var errorMessage: some View {
        if let errorMessage = viewModel.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .font(.callout)
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
            hasStartedPreview: viewModel.hasStartedPreview,
            segments: viewModel.previewSegments,
            canCopyRecentContext: viewModel.canCopyRecentContext,
            copyFeedbackText: viewModel.copyFeedbackText,
            onCopyLastFiveMinutes: viewModel.copyLastFiveMinutes
        )
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
    let hasStartedPreview: Bool
    let segments: [TranscriptSegment]
    let canCopyRecentContext: Bool
    let copyFeedbackText: String?
    let onCopyLastFiveMinutes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("Transcript")
                    .font(.headline)

                Spacer()

                Button {
                    onCopyLastFiveMinutes()
                } label: {
                    Label("Copy Last 5 Minutes", systemImage: "doc.on.doc")
                }
                .disabled(!canCopyRecentContext)
                .help(canCopyRecentContext ? "Copy recent meeting context." : "Transcript lines will appear here before you can copy context.")
                .accessibilityLabel("Copy last five minutes of transcript")
            }

            VStack(alignment: .leading, spacing: 12) {
                if let copyFeedbackText {
                    Text(copyFeedbackText)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }

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
            Text(isRecording ? "Mock Russian segments are shown while live transcription is being wired in. This is not real audio transcription yet." : "This sample transcript was generated for the placeholder experience.")
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
