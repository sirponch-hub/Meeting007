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
        checkFullTranscriptContextIncludesOnlyFinalSegments()
        checkFullTranscriptContextCanReturnEmptyText()
        checkTimestampFormatterUsesMinutesAndHours()
        checkMarkdownExportIncludesOnlyFinalSegments()
        checkMarkdownFilenameSlugUsesSafeReadableText()
        checkMarkdownFolderSettingsDefaultAndCustomFolder()
        checkMarkdownFolderSettingsResetRestoresDefault()
        await checkLocalMarkdownWriterCreatesFolderAndFile()
        await checkLocalMarkdownWriterUsesDistinctFilenamesForDuplicateTitles()
        await checkManualRecordingStartCreatesSession()
        await checkManualRecordingStopCompletesSession()
        await checkRepeatedStartDoesNotCreateDuplicateSession()
        await checkStopWhileIdleIsSafe()
        await checkStartFailureReturnsStableErrorState()
        await checkRecordingStartStartsMicrophoneLane()
        await checkRecordingStopStopsMicrophoneLane()
        await checkMicrophoneChunksCarrySessionAndLane()
        await checkMicrophoneStartFailureReturnsStableError()
        await checkRuntimeAudioChunksDoNotPersistIntoMarkdown()
        await checkDefaultRecordingLanguageIsRussian()
        await checkLiveTranscriptPreviewEmitsRussianSegments()
        await checkLiveTranscriptPreviewReplacesPartialWithFinal()
        await checkLiveTranscriptPreviewStopDisablesFurtherUpdates()
        checkCompletedSessionRequiresEndedSession()
        await checkStopSavesCompletedSessionToHistory()
        await checkRepeatedStopDoesNotDuplicateSavedSession()
        await checkMultipleCompletedSessionsRemainInHistory()
        checkCompletedSessionRenameKeepsSessionIdentity()
        await checkRenamedCompletedSessionExportsWithNewTitle()
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

    private static func checkFullTranscriptContextIncludesOnlyFinalSegments() {
        let meetingID = UUID()
        let transcript = MeetingTranscript(meetingID: meetingID, segments: [
            TranscriptSegment(
                meetingID: meetingID,
                lane: .others,
                state: .final,
                startTime: 10,
                endTime: 12,
                text: "Старый пункт тоже нужен."
            ),
            TranscriptSegment(
                meetingID: meetingID,
                lane: .me,
                state: .partial,
                startTime: 20,
                endTime: 23,
                text: "Черновик не должен выглядеть как полный транскрипт."
            ),
            TranscriptSegment(
                meetingID: meetingID,
                lane: .me,
                state: .final,
                startTime: 610,
                endTime: 612,
                text: "Новый финальный пункт."
            )
        ])

        let copiedText = transcript.contextTextForFullTranscript(
            meetingTitle: "Русская встреча",
            language: "ru",
            copiedAtText: "14:32"
        )

        require(copiedText.contains("Meeting007"), "Full transcript copy must identify the source app.")
        require(copiedText.contains("Meeting: Русская встреча"), "Full transcript copy must include the meeting title.")
        require(copiedText.contains("Window: Full transcript"), "Full transcript copy must identify the full transcript scope.")
        require(copiedText.contains("Copied: 14:32"), "Full transcript copy must include copied-at text.")
        require(copiedText.contains("Language: ru"), "Full transcript copy must include the language.")
        require(copiedText.contains("[00:10] Others: Старый пункт тоже нужен."), "Full transcript copy must include old final segments.")
        require(copiedText.contains("[10:10] Me: Новый финальный пункт."), "Full transcript copy must include recent final segments.")
        require(!copiedText.contains("Черновик"), "Full transcript copy must exclude partial text until it is finalized.")
        require(!copiedText.contains("(live)"), "Full transcript copy must not present live text as final transcript.")
    }

    private static func checkFullTranscriptContextCanReturnEmptyText() {
        let meetingID = UUID()
        let emptyTranscript = MeetingTranscript(meetingID: meetingID)
        let partialOnlyTranscript = MeetingTranscript(meetingID: meetingID, segments: [
            TranscriptSegment(
                meetingID: meetingID,
                lane: .others,
                state: .partial,
                startTime: 0,
                endTime: 2,
                text: "Пока только черновик."
            )
        ])

        let emptyCopiedText = emptyTranscript.contextTextForFullTranscript(
            meetingTitle: "Empty",
            language: "ru",
            copiedAtText: "14:32"
        )
        let partialOnlyCopiedText = partialOnlyTranscript.contextTextForFullTranscript(
            meetingTitle: "Partial",
            language: "ru",
            copiedAtText: "14:32"
        )

        require(emptyCopiedText.isEmpty, "Full transcript copy should return empty text when no segments are available.")
        require(partialOnlyCopiedText.isEmpty, "Full transcript copy should return empty text when only partial segments are available.")
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
        require(markdown.contains("transcript_source: local_preview"), "Markdown must identify the transcript source.")
        require(markdown.contains("Me: Готово"), "Markdown must include final transcript text.")
        require(!markdown.contains("partial"), "Markdown export must exclude partial segments.")
    }

    private static func checkMarkdownFilenameSlugUsesSafeReadableText() {
        let meetingID = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!
        let metadata = MeetingMetadata(
            id: meetingID,
            title: "Русская встреча / QA",
            startedAt: Date(timeIntervalSince1970: 0)
        )
        let store = MarkdownTranscriptFileStore(folderURL: FileManager.default.temporaryDirectory)

        let filename = store.filename(for: metadata)

        require(filename == "1970-01-01_00-00_russkaya-vstrecha-qa_12345678.md", "Filename must include date, safe title slug, short UUID, and .md extension.")
        require(MarkdownTranscriptFileStore.slug("   ") == "untitled-meeting", "Whitespace title slug must fall back to untitled-meeting.")
    }

    private static func checkMarkdownFolderSettingsDefaultAndCustomFolder() {
        let suiteName = "Meeting007CoreChecks-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            require(false, "Test UserDefaults suite must be available.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let customFolder = temporaryExportFolder()
        let settings = MarkdownTranscriptFolderSettings(defaults: defaults)

        require(settings.usesDefaultFolder, "Markdown folder settings must use default before user selection.")
        require(settings.folderURL == MarkdownTranscriptFolderSettings.defaultFolderURL(), "Default Markdown folder must stay stable.")

        do {
            try settings.setFolderURL(customFolder)
        } catch {
            require(false, "Writable custom Markdown folder must be accepted: \(error)")
        }

        require(!settings.usesDefaultFolder, "Custom Markdown folder selection must be detected.")
        require(settings.folderURL == customFolder, "Markdown folder settings must return the selected folder.")
        require(FileManager.default.fileExists(atPath: customFolder.path), "Markdown folder validation must create the selected folder when needed.")
    }

    private static func checkMarkdownFolderSettingsResetRestoresDefault() {
        let suiteName = "Meeting007CoreChecks-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            require(false, "Test UserDefaults suite must be available.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = MarkdownTranscriptFolderSettings(defaults: defaults)

        do {
            try settings.setFolderURL(temporaryExportFolder())
        } catch {
            require(false, "Writable custom Markdown folder must be accepted before reset: \(error)")
        }

        settings.resetToDefault()

        require(settings.usesDefaultFolder, "Reset must return Markdown folder settings to default mode.")
        require(settings.folderURL == MarkdownTranscriptFolderSettings.defaultFolderURL(), "Reset must restore the default Markdown folder URL.")
    }

    private static func checkLocalMarkdownWriterCreatesFolderAndFile() async {
        let exportFolder = temporaryExportFolder()
        let completedSession = makeCompletedSession(
            id: UUID(uuidString: "aaaaaaaa-1111-2222-3333-444444444444")!,
            title: "Русская встреча",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 90)
        )
        let writer = LocalMarkdownTranscriptFileWriter(folderURL: exportFolder)

        do {
            let result = try await writer.write(completedSession)
            let markdown = try String(contentsOf: result.fileURL, encoding: .utf8)
            let folderContents = try FileManager.default.contentsOfDirectory(at: exportFolder, includingPropertiesForKeys: nil)

            require(FileManager.default.fileExists(atPath: exportFolder.path), "Markdown writer must create the export folder.")
            require(result.fileURL.path.hasPrefix(exportFolder.path), "Markdown writer must honor the injected export folder.")
            require(result.fileURL.pathExtension == "md", "Markdown writer must create a .md file.")
            require(markdown == result.markdown, "Returned markdown must match file contents.")
            require(markdown.contains("# Русская встреча"), "Markdown file must include the meeting title.")
            require(markdown.contains("started_at: 1970-01-01T00:00:00Z"), "Markdown file must include started_at.")
            require(markdown.contains("ended_at: 1970-01-01T00:01:30Z"), "Markdown file must include ended_at.")
            require(markdown.contains("primary_language: ru"), "Markdown file must include Russian language metadata.")
            require(markdown.contains("transcript_source: local_preview"), "Markdown file must include transcript source metadata.")
            require(markdown.contains("Others: Русский сегмент"), "Markdown file must include final transcript segments.")
            require(!markdown.contains("Черновик"), "Markdown file must exclude partial transcript segments.")
            require(!folderContents.contains { $0.lastPathComponent.hasSuffix(".tmp") }, "Markdown writer must not leave temp files after success.")
        } catch {
            require(false, "Markdown writer must save completed sessions without throwing: \(error)")
        }
    }

    private static func checkLocalMarkdownWriterUsesDistinctFilenamesForDuplicateTitles() async {
        let exportFolder = temporaryExportFolder()
        let startedAt = Date(timeIntervalSince1970: 0)
        let first = makeCompletedSession(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Same Title",
            startedAt: startedAt,
            endedAt: Date(timeIntervalSince1970: 60)
        )
        let second = makeCompletedSession(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "Same Title",
            startedAt: startedAt,
            endedAt: Date(timeIntervalSince1970: 120)
        )
        let writer = LocalMarkdownTranscriptFileWriter(folderURL: exportFolder)

        do {
            let firstResult = try await writer.write(first)
            let secondResult = try await writer.write(second)

            require(firstResult.fileURL != secondResult.fileURL, "Duplicate title/start-time sessions must use distinct filenames.")
            require(FileManager.default.fileExists(atPath: firstResult.fileURL.path), "First Markdown file must remain after duplicate-title export.")
            require(FileManager.default.fileExists(atPath: secondResult.fileURL.path), "Second Markdown file must be saved after duplicate-title export.")
        } catch {
            require(false, "Markdown writer must handle duplicate titles without throwing: \(error)")
        }
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

    private static func checkRecordingStartStartsMicrophoneLane() async {
        let microphone = FakeMicrophoneCaptureDriver()
        let controller = RecordingSessionController(
            captureDriver: MicrophoneRecordingCaptureDriver(microphone: microphone)
        )

        let state = await controller.startManualRecording(title: "Mic")
        let session = await controller.currentSession()
        let startedSessionIDs = await microphone.startedSessionIDs()

        require(state == .recording, "Manual start must enter recording after microphone capture starts.")
        require(startedSessionIDs == [session?.id], "Manual start must start exactly one microphone lane for the active session.")
    }

    private static func checkRecordingStopStopsMicrophoneLane() async {
        let microphone = FakeMicrophoneCaptureDriver()
        let consumer = RuntimeOnlyAudioChunkConsumer()
        let controller = RecordingSessionController(
            captureDriver: MicrophoneRecordingCaptureDriver(microphone: microphone, consumer: consumer)
        )

        _ = await controller.startManualRecording(title: "Mic stop")
        guard let session = await controller.currentSession() else {
            require(false, "Mic stop test must have an active session.")
            return
        }

        await microphone.emitTestChunk(sessionID: session.id)
        _ = await controller.stopManualRecording()
        await microphone.emitTestChunk(sessionID: session.id, startedAt: 2)

        let stoppedSessionIDs = await microphone.stoppedSessionIDs()
        let chunks = await consumer.capturedChunks()

        require(stoppedSessionIDs == [session.id], "Manual stop must stop the microphone lane for the same session.")
        require(chunks.isEmpty, "Runtime audio chunks must be cleared and rejected after stop.")
    }

    private static func checkMicrophoneChunksCarrySessionAndLane() async {
        let microphone = FakeMicrophoneCaptureDriver()
        let consumer = RuntimeOnlyAudioChunkConsumer()
        let controller = RecordingSessionController(
            captureDriver: MicrophoneRecordingCaptureDriver(microphone: microphone, consumer: consumer)
        )

        _ = await controller.startManualRecording(title: "Mic chunks")
        guard let session = await controller.currentSession() else {
            require(false, "Mic chunk test must have an active session.")
            return
        }

        await microphone.emitTestChunk(sessionID: session.id, startedAt: 0)
        await microphone.emitTestChunk(sessionID: session.id, startedAt: 0.25)

        let chunks = await consumer.capturedChunks()

        require(chunks.count == 2, "Microphone chunks must reach the in-memory runtime consumer.")
        require(chunks.allSatisfy { $0.sessionID == session.id }, "Microphone chunks must carry the active meeting ID.")
        require(chunks.allSatisfy { $0.lane == .mic }, "Microphone chunks must stay on the mic lane.")
        require(chunks.map(\.startedAt) == chunks.map(\.startedAt).sorted(), "Microphone chunks must keep monotonic timestamps.")
        require(chunks.allSatisfy { $0.duration > 0 }, "Microphone chunks must include nonzero duration.")
        require(chunks.allSatisfy { $0.sampleRate > 0 && $0.channelCount > 0 }, "Microphone chunks must include usable audio format metadata.")
    }

    private static func checkMicrophoneStartFailureReturnsStableError() async {
        let microphone = FakeMicrophoneCaptureDriver(
            startError: RecordingFailure(
                code: "microphone_permission_denied",
                message: "Microphone access is off. Turn it on in macOS Settings, then start recording again."
            )
        )
        let controller = RecordingSessionController(
            captureDriver: MicrophoneRecordingCaptureDriver(microphone: microphone)
        )

        let state = await controller.startManualRecording(title: "Blocked mic")

        require(
            state == .failed(RecordingFailure(
                code: "microphone_permission_denied",
                message: "Microphone access is off. Turn it on in macOS Settings, then start recording again."
            )),
            "Microphone permission failure must surface as a stable recording failure."
        )
    }

    private static func checkRuntimeAudioChunksDoNotPersistIntoMarkdown() async {
        let meetingID = UUID()
        var session = RecordingSession(id: meetingID, title: "Runtime Audio")
        session.markStarted(at: Date(timeIntervalSince1970: 0))
        session.markEnded(at: Date(timeIntervalSince1970: 30))
        let transcript = MeetingTranscript(meetingID: meetingID, segments: [
            TranscriptSegment(
                meetingID: meetingID,
                lane: .me,
                state: .final,
                startTime: 0,
                endTime: 2,
                text: "Проверка без сохранения аудио."
            )
        ])
        guard let completedSession = CompletedRecordingSession(session: session, transcript: transcript) else {
            require(false, "Runtime audio Markdown test must create a completed session.")
            return
        }

        let exportFolder = temporaryExportFolder()
        let writer = LocalMarkdownTranscriptFileWriter(folderURL: exportFolder)

        do {
            let result = try await writer.write(completedSession)
            let folderContents = try FileManager.default.contentsOfDirectory(
                at: exportFolder,
                includingPropertiesForKeys: nil
            )
            let audioExtensions = Set(["wav", "caf", "m4a", "pcm", "aiff", "flac", "mp3"])

            require(folderContents.allSatisfy { !audioExtensions.contains($0.pathExtension.lowercased()) }, "Markdown export must not create raw audio artifacts.")
            require(!result.markdown.contains(".wav"), "Markdown must not reference audio filenames.")
            require(!result.markdown.contains("sampleRate"), "Markdown must not dump audio metadata.")
            require(!result.markdown.contains("byteCount"), "Markdown must not dump audio payload metadata.")
        } catch {
            require(false, "Runtime audio Markdown export must not throw: \(error)")
        }
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

    private static func checkCompletedSessionRenameKeepsSessionIdentity() {
        let completedSession = makeCompletedSession(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            title: "",
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: Date(timeIntervalSince1970: 20)
        )

        guard let renamed = completedSession.renamed(to: "Новая встреча") else {
            require(false, "Completed session rename must create a valid snapshot.")
            return
        }

        require(renamed.id == completedSession.id, "Renaming a completed session must keep the meeting ID.")
        require(renamed.startedAt == completedSession.startedAt, "Renaming a completed session must keep startedAt.")
        require(renamed.endedAt == completedSession.endedAt, "Renaming a completed session must keep endedAt.")
        require(renamed.title == "Новая встреча", "Renaming a completed session must update the title.")
        require(renamed.transcript == completedSession.transcript, "Renaming a completed session must not change transcript text.")
    }

    private static func checkRenamedCompletedSessionExportsWithNewTitle() async {
        let exportFolder = temporaryExportFolder()
        let completedSession = makeCompletedSession(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            title: "",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 60)
        )
        guard let renamed = completedSession.renamed(to: "Новая встреча") else {
            require(false, "Completed session rename must create a valid snapshot for export.")
            return
        }
        let writer = LocalMarkdownTranscriptFileWriter(folderURL: exportFolder)

        do {
            let result = try await writer.write(renamed)
            let markdown = try String(contentsOf: result.fileURL, encoding: .utf8)

            require(result.fileURL.lastPathComponent.contains("novaya-vstrecha"), "Renamed completed session must export with the new title slug.")
            require(markdown.contains("# Новая встреча"), "Renamed completed session Markdown must include the new title.")
        } catch {
            require(false, "Renamed completed session must export without throwing: \(error)")
        }
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

    private static func makeCompletedSession(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        endedAt: Date
    ) -> CompletedRecordingSession {
        var session = RecordingSession(id: id, title: title)
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

    private static func temporaryExportFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Meeting007CoreChecks", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Transcripts", isDirectory: true)
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

private actor FakeMicrophoneCaptureDriver: MicrophoneCaptureDriver {
    private let startError: Error?
    private var starts: [UUID] = []
    private var stops: [UUID] = []
    private var consumer: (any AudioChunkConsumer)?

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func start(session: RecordingSession, consumer: any AudioChunkConsumer) async throws {
        if let startError {
            throw startError
        }

        starts.append(session.id)
        self.consumer = consumer
    }

    func stop(sessionID: UUID) async throws {
        stops.append(sessionID)
        consumer = nil
    }

    func emitTestChunk(sessionID: UUID, startedAt: TimeInterval = 0) async {
        await consumer?.receive(CapturedAudioChunk(
            sessionID: sessionID,
            lane: .mic,
            startedAt: startedAt,
            duration: 0.25,
            sampleRate: 48_000,
            channelCount: 1,
            byteCount: 1_024
        ))
    }

    func startedSessionIDs() -> [UUID] {
        starts
    }

    func stoppedSessionIDs() -> [UUID] {
        stops
    }
}
