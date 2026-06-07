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

    private let controller: RecordingSessionController
    private var timer: Timer?

    init(controller: RecordingSessionController = RecordingSessionController()) {
        self.controller = controller
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
                startTimer()
            }
        }
    }

    func stop() {
        errorMessage = nil
        state = .stopping
        stopTimer()

        Task {
            let nextState = await controller.stopManualRecording()
            apply(nextState)
        }
    }

    private func apply(_ nextState: RecordingState) {
        state = nextState

        if case let .failed(failure) = nextState {
            errorMessage = failure.message
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
            transcriptPlaceholder
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

    private var transcriptPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transcript")
                .font(.headline)
            Text(transcriptPlaceholderText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var transcriptPlaceholderText: String {
        switch viewModel.state {
        case .recording, .starting, .stopping:
            return "Recording is active. Transcript preview is not enabled yet."
        case .stopped:
            return "Transcript area ready."
        default:
            return "Transcript will appear here during future transcription-enabled recordings."
        }
    }
}
