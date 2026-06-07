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

    private let controller: RecordingSessionController
    private let transcriptPreviewController: LiveTranscriptPreviewController
    private var timer: Timer?
    private var transcriptPreviewTimer: Timer?

    init(
        controller: RecordingSessionController = RecordingSessionController(),
        transcriptPreviewController: LiveTranscriptPreviewController = LiveTranscriptPreviewController()
    ) {
        self.controller = controller
        self.transcriptPreviewController = transcriptPreviewController
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
            await transcriptPreviewController.stop()
            let nextState = await controller.stopManualRecording()
            apply(nextState)
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
        VStack(alignment: .leading, spacing: 22) {
            header
            meetingFields
            recordingPanel
            TranscriptPanel(
                state: viewModel.state,
                hasStartedPreview: viewModel.hasStartedPreview,
                segments: viewModel.previewSegments
            )
            Spacer(minLength: 0)
        }
        .padding(28)
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
