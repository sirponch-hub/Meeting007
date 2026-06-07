import Foundation
import Meeting007Core

@main
struct Meeting007CoreChecks {
    static func main() async {
        checkSegmentsAreSortedByStartTime()
        checkUpsertReplacesPartialWithFinalSegment()
        checkCopyLastWindowIncludesOnlyRecentSegments()
        checkTimestampFormatterUsesMinutesAndHours()
        checkMarkdownExportIncludesOnlyFinalSegments()
        await checkManualRecordingStartCreatesSession()
        await checkManualRecordingStopCompletesSession()
        await checkRepeatedStartDoesNotCreateDuplicateSession()
        await checkStopWhileIdleIsSafe()
        await checkStartFailureReturnsStableErrorState()
        await checkDefaultRecordingLanguageIsRussian()
        await checkLiveTranscriptPreviewEmitsRussianSegments()
        await checkLiveTranscriptPreviewReplacesPartialWithFinal()
        await checkLiveTranscriptPreviewStopDisablesFurtherUpdates()
        print("Meeting007CoreChecks passed")
    }

    private static func checkSegmentsAreSortedByStartTime() {
        let meetingID = UUID()
        let first = TranscriptSegment(
            meetingID: meetingID,
            lane: .me,
            state: .final,
            startTime: 0,
            endTime: 2,
            text: "First"
        )
        let second = TranscriptSegment(
            meetingID: meetingID,
            lane: .others,
            state: .final,
            startTime: 10,
            endTime: 12,
            text: "Second"
        )

        let transcript = MeetingTranscript(meetingID: meetingID, segments: [second, first])
        require(transcript.segments.map(\.text) == ["First", "Second"], "Segments must be sorted by start time.")
    }

    private static func checkUpsertReplacesPartialWithFinalSegment() {
        let meetingID = UUID()
        let segmentID = UUID()
        var transcript = MeetingTranscript(meetingID: meetingID)

        transcript.upsert(TranscriptSegment(
            id: segmentID,
            meetingID: meetingID,
            lane: .others,
            state: .partial,
            startTime: 1,
            endTime: 3,
            text: "priv"
        ))
        transcript.upsert(TranscriptSegment(
            id: segmentID,
            meetingID: meetingID,
            lane: .others,
            state: .final,
            startTime: 1,
            endTime: 3,
            text: "Привет"
        ))

        require(transcript.segments.count == 1, "Upsert must replace an existing segment.")
        require(transcript.segments.first?.state == .final, "Replacement segment must be final.")
        require(transcript.segments.first?.text == "Привет", "Replacement segment must keep final text.")
    }

    private static func checkCopyLastWindowIncludesOnlyRecentSegments() {
        let meetingID = UUID()
        let oldSegment = TranscriptSegment(
            meetingID: meetingID,
            lane: .me,
            state: .final,
            startTime: 10,
            endTime: 20,
            text: "Old context"
        )
        let recentSegment = TranscriptSegment(
            meetingID: meetingID,
            lane: .others,
            state: .final,
            startTime: 295,
            endTime: 300,
            text: "Recent context"
        )
        let transcript = MeetingTranscript(meetingID: meetingID, segments: [oldSegment, recentSegment])
        let copiedText = transcript.textForLast(seconds: 300, from: 600)

        require(!copiedText.contains("Old context"), "Old segment must be outside the copy window.")
        require(copiedText.contains("Recent context"), "Recent segment must be included in the copy window.")
        require(copiedText.contains("Others"), "Copy text must include speaker labels.")
    }

    private static func checkTimestampFormatterUsesMinutesAndHours() {
        require(TimestampFormatter.format(65) == "01:05", "Minute timestamp formatting failed.")
        require(TimestampFormatter.format(3661) == "01:01:01", "Hour timestamp formatting failed.")
    }

    private static func checkMarkdownExportIncludesOnlyFinalSegments() {
        let meetingID = UUID()
        let metadata = MeetingMetadata(
            id: meetingID,
            title: "Русская встреча",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 60)
        )
        let transcript = MeetingTranscript(meetingID: meetingID, segments: [
            TranscriptSegment(
                meetingID: meetingID,
                lane: .me,
                state: .final,
                startTime: 0,
                endTime: 3,
                text: "Готово"
            ),
            TranscriptSegment(
                meetingID: meetingID,
                lane: .others,
                state: .partial,
                startTime: 4,
                endTime: 5,
                text: "partial"
            )
        ])

        let markdown = MarkdownTranscriptExporter.export(metadata: metadata, transcript: transcript)

        require(markdown.contains("# Русская встреча"), "Markdown must include the meeting title.")
        require(markdown.contains("primary_language: ru"), "Markdown must include the Russian default language.")
        require(markdown.contains("Me: Готово"), "Markdown must include final transcript text.")
        require(!markdown.contains("partial"), "Markdown export must exclude partial segments.")
    }

    private static func checkManualRecordingStartCreatesSession() async {
        let fixedDate = Date(timeIntervalSince1970: 100)
        let controller = RecordingSessionController(clock: { fixedDate })

        let state = await controller.startManualRecording(title: "Weekly Sync")

        require(state == .recording, "Manual start must enter recording state.")
        let session = await controller.currentSession()
        require(session?.title == "Weekly Sync", "Manual start must keep the meeting title.")
        require(session?.startedAt == fixedDate, "Manual start must set startedAt through the injected clock.")
        require(session?.primaryLanguage == "ru", "Manual recording must default to Russian.")
    }

    private static func checkManualRecordingStopCompletesSession() async {
        var dates = [
            Date(timeIntervalSince1970: 100),
            Date(timeIntervalSince1970: 130)
        ]
        let controller = RecordingSessionController(clock: { dates.removeFirst() })

        _ = await controller.startManualRecording(title: "Stop Test")
        let state = await controller.stopManualRecording()
        let session = await controller.currentSession()

        require(state == .stopped, "Manual stop must enter stopped state.")
        require(session?.endedAt == Date(timeIntervalSince1970: 130), "Manual stop must set endedAt.")
    }

    private static func checkRepeatedStartDoesNotCreateDuplicateSession() async {
        let controller = RecordingSessionController()

        _ = await controller.startManualRecording(title: "First")
        let firstSessionID = await controller.currentSession()?.id
        let state = await controller.startManualRecording(title: "Second")
        let session = await controller.currentSession()

        require(state == .recording, "Repeated start while recording must keep recording state.")
        require(session?.id == firstSessionID, "Repeated start must not create a duplicate session.")
        require(session?.title == "First", "Repeated start must not replace the active session.")
    }

    private static func checkStopWhileIdleIsSafe() async {
        let controller = RecordingSessionController()

        let state = await controller.stopManualRecording()
        let session = await controller.currentSession()

        require(state == .idle, "Stop while idle must keep the controller idle.")
        require(session == nil, "Stop while idle must not create a session.")
    }

    private static func checkStartFailureReturnsStableErrorState() async {
        let controller = RecordingSessionController(
            captureDriver: FailingRecordingCaptureDriver(
                error: RecordingFailure(code: "permission_needed", message: "Microphone access is needed to record meetings.")
            )
        )

        let state = await controller.startManualRecording(title: "Failure")

        require(
            state == .failed(RecordingFailure(code: "permission_needed", message: "Microphone access is needed to record meetings.")),
            "Start failure must expose a stable domain error."
        )
    }

    private static func checkDefaultRecordingLanguageIsRussian() async {
        let controller = RecordingSessionController()

        _ = await controller.startManualRecording(title: "")

        let session = await controller.currentSession()
        require(session?.title == "Untitled meeting", "Empty meeting title must fall back to Untitled meeting.")
        require(session?.primaryLanguage == "ru", "Recording sessions must default to Russian.")
    }

    private static func checkLiveTranscriptPreviewEmitsRussianSegments() async {
        let meetingID = UUID()
        let preview = LiveTranscriptPreviewController()
        await preview.start(meetingID: meetingID)

        _ = await preview.advance()
        _ = await preview.advance()
        let segments = await preview.advance()

        require(segments.count == 2, "Preview should contain two visible segments after partial replacement and one final segment.")
        require(segments.contains { $0.speakerLabel == "Me" }, "Preview must include Me speaker label.")
        require(segments.contains { $0.speakerLabel == "Others" }, "Preview must include Others speaker label.")
        require(segments.contains { $0.text.contains("Давайте начнем") }, "Preview must use Russian sample text.")
        require(segments.map(\.startTime) == segments.map(\.startTime).sorted(), "Preview segments must be sorted by start time.")
    }

    private static func checkLiveTranscriptPreviewReplacesPartialWithFinal() async {
        let meetingID = UUID()
        let preview = LiveTranscriptPreviewController()
        await preview.start(meetingID: meetingID)

        let partialSegments = await preview.advance()
        let finalSegments = await preview.advance()

        require(partialSegments.count == 1, "First preview step should show one partial segment.")
        require(partialSegments.first?.state == .partial, "First preview segment should be partial.")
        require(finalSegments.count == 1, "Final preview step with the same ID should replace, not duplicate, the segment.")
        require(finalSegments.first?.state == .final, "Second preview segment should finalize the same segment.")
        require(partialSegments.first?.id == finalSegments.first?.id, "Partial and final preview updates must reuse the same segment ID.")
    }

    private static func checkLiveTranscriptPreviewStopDisablesFurtherUpdates() async {
        let meetingID = UUID()
        let preview = LiveTranscriptPreviewController()
        await preview.start(meetingID: meetingID)

        let firstSegments = await preview.advance()
        await preview.stop()
        let stoppedSegments = await preview.advance()
        let isActive = await preview.isActive()

        require(!isActive, "Preview should not remain active after stop.")
        require(stoppedSegments == firstSegments, "Preview stop must prevent further fake segment updates.")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("Check failed: \(message)\n", stderr)
            exit(1)
        }
    }
}

private struct FailingRecordingCaptureDriver: RecordingCaptureDriver {
    let error: Error

    func start(session: RecordingSession) async throws {
        throw error
    }

    func stop(sessionID: UUID) async throws {}
}
