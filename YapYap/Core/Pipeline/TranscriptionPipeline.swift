// TranscriptionPipeline.swift
// YapYap — Orchestrates audio → STT → cleanup → paste
import SwiftData
import AppKit
import AVFoundation
import Foundation

@Observable
class TranscriptionPipeline {
    let appState: AppState
    let audioCapture: AudioCaptureManager
    let pasteManager: PasteManager

    let executor = TranscriptionExecutor()
    private let container: ModelContainer
    private var isCommandMode: Bool = false

    /// Word count threshold: transcriptions this short skip LLM and just get regex cleanup
    private let fastPathWordThreshold = 20

    /// Common filler words that indicate the text would benefit from LLM cleanup
    private static let fillerWords: Set<String> = [
        "um", "uh", "uh,", "um,", "like", "basically", "you know",
        "actually", "literally", "i mean", "sort of", "kind of"
    ]

    /// Cached managers to avoid per-transcription disk I/O
    private let snippetManager = SnippetManager()
    private let personalDict = PersonalDictionary.shared

    /// Keep-alive timer: periodic warmup to prevent OS from evicting model weights.
    /// 15 minutes strikes a balance — macOS can evict memory-mapped pages well before
    /// the previous 30-minute interval under memory pressure, causing cold-start stalls.
    private var keepAliveTimer: Timer?
    private static let keepAliveInterval: TimeInterval = 900 // 15 minutes

    /// Pre-computed context: captured at recording start so it's ready when STT finishes
    private var cachedStyleSettings: StyleSettings?
    private var cachedAppContext: AppContext?

    /// Target app for paste: captured at recording start when the user's app is frontmost.
    /// This prevents pasting into YapYap itself if processing takes a long time.
    private var targetApp: NSRunningApplication?

    /// Whether media was paused by us and should be resumed
    private var didPauseMedia = false

    /// Reentrancy guard: prevents concurrent startRecording calls (e.g. from key auto-repeat
    /// while model loading is blocking). Set true at entry, false when recording is running.
    private var isStartingRecording = false

    /// Deferred stop: set when stopRecordingAndProcess() is called while startRecording()
    /// is still in-flight (model loading). startRecording() checks this after model load
    /// and aborts instead of starting capture.
    var pendingStop = false

    init(appState: AppState, container: ModelContainer) {
        self.appState = appState
        self.container = container
        self.audioCapture = AudioCaptureManager()
        self.pasteManager = PasteManager()
    }

    // MARK: - Model Loading

    func loadModelsAtStartup() async throws {
        appState.isLoadingModels = true
        appState.modelsReady = false

        // Pre-warm audio engine so first recording starts instantly
        audioCapture.warmUp()

        do {
            try await ensureModelsLoaded()
            // Immediately warm up engines to page model weights into memory.
            // Without this, the first real inference suffers a 10-13s cold-start
            // penalty as weights are paged from disk.
            await executor.warmupEngines()
            appState.modelsReady = true
            appState.modelLoadingStatus = "Ready to transcribe"
            NSLog("[TranscriptionPipeline] ✅ Models loaded and warmed up at startup")
        } catch {
            appState.modelLoadingStatus = "Model loading failed"
            NSLog("[TranscriptionPipeline] ❌ Model loading failed at startup: \(error)")
            // Always clear loading state, even on failure — otherwise
            // the UI stays stuck showing the loading indicator forever
            appState.isLoadingModels = false
            throw error
        }

        appState.isLoadingModels = false
    }

    // MARK: - Keep-Alive

    /// Start periodic warmup to keep model weights resident in memory.
    /// macOS will evict memory-mapped weights after extended idle, causing
    /// 8-9s cold-start penalty. A tiny inference every 30 min prevents this.
    func startKeepAliveTimer() {
        stopKeepAliveTimer()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: Self.keepAliveInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task {
                NSLog("[TranscriptionPipeline] Keep-alive: warming up models")
                await self.executor.warmupEngines()
                NSLog("[TranscriptionPipeline] Keep-alive: warmup complete")
            }
        }
        NSLog("[TranscriptionPipeline] Keep-alive timer started (interval: \(Self.keepAliveInterval)s)")
    }

    func stopKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

    func ensureModelsLoaded() async throws {
        let settings = try fetchSettings()

        // Only signal loading state when the LLM actually needs to load (not already active).
        // Setting llmLoadingModelId on every hotkey press would cause a "Loading..." flash
        // in the popover even when the model is already warm in memory.
        let llmAlreadyLoaded = await executor.activeLLMModelId == settings.llmModelId
        if !llmAlreadyLoaded {
            await MainActor.run { [weak self] in
                self?.appState.llmLoadingModelId = settings.llmModelId
                self?.appState.llmDownloadProgress = 0.0
            }
        }

        try await executor.ensureModelsLoaded(
            sttModelId: settings.sttModelId,
            llmModelId: settings.llmModelId,
            onSTTProgress: { [weak self] progress in
                Task { @MainActor in self?.appState.modelLoadingProgress = progress * 0.5 }
            },
            onLLMProgress: { [weak self] progress in
                Task { @MainActor in
                    self?.appState.modelLoadingProgress = 0.5 + progress * 0.5
                    self?.appState.llmDownloadProgress = progress
                }
            },
            onStatus: { [weak self] status in
                await MainActor.run { self?.appState.modelLoadingStatus = status }
            }
        )
        let activeLLM = await executor.activeLLMModelId
        let activeSTT = await executor.sttModelId
        await MainActor.run { [weak self] in
            self?.appState.activeLLMModelId = activeLLM
            self?.appState.activeSTTModelId = activeSTT
            // Clear LLM loading state — load is complete (success or failure)
            self?.appState.llmLoadingModelId = nil
            self?.appState.llmDownloadProgress = nil
            self?.appState.modelLoadingProgress = 1.0
            NotificationCenter.default.post(name: .yapSettingsChanged, object: nil)
        }
    }

    // MARK: - Recording

    func startRecording(isCommandMode: Bool = false) async throws {
        NSLog("[TranscriptionPipeline] startRecording() called, isCommandMode: \(isCommandMode)")

        // Reentrancy guard: reject concurrent calls (key auto-repeat during model load)
        guard !isStartingRecording else {
            NSLog("[TranscriptionPipeline] ⚠️ startRecording() already in-flight, ignoring duplicate call")
            return
        }
        isStartingRecording = true
        pendingStop = false
        defer { isStartingRecording = false }

        // CHECK MICROPHONE PERMISSION FIRST - gives instant feedback if denied
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        NSLog("[TranscriptionPipeline] Microphone permission check: status=\(micStatus.rawValue), bundleId=\(bundleId)")

        guard micStatus == .authorized else {
            NSLog("[TranscriptionPipeline] ❌ Microphone permission denied (status=\(micStatus.rawValue))")
            throw YapYapError.microphonePermissionDenied
        }

        NSLog("[TranscriptionPipeline] ✅ Microphone permission granted")

        // Always call ensureModelsLoaded — it's a no-op if the right models are already
        // loaded, but it detects model ID changes from Settings and reloads as needed.
        // Show loading UI if models aren't ready or if the model ID changed.
        let settings = try fetchSettings()
        let sttChanged = await executor.sttModelId != settings.sttModelId
        let llmChanged = await executor.llmModelId != settings.llmModelId
        if !appState.modelsReady || sttChanged || llmChanged {
            let what = sttChanged ? "speech model" : llmChanged ? "language model" : "models"
            NSLog("[TranscriptionPipeline] ⚠️ Loading \(what)...")
            appState.isLoadingModels = true
            appState.modelLoadingStatus = "Loading \(what)..."
        }
        try await ensureModelsLoaded()
        appState.modelsReady = true
        appState.isLoadingModels = false

        // Check if user released the hotkey while we were loading models.
        // If so, abort — don't start recording when the user already let go.
        if pendingStop {
            NSLog("[TranscriptionPipeline] ⚠️ Hotkey released during model load, aborting recording")
            pendingStop = false
            appState.creatureState = .sleeping
            return
        }

        NSLog("[TranscriptionPipeline] ✅ Models ready, starting capture")

        self.isCommandMode = isCommandMode
        appState.creatureState = .recording
        appState.isRecording = true
        NSLog("[TranscriptionPipeline] Recording state set to true, creature: \(appState.creatureState)")
        print("[TranscriptionPipeline] Recording state set to true")

        SoundManager.shared.playStart()
        HapticManager.shared.tap()

        // Pre-compute app context now — the user's app is frontmost during recording.
        // This saves ~30ms off the critical path after STT and provides cached values
        // for future speculative LLM prefill.
        let styleSettings = StyleSettings.loadFromUserDefaults()
        let appContext = AppContextDetector.detect(settings: styleSettings)
        self.cachedStyleSettings = styleSettings
        self.cachedAppContext = appContext
        self.targetApp = NSWorkspace.shared.frontmostApplication
        NSLog("[TranscriptionPipeline] Pre-cached context: \(appContext.appName) (\(appContext.category.rawValue)), target app pid: \(self.targetApp?.processIdentifier ?? -1)")

        // Auto-pause media playback if enabled
        if settings.pauseMediaDuringRecording {
            didPauseMedia = true
            MediaPlaybackController.shared.pauseIfPlaying()
        }

        // Pass selected microphone from settings
        let micId = settings.microphoneId
        try await audioCapture.startCapture(microphoneId: micId) { [weak self] rms in
            DispatchQueue.main.async {
                self?.appState.currentRMS = rms
            }
        }
        print("[TranscriptionPipeline] Audio capture started")

        // Wire up audio engine failure recovery
        audioCapture.onEngineFailure = { [weak self] in
            Task {
                do {
                    try await self?.audioCapture.recreateEngine()
                    NSLog("[TranscriptionPipeline] Audio engine recovered")
                } catch {
                    NSLog("[TranscriptionPipeline] Audio engine recovery failed: \(error)")
                }
            }
        }

        // Monitor for device changes (mic plugged/unplugged)
        audioCapture.onDeviceChanged = { [weak self] in
            NSLog("[TranscriptionPipeline] Audio device changed during recording")
            Task {
                do {
                    try await self?.audioCapture.recreateEngine()
                    NSLog("[TranscriptionPipeline] Reconnected to new audio device")
                } catch {
                    NSLog("[TranscriptionPipeline] Failed to reconnect: \(error)")
                }
            }
        }
        audioCapture.startDeviceChangeMonitoring()

        // Start streaming STT if the engine supports it
        let isStreaming = await executor.isStreaming
        if !isStreaming {
            let hasStreamingSupport = await executor.streamingEngine != nil
            if hasStreamingSupport {
                try await executor.startStreaming(
                    audioSamplesProvider: { [weak self] in
                        self?.audioCapture.currentAudioSamples() ?? []
                    },
                    language: settings.language,
                    onUpdate: { [weak self] update in
                        Task { @MainActor in
                            self?.appState.partialTranscription = update.currentText.isEmpty ? nil : update.currentText
                        }
                    }
                )
                NSLog("[TranscriptionPipeline] Streaming STT started")
            }
        }
    }

    func stopRecordingAndProcess() async throws -> String {
        let pipelineStart = Date()
        NSLog("[TranscriptionPipeline] stopRecordingAndProcess() called")

        appState.isRecording = false
        appState.creatureState = .processing
        appState.isProcessing = true

        SoundManager.shared.playStop()
        HapticManager.shared.tap()

        do {
            var rawText: String
            var audioDuration: Double
            var detectedLanguage: String
            var stageStart = Date()
            let settings = try fetchSettings()

            // Stop streaming if active (cleans up polling task), then always
            // use batch transcription on the full audio buffer for accuracy.
            let isCurrentlyStreaming = await executor.isStreaming
            if isCurrentlyStreaming {
                _ = try? await executor.stopStreaming()
                NSLog("[TranscriptionPipeline] Streaming stopped, using batch for final result")
            }

            // Batch path: stop capture, then run STT on full buffer
            guard let audioBuffer = audioCapture.stopCapture() else {
                NSLog("[TranscriptionPipeline] ❌ No audio buffer captured (too short or empty)")
                appState.creatureState = .sleeping
                appState.isProcessing = false
                throw YapYapError.noAudioRecorded
            }
            audioDuration = Double(audioBuffer.frameLength) / audioCapture.sampleRate
            NSLog("[TranscriptionPipeline] ✅ Audio buffer: \(audioBuffer.frameLength) frames (\(String(format: "%.1f", audioDuration))s)")

            let transcription = try await executor.transcribe(audioBuffer: audioBuffer, language: settings.language)
            rawText = Self.stripWhisperArtifacts(transcription.text.trimmingCharacters(in: .whitespacesAndNewlines))
            rawText = OutputFormatter.applyMetaCommandStripping(rawText)
            detectedLanguage = transcription.language ?? settings.language
            NSLog("[TranscriptionPipeline] STT (batch): \"\(rawText)\" (\(String(format: "%.0f", Date().timeIntervalSince(stageStart) * 1000))ms)")

            guard !rawText.isEmpty else {
                NSLog("[TranscriptionPipeline] ❌ Empty transcription")
                appState.creatureState = .sleeping
                appState.isProcessing = false
                appState.partialTranscription = nil
                throw YapYapError.noAudioRecorded
            }

            // Show raw STT output immediately as type-ahead preview.
            // User sees their words while LLM cleanup runs in the background.
            appState.partialTranscription = rawText

            // Check for command mode
            if isCommandMode || CommandMode.isCommand(rawText) {
                return try await handleCommandMode(rawText: rawText, settings: settings)
            }

            // Check for snippet trigger
            if let snippet = snippetManager.matchSnippet(from: rawText) {
                return try await handleSnippet(snippet: snippet, settings: settings)
            }

            // Use pre-computed context from startRecording() (saves ~30ms).
            // Fall back to fresh detection if cache is empty (shouldn't happen).
            stageStart = Date()
            let styleSettings = cachedStyleSettings ?? StyleSettings.loadFromUserDefaults()
            let appContext = cachedAppContext ?? AppContextDetector.detect(settings: styleSettings)

            // Apply personal dictionary corrections (pass app name for per-app entries)
            let correctedText = personalDict.applyCorrections(to: rawText, activeAppName: appContext.appName)
            cachedStyleSettings = nil
            cachedAppContext = nil
            NSLog("[TranscriptionPipeline] Context: \(appContext.appName) (\(appContext.category.rawValue)) (\(String(format: "%.0f", Date().timeIntervalSince(stageStart) * 1000))ms, cached)")

            let wordCount = correctedText.split(separator: " ").count
            var cleanedText: String

            // FAST PATH: Short transcriptions skip LLM entirely — just regex cleanup.
            // This saves 500-1500ms for quick phrases like "hello" or "sounds good".
            // Exception: if fillers are detected, route through LLM even if short.
            let hasFillers = Self.containsFillers(correctedText)
            if wordCount <= fastPathWordThreshold && !hasFillers {
                NSLog("[TranscriptionPipeline] Fast path: \(wordCount) words, no fillers, skipping LLM")
                cleanedText = correctedText
                // Apply basic capitalization fix
                if let first = cleanedText.first, first.isLowercase {
                    cleanedText = first.uppercased() + cleanedText.dropFirst()
                }
            } else {
                // LLM cleanup for longer text
                stageStart = Date()
                let context = CleanupContext(
                    stylePrompt: settings.stylePrompt,
                    formality: CleanupContext.Formality(rawValue: settings.formality) ?? .neutral,
                    language: settings.language,
                    appContext: appContext,
                    cleanupLevel: CleanupContext.CleanupLevel(rawValue: settings.cleanupLevel) ?? .medium,
                    removeFillers: true,
                    experimentalPrompts: settings.experimentalPrompts
                )

                let isLLMLoaded = await executor.isLLMLoaded
                if isLLMLoaded {
                    cleanedText = try await executor.cleanup(rawText: correctedText, context: context)
                    NSLog("[TranscriptionPipeline] LLM: \"\(cleanedText)\" (\(String(format: "%.0f", Date().timeIntervalSince(stageStart) * 1000))ms)")
                } else {
                    NSLog("[TranscriptionPipeline] ⚠️ LLM not loaded, using raw STT output")
                    cleanedText = correctedText
                    if let first = cleanedText.first, first.isLowercase {
                        cleanedText = first.uppercased() + cleanedText.dropFirst()
                    }
                }

                // Strip example echo: small models sometimes echo few-shot examples before the actual output
                cleanedText = Self.stripExampleEcho(output: cleanedText, input: correctedText)

                // Validate: LLM output must share significant content with input.
                // If the model went off-script (chatbot response, refusal, code), fall back.
                let trimmedOutput = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedOutput.isEmpty || !Self.isValidCleanup(input: correctedText, output: trimmedOutput) {
                    NSLog("[TranscriptionPipeline] ⚠️ LLM output invalid, falling back to raw text")
                    cleanedText = correctedText
                    if let first = cleanedText.first, first.isLowercase {
                        cleanedText = first.uppercased() + cleanedText.dropFirst()
                    }
                }
            }

            // Post-processing: output formatting + filler filter
            cleanedText = OutputFormatter.format(cleanedText, for: appContext, styleSettings: styleSettings)
            cleanedText = FillerFilter.removeFillers(from: cleanedText, aggressive: settings.cleanupLevel == "heavy")

            // Paste and/or copy
            if settings.autoPaste {
                pasteManager.paste(cleanedText, targetApp: self.targetApp)
            }
            if settings.copyToClipboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cleanedText, forType: .string)
            }

            // Update state immediately — text is already pasted
            appState.creatureState = .sleeping
            appState.isProcessing = false
            appState.partialTranscription = nil
            appState.lastTranscription = cleanedText
            appState.lastRawTranscription = rawText

            // Auto-learn corrections: poll the focused text field for user edits to our paste
            if settings.autoPaste {
                personalDict.monitorAndLearn(pastedText: cleanedText, appName: appContext.appName)
            }

            // Move history save + analytics off the critical path.
            // Text is already pasted, no need to block on disk I/O.
            let finalWordCount = cleanedText.split(separator: " ").count
            let sttModelId = await executor.sttModelId ?? "unknown"
            let llmModelId = await executor.llmModelId ?? "unknown"
            let sourceApp = appContext.appName
            let container = self.container
            Task.detached { [weak self] in
                do {
                    let context = ModelContext(container)
                    let entry = Transcription(
                        rawText: rawText,
                        cleanedText: cleanedText,
                        durationSeconds: audioDuration,
                        wordCount: finalWordCount,
                        sttModel: sttModelId,
                        llmModel: llmModelId,
                        sourceApp: sourceApp,
                        language: detectedLanguage
                    )
                    context.insert(entry)
                    try context.save()
                } catch {
                    NSLog("[TranscriptionPipeline] ⚠️ Failed to save transcription history: \(error)")
                }
                // Use audio duration (speaking time) as the "time saved" metric,
                // since it represents how long the user would have spent typing
                await AnalyticsTracker.shared.recordTranscription(
                    wordCount: finalWordCount,
                    duration: audioDuration
                )
                Analytics.trackTranscription(
                    sttModel: sttModelId,
                    llmModel: llmModelId == "unknown" ? nil : llmModelId,
                    durationSeconds: audioDuration,
                    wordCount: finalWordCount,
                    appCategory: appContext.category.rawValue,
                    hadLLMCleanup: llmModelId != "unknown"
                )
                Task { @MainActor in
                    self?.appState.updateStats()
                }
            }

            // Resume media if we paused it
            resumeMediaIfNeeded()

            let totalMs = Date().timeIntervalSince(pipelineStart) * 1000
            NSLog("[TranscriptionPipeline] ✅ Complete in \(String(format: "%.0f", totalMs))ms: \"\(cleanedText)\"")
            return cleanedText

        } catch {
            NSLog("[TranscriptionPipeline] ❌ Error: \(error)")
            appState.creatureState = .sleeping
            appState.isProcessing = false
            appState.partialTranscription = nil
            resumeMediaIfNeeded()
            throw error
        }
    }

    func cancelRecording() {
        // Stop streaming if active before cancelling audio
        Task {
            let isStreaming = await executor.isStreaming
            if isStreaming {
                _ = try? await executor.stopStreaming()
            }
        }
        audioCapture.cancelCapture()
        appState.isRecording = false
        appState.isProcessing = false
        appState.creatureState = .sleeping
        appState.partialTranscription = nil
        isCommandMode = false
        resumeMediaIfNeeded()
    }

    // MARK: - Media Playback

    private func resumeMediaIfNeeded() {
        guard didPauseMedia else { return }
        didPauseMedia = false
        MediaPlaybackController.shared.resumeIfWasPaused()
    }

    // MARK: - Command Mode

    private func handleCommandMode(rawText: String, settings: AppSettings) async throws -> String {
        let selectedText = AppContextDetector.getSelectedText() ?? ""

        let prompt: String
        if selectedText.isEmpty {
            // Write mode: generate new content from voice instruction
            NSLog("[TranscriptionPipeline] Command mode: write mode (no selection)")
            prompt = CommandMode.buildWritePrompt(instruction: rawText)
        } else {
            // Edit mode: transform selected text
            NSLog("[TranscriptionPipeline] Command mode: edit mode (\(selectedText.count) chars selected)")
            prompt = CommandMode.buildPrompt(command: rawText, selectedText: selectedText)
        }

        let isLLMLoaded = await executor.isLLMLoaded
        guard isLLMLoaded else {
            appState.creatureState = .sleeping
            appState.isProcessing = false
            return rawText
        }
        let result = try await executor.cleanup(rawText: prompt, context: CleanupContext(
            stylePrompt: "",
            formality: .neutral,
            language: settings.language,
            appContext: nil,
            cleanupLevel: .medium,
            removeFillers: false,
            experimentalPrompts: settings.experimentalPrompts
        ))

        pasteManager.paste(result, targetApp: self.targetApp)
        appState.creatureState = .sleeping
        appState.isProcessing = false
        appState.partialTranscription = nil
        appState.lastTranscription = result
        return result
    }

    // MARK: - Snippet

    private func handleSnippet(snippet: VoiceSnippet, settings: AppSettings) async throws -> String {
        if settings.autoPaste {
            pasteManager.paste(snippet.expansion, targetApp: self.targetApp)
        }
        if settings.copyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(snippet.expansion, forType: .string)
        }

        appState.creatureState = .sleeping
        appState.isProcessing = false
        appState.lastTranscription = snippet.expansion
        return snippet.expansion
    }

    // MARK: - STT Artifact Stripping

    /// Removes Whisper hallucination artifacts from raw STT output.
    /// Whisper is trained on YouTube subtitles and generates bracketed tags like
    /// [BLANK_AUDIO], [no audio], [Music], [Applause] when it detects silence or noise.
    static let whisperArtifactRegex: NSRegularExpression = {
        // Matches bracketed tags: [BLANK_AUDIO], [no audio from the video], [Music], etc.
        // Also matches parenthesized equivalents: (sighs), (laughs), etc.
        try! NSRegularExpression(pattern: "\\[([^\\]]{0,60})\\]|\\(([^\\)]{0,40})\\)", options: .caseInsensitive)
    }()

    static func stripWhisperArtifacts(_ text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = whisperArtifactRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        // Strip Whisper trailing-pause ellipsis: "word..." → "word"
        // Uses a capture group to keep the last word character and discard the "..."
        result = result.replacingOccurrences(of: "(\\w)\\.\\.\\.", with: "$1", options: .regularExpression)
        // Collapse multiple spaces left by removed tags
        result = result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Filler Detection

    /// Quick check for common filler words that indicate LLM cleanup would help.
    /// Uses word-boundary matching to prevent false positives (e.g. "ukulele" contains "uh").
    private static let fillerRegex: NSRegularExpression = {
        let escaped = fillerWords.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = "\\b(?:" + escaped.joined(separator: "|") + ")\\b"
        return try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()

    private static func containsFillers(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return fillerRegex.firstMatch(in: text, range: range) != nil
    }

    // MARK: - Output Validation

    /// Strip example echo: small models sometimes echo few-shot examples before the actual output.
    /// Detects known example phrases or "Transcript:" markers and strips everything before them.
    static func stripExampleEcho(output: String, input: String) -> String {
        var cleaned = output

        // Check for EXAMPLE N: or Input: structure — model echoed the few-shot template.
        // Try to extract the last "out:" or "Output:" segment (the final cleaned output).
        let exampleLabelPatterns = ["EXAMPLE 1:", "EXAMPLE 2:", "EXAMPLE 3:", "Input:", "<example>"]
        for pattern in exampleLabelPatterns {
            if cleaned.contains(pattern) {
                // Find last "out:" (XML format) or "Output:" (old format) marker
                let outMarkers = ["out:", "Output:"]
                for marker in outMarkers {
                    if let lastOutputRange = cleaned.range(of: marker, options: [.caseInsensitive, .backwards]) {
                        let candidate = String(cleaned[lastOutputRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        // Validate: candidate must be shorter than full output (not just re-echoing everything)
                        // and must not be empty
                        let candidateWords = candidate.split(separator: " ").count
                        let fullWords = cleaned.split(separator: " ").count
                        if !candidate.isEmpty && candidateWords <= fullWords / 2 {
                            NSLog("[TranscriptionPipeline] ⚠️ Stripped EXAMPLE echo (found \(marker) marker)")
                            cleaned = candidate
                            break
                        }
                    }
                }
                break
            }
        }

        // Check for "Transcript:" marker — model echoed the prompt structure
        if let transcriptRange = cleaned.range(of: "Transcript:", options: .caseInsensitive) {
            let afterTranscript = String(cleaned[transcriptRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !afterTranscript.isEmpty {
                NSLog("[TranscriptionPipeline] ⚠️ Stripped example echo (Transcript: marker)")
                cleaned = afterTranscript
            }
        }

        // Check for known example phrases from few-shot prompts
        let exampleMarkers = [
            "I was thinking we should meet on Tuesday",
            "Can you grab the spreadsheet from the shared folder",
            "I told her we should move the meeting to Thursday",
            "The package got delivered to the wrong address",
        ]
        for marker in exampleMarkers {
            if cleaned.contains(marker), !input.lowercased().contains(marker.lowercased().prefix(20)) {
                // The output contains an example phrase that's NOT in the actual input — likely echo
                // Try to find where the actual transcript starts by looking for input words
                let inputFirstWords = input.split(separator: " ").prefix(4).joined(separator: " ").lowercased()
                if let startRange = cleaned.range(of: inputFirstWords, options: .caseInsensitive) {
                    let extracted = String(cleaned[startRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !extracted.isEmpty {
                        NSLog("[TranscriptionPipeline] ⚠️ Stripped example echo (matched input start)")
                        cleaned = extracted
                        break
                    }
                }
            }
        }

        // Length sanity: if output is more than 2.5x the input word count, something is wrong
        let inputWordCount = input.split(separator: " ").count
        let outputWordCount = cleaned.split(separator: " ").count
        if outputWordCount > 0 && inputWordCount > 0 && Double(outputWordCount) / Double(inputWordCount) > 2.5 {
            NSLog("[TranscriptionPipeline] ⚠️ Output suspiciously long (\(outputWordCount) vs \(inputWordCount) input words)")
        }

        return cleaned
    }

    /// Check that LLM output is a valid cleanup of the input, not a chatbot response.
    /// A valid cleanup should share a significant number of content words with the input.
    private static func isValidCleanup(input: String, output: String) -> Bool {
        let stopWords: Set<String> = ["the", "a", "an", "is", "are", "was", "were", "be", "been",
            "to", "of", "in", "for", "on", "with", "at", "by", "from", "it", "its",
            "this", "that", "and", "or", "but", "not", "no", "so", "if", "as", "do"]

        let inputWordList = input.lowercased().split(separator: " ")
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
        let outputWordList = output.lowercased().split(separator: " ")
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }

        // Reject output that is significantly longer than input — likely hallucination or echo
        if !inputWordList.isEmpty && Double(outputWordList.count) > Double(inputWordList.count) * 1.3 {
            NSLog("[TranscriptionPipeline] Validation FAILED: output (\(outputWordList.count) words) > 1.3× input (\(inputWordList.count) words) — likely hallucination")
            return false
        }

        let inputWords = Set(inputWordList
            .filter { $0.count > 2 && !stopWords.contains($0) })

        let outputWords = Set(outputWordList
            .filter { $0.count > 2 && !stopWords.contains($0) })

        guard !inputWords.isEmpty else { return true }

        let overlap = inputWords.intersection(outputWords).count
        let overlapRatio = Double(overlap) / Double(inputWords.count)

        NSLog("[TranscriptionPipeline] Validation: \(overlap)/\(inputWords.count) content words overlap (ratio: \(String(format: "%.2f", overlapRatio)))")

        // At least 50% of input content words should appear in output.
        // 0.3 was too permissive — LLM "answers" to questions scored ~0.36 and slipped through.
        return overlapRatio >= 0.5
    }

    // MARK: - Persistence

    private func fetchSettings() throws -> AppSettings {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AppSettings>()
        return try context.fetch(descriptor).first ?? AppSettings()
    }

}
