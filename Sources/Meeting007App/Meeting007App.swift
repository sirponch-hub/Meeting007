import SwiftUI
import Meeting007Core

@main
struct Meeting007App: App {
    var body: some Scene {
        WindowGroup {
            RecordingShellView(viewModel: RecordingShellViewModel())
                .frame(minWidth: 760, minHeight: 560)
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

    private let controller: RecordingSessionController
    private let transcriptPreviewController: LiveTranscriptPreviewController
    private let recordingStore: any RecordingSessionStore
    private var timer: Timer?
    private var transcriptPreviewTimer: Timer?

    init(
        controller: RecordingSessionController = RecordingSessionController(),
        transcriptPreviewController: LiveTranscriptPreviewController = LiveTranscriptPreviewController(),
        recordingStore: any RecordingSessionStore = InMemoryRecordingSessionStore()
    ) {
        self.controller = controller
        self.transcriptPreviewController = transcriptPreviewController
        self.recordingStore = recordingStore
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

    var primaryButtonTitle: String {
        state.isRecording ? "Stop Recording" : "Start Recording"
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

    func primaryAction() {
        if state.isRecording {
            stop()
        } else {
            start()
        }
    }

    func start() {
        errorMessage = nil
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

        await recordingStore.save(completedSession)
        recentSessions = await recordingStore.recentSessions(limit: 8)
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

struct RecordingShellView: View {
    @ObservedObject var viewModel: RecordingShellViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                meetingFields
                recordingPanel
                TranscriptPanel(
                    state: viewModel.state,
                    hasStartedPreview: viewModel.hasStartedPreview,
                    segments: viewModel.previewSegments
                )
                if let lastCompletedSession = viewModel.lastCompletedSession {
                    CompletedSessionSummary(session: lastCompletedSession)
                }
                RecentSessionsPanel(sessions: viewModel.recentSessions)
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meeting007")
                    .font(.system(size: 28, weight: .semibold))
                Text("Local-first meeting recording")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.state.isRecording ? Color.red : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(viewModel.statusText)
                    .font(.headline)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var meetingFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Meeting title", text: $viewModel.meetingTitle)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Meeting title")

            TextField("Add a quick note for yourself", text: $viewModel.quickNote, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Quick note")
        }
    }

    private var recordingPanel: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.displayTitle)
                    .font(.title3.weight(.semibold))
                Text("Elapsed recording time: \(viewModel.elapsedText)")
                    .font(.system(.title2, design: .monospaced))
                    .accessibilityLabel("Elapsed recording time \(viewModel.elapsedText)")
            }

            Spacer()

            Button(viewModel.primaryButtonTitle) {
                viewModel.primaryAction()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canUsePrimaryAction)
            .controlSize(.large)
            .accessibilityLabel(viewModel.state.isRecording ? "Stop recording" : "Start recording")
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottomLeading) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.leading, 18)
                    .padding(.bottom, -28)
            }
        }
    }

}

struct CompletedSessionSummary: View {
    let session: CompletedRecordingSession

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

            Text("Saved locally in this app for now. Markdown export and search index are coming in a later slice.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

struct RecentSessionsPanel: View {
    let sessions: [CompletedRecordingSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent recordings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                if sessions.isEmpty {
                    Text("Completed sessions will appear here after you stop recording.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { session in
                        RecentSessionRow(session: session)
                    }

                    Text("Available until the app closes in this prototype slice.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct RecentSessionRow: View {
    let session: CompletedRecordingSession

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.callout.weight(.semibold))
                Text("\(session.endedAt?.formatted(date: .omitted, time: .shortened) ?? "Unknown") - \(session.segmentCount) preview segments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(TimestampFormatter.format(session.duration))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

struct TranscriptPanel: View {
    let state: RecordingState
    let hasStartedPreview: Bool
    let segments: [TranscriptSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transcript")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                if shouldShowPreview {
                    TranscriptPreviewBanner(isRecording: state.isRecording)

                    if segments.isEmpty {
                        Text("Preview transcript segments will appear here.")
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
