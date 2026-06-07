import Foundation
import Meeting007Core

@main
struct Meeting007CoreChecks {
    static func main() async {
        checkSegmentsAreSortedByStartTime()
        checkUpsertReplacesPartialWithFinalSegment()
        checkCopyLastWindowIncludesOnlyRecentSegments()
        checkCopyLastWindowReturnsFormattedSpeakerText()
        checkCopyLastWindowCanReturnEmptyText()
        checkCopyLastWindowContextIncludesHeaderAndLiveMarker()
        checkCopyLastWindowContextCanReturnEmptyText()
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
        checkCompletedSessionRequiresEndedSession()
        await checkStopSavesCompletedSessionToHistory()
        await checkRepeatedStopDoesNotDuplicateSavedSession()
        await checkMultipleCompletedSessionsRemainInHistory()
        await checkStopWhileIdleDoesNotSaveHistoryItem()
        await checkStartAfterStopKeepsPreviousHistory()
        await checkHistoryUsesInMemoryStoreOnly()
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

    private static func checkCopyLastWindowReturnsFormattedSpeakerText() {
        let meetingID = UUID()
        let transcript = MeetingTranscript(meetingID: meetingID, segments: [
            TranscriptSegment(
                meetingID: meetingID,
                lane: .me,
                state: .final,
                startTime: 61,
                endTime: 66,
                text: "Нужно быстро ответить клиенту."
            ),
            TranscriptSegment(
                meetingID: meetingID,
                lane: .others,
                state: .partial,
                startTime: 70,
                endTime: 75,
                text: "Да, пришлите последний контекст..."
            )
        ])

        let copiedText = transcript.textForLast(seconds: 300, from: 90)

        require(copiedText.contains("[01:01] Me: Нужно быстро ответить клиенту."), "Copy text must include timestamps and Me label.")
        require(copiedText.contains("[01:10] Others: Да, пришлите последний контекст..."), "Copy text must include partial text and Others label.")
    }

    private static func checkCopyLastWindowCanReturnEmptyText() {
        let meetingID = UUID()
        let transcript = MeetingTranscript(meetingID: meetingID)

        let copiedText = transcript.textForLast(seconds: 300, from: 600)

        require(copiedText.isEmpty, "Copy text should be empty when no segments are available.")
    }

    private static func checkCopyLastWindowContextIncludesHeaderAndLiveMarker() {
        let meetingID = UUID()
        let transcript = MeetingTranscript(meetingID: meetingID, segments: [
            TranscriptSegment(
                meetingID: meetingID,
                lane: .me,
                state: .final,
                startTime: 12,
                endTime: 16,
                text: "Сформулирую короткий ответ."
            ),
            TranscriptSegment(
                meetingID: meetingID,
                lane: .others,
                state: .partial,
                startTime: 20,
                endTime: 23,
                text: "Добавьте последний риск..."
            )
        ])

        let copiedText = transcript.contextTextForLast(
            seconds: 300,
            from: 30,
            meetingTitle: "Русская встреча",
            language: "ru",
            copiedAtText: "14:32"
        )

        require(copiedText.contains("Meeting007"), "Context copy must identify the source app.")
        require(copiedText.contains("Meeting: Русская встреча"), "Context copy must include the meeting title.")
        require(copiedText.contains("Window: Last 5 minutes"), "Context copy must include the copy window.")
        require(copiedText.contains("Copied: 14:32"), "Context copy must include copied-at text.")
        require(copiedText.contains("Language: ru"), "Context copy must include the language.")
        require(copiedText.contains("[00:12] Me: Сформулирую короткий ответ."), "Context copy must include final speaker lines.")
        require(copiedText.contains("[00:20] Others (live): Добавьте последний риск..."), "Context copy must mark partial lines as live.")
    }

    private static func checkCopyLastWindowContextCanReturnEmptyText() {
        let meetingID = UUID()
        let transcript = MeetingTranscript(meetingID: meetingID)

        let copiedText = transcript.contextTextForLast(
            seconds: 300,
            from: 30,
            meetingTitle: "Empty",
            language: "ru",
            copiedAtText: "14:32"
        )

        require(copiedText.isEmpty, "Context copy should return empty text when no segments are available.")
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

    private static func checkCompletedSessionRequiresEndedSession() {
        var session = RecordingSession(id: UUID(), title: "Incomplete")
        session.markStarted(at: Date(timeIntervalSince1970: 10))
        let transcript = MeetingTranscript(meetingID: session.id)

        let completedSession = CompletedRecordingSession(session: session, transcript: transcript)

        require(completedSession == nil, "Completed session snapshots must require an ended recording session.")
    }

    private static func checkStopSavesCompletedSessionToHistory() async {
        var dates = [
            Date(timeIntervalSince1970: 100),
            Date(timeIntervalSince1970: 145)
        ]
        let controller = RecordingSessionController(clock: { dates.removeFirst() })
        let store = InMemoryRecordingSessionStore()

        _ = await controller.startManualRecording(title: "История встречи")
        let meetingID = await controller.currentSession()?.id
        let state = await controller.stopManualRecording()
        guard let session = await controller.currentSession(), let meetingID else {
            require(false, "Stopped recording must keep the session available for snapshot creation.")
            return
        }

        let transcript = MeetingTranscript(meetingID: meetingID, segments: [
            TranscriptSegment(
                meetingID: meetingID,
                lane: .me,
                state: .final,
                startTime: 2,
                endTime: 6,
                text: "Готово"
            )
        ])
        guard let completedSession = CompletedRecordingSession(
            session: session,
            transcript: transcript,
            note: "Локальная заметка",
            completedAt: Date(timeIntervalSince1970: 150)
        ) else {
            require(false, "Stopped recording must create a completed session snapshot.")
            return
        }

        if state == .stopped {
            await store.save(completedSession)
        }

        let recent = await store.recentSessions(limit: 10)
        require(recent.count == 1, "Stop must save exactly one completed session to in-memory history.")
        require(recent.first?.title == "История встречи", "Completed session history must keep the meeting title.")
        require(recent.first?.duration == 45, "Completed session history must keep the recording duration.")
        require(recent.first?.note == "Локальная заметка", "Completed session history must keep the quick note.")
        require(recent.first?.finalSegmentCount == 1, "Completed session history must keep transcript metadata.")
    }

    private static func checkRepeatedStopDoesNotDuplicateSavedSession() async {
        var session = RecordingSession(id: UUID(), title: "No Duplicate")
        session.markStarted(at: Date(timeIntervalSince1970: 10))
        session.markEnded(at: Date(timeIntervalSince1970: 20))
        let transcript = MeetingTranscript(meetingID: session.id)
        let store = InMemoryRecordingSessionStore()
        guard let firstSnapshot = CompletedRecordingSession(
            session: session,
            transcript: transcript,
            note: "first",
            completedAt: Date(timeIntervalSince1970: 20)
        ), let secondSnapshot = CompletedRecordingSession(
            session: session,
            transcript: transcript,
            note: "second",
            completedAt: Date(timeIntervalSince1970: 25)
        ) else {
            require(false, "Ended sessions must create snapshots for duplicate-save checks.")
            return
        }

        await store.save(firstSnapshot)
        await store.save(secondSnapshot)

        let recent = await store.recentSessions(limit: 10)
        require(recent.count == 1, "Saving the same completed session twice must replace instead of duplicating.")
        require(recent.first?.note == "second", "Duplicate save must keep the latest snapshot.")
    }

    private static func checkMultipleCompletedSessionsRemainInHistory() async {
        let store = InMemoryRecordingSessionStore()
        let older = makeCompletedSession(
            title: "Older",
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: Date(timeIntervalSince1970: 20)
        )
        let newer = makeCompletedSession(
            title: "Newer",
            startedAt: Date(timeIntervalSince1970: 30),
            endedAt: Date(timeIntervalSince1970: 50)
        )

        await store.save(older)
        await store.save(newer)

        let recent = await store.recentSessions(limit: 10)
        require(recent.map(\.title) == ["Newer", "Older"], "Completed session history must keep all sessions newest first.")

        let limited = await store.recentSessions(limit: 1)
        require(limited.map(\.title) == ["Newer"], "Completed session history must respect the requested limit.")
    }

    private static func checkStopWhileIdleDoesNotSaveHistoryItem() async {
        let controller = RecordingSessionController()
        let store = InMemoryRecordingSessionStore()

        let state = await controller.stopManualRecording()
        if state == .stopped, let session = await controller.currentSession() {
            let transcript = MeetingTranscript(meetingID: session.id)
            if let completedSession = CompletedRecordingSession(session: session, transcript: transcript) {
                await store.save(completedSession)
            }
        }

        let recent = await store.recentSessions(limit: 10)
        require(recent.isEmpty, "Stop while idle must not save a completed session.")
    }

    private static func checkStartAfterStopKeepsPreviousHistory() async {
        var dates = [
            Date(timeIntervalSince1970: 100),
            Date(timeIntervalSince1970: 120),
            Date(timeIntervalSince1970: 200)
        ]
        let controller = RecordingSessionController(clock: { dates.removeFirst() })
        let store = InMemoryRecordingSessionStore()

        _ = await controller.startManualRecording(title: "First")
        _ = await controller.stopManualRecording()
        guard let firstSession = await controller.currentSession(),
              let firstCompleted = CompletedRecordingSession(
                session: firstSession,
                transcript: MeetingTranscript(meetingID: firstSession.id)
              ) else {
            require(false, "First stopped recording must create a completed snapshot.")
            return
        }
        await store.save(firstCompleted)

        _ = await controller.startManualRecording(title: "Second")

        let recent = await store.recentSessions(limit: 10)
        let activeSession = await controller.currentSession()
        require(recent.map(\.title) == ["First"], "Starting a new recording must not erase completed history.")
        require(activeSession?.title == "Second", "Second recording must become the active session.")
    }

    private static func checkHistoryUsesInMemoryStoreOnly() async {
        let store = InMemoryRecordingSessionStore()
        let completedSession = makeCompletedSession(
            title: "Runtime Only",
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: Date(timeIntervalSince1970: 40)
        )

        await store.save(completedSession)

        let saved = await store.session(id: completedSession.id)
        let emptyFreshStore = await InMemoryRecordingSessionStore().recentSessions(limit: 10)

        require(saved?.title == "Runtime Only", "In-memory store must return saved sessions during the app run.")
        require(emptyFreshStore.isEmpty, "A fresh in-memory store must not contain prior sessions.")
    }

    private static func makeCompletedSession(title: String, startedAt: Date, endedAt: Date) -> CompletedRecordingSession {
        var session = RecordingSession(id: UUID(), title: title)
        session.markStarted(at: startedAt)
        session.markEnded(at: endedAt)
        let transcript = MeetingTranscript(meetingID: session.id, segments: [
            TranscriptSegment(
                meetingID: session.id,
                lane: .others,
                state: .final,
                startTime: 1,
                endTime: 2,
                text: "Русский сегмент"
            ),
            TranscriptSegment(
                meetingID: session.id,
                lane: .me,
                state: .partial,
                startTime: 3,
                endTime: 4,
                text: "Черновик"
            )
        ])

        guard let completedSession = CompletedRecordingSession(
            session: session,
            transcript: transcript,
            completedAt: endedAt
        ) else {
            fatalError("Test fixture must create a valid completed session.")
        }

        return completedSession
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
