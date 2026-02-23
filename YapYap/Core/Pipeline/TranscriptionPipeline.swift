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

    private var sttEngine: (any STTEngine)?
    private var llmEngine: (any LLMEngine)?
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

    /// Keep-alive timer: periodic warmup to prevent OS from evicting model weights
    private var keepAliveTimer: Timer?
    private static let keepAliveInterval: TimeInterval = 1800 // 30 minutes

    /// Pre-computed context: captured at recording start so it's ready when STT finishes
    private var cachedStyleSettings: StyleSettings?
    private var cachedAppContext: AppContext?

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
            appState.modelsReady = true
            appState.modelLoadingStatus = "Ready to transcribe"
            NSLog("[TranscriptionPipeline] ✅ Models loaded at startup, app ready")
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
                await self.sttEngine?.warmup()
                await self.llmEngine?.warmup()
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

        // Reload STT if not loaded OR if user switched to a different model in Settings
        let needsSTTReload = sttEngine == nil || !sttEngine!.isLoaded
            || sttEngine!.modelInfo.id != settings.sttModelId
        if needsSTTReload {
            if let existing = sttEngine, existing.isLoaded {
                NSLog("[TranscriptionPipeline] STT model changed: \(existing.modelInfo.id) → \(settings.sttModelId), unloading old")
                existing.unloadModel()
            }
            appState.modelLoadingStatus = "Loading speech model..."
            appState.modelLoadingProgress = 0.0
            NSLog("[TranscriptionPipeline] Loading STT model: \(settings.sttModelId)")

            sttEngine = STTEngineFactory.create(modelId: settings.sttModelId)
            try await sttEngine!.loadModel { [weak self] progress in
                Task { @MainActor in
                    self?.appState.modelLoadingProgress = progress * 0.5 // First 50%
                }
            }
            NSLog("[TranscriptionPipeline] ✅ STT model loaded")
        }

        // Reload LLM if not loaded OR if user switched to a different model in Settings
        let needsLLMReload = llmEngine == nil || !llmEngine!.isLoaded
            || llmEngine!.modelId != settings.llmModelId
        if needsLLMReload {
            if let existing = llmEngine, existing.isLoaded {
                NSLog("[TranscriptionPipeline] LLM model changed: \(existing.modelId ?? "unknown") → \(settings.llmModelId), unloading old")
                existing.unloadModel()
            }
            appState.modelLoadingStatus = "Loading language model..."
            appState.modelLoadingProgress = 0.5
            NSLog("[TranscriptionPipeline] Loading LLM model: \(settings.llmModelId)")

            llmEngine = MLXEngine()
            try await llmEngine!.loadModel(id: settings.llmModelId) { [weak self] progress in
                Task { @MainActor in
                    self?.appState.modelLoadingProgress = 0.5 + (progress * 0.5) // Next 50%
                }
            }
            NSLog("[TranscriptionPipeline] ✅ LLM model loaded")
        }

        appState.modelLoadingProgress = 1.0
    }

    // MARK: - Recording

    func startRecording(isCommandMode: Bool = false) async throws {
        NSLog("[TranscriptionPipeline] startRecording() called, isCommandMode: \(isCommandMode)")
        print("[TranscriptionPipeline] startRecording() called, isCommandMode: \(isCommandMode)")

        // CHECK MICROPHONE PERMISSION FIRST - gives instant feedback if denied
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        NSLog("[TranscriptionPipeline] Microphone permission check: status=\(micStatus.rawValue), bundleId=\(bundleId)")

        guard micStatus == .authorized else {
            NSLog("[TranscriptionPipeline] ❌ Microphone permission denied (status=\(micStatus.rawValue))")
            throw YapYapError.microphonePermissionDenied
        }

        NSLog("[TranscriptionPipeline] ✅ Microphone permission granted")

        // CHECK IF MODELS ARE READY - should already be loaded at startup
        if !appState.modelsReady {
            NSLog("[TranscriptionPipeline] ⚠️ Models not ready, loading now...")
            appState.modelLoadingStatus = "Loading models..."
            try await ensureModelsLoaded()
            appState.modelsReady = true
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
        NSLog("[TranscriptionPipeline] Pre-cached context: \(appContext.appName) (\(appContext.category.rawValue))")

        try await audioCapture.startCapture { [weak self] rms in
            DispatchQueue.main.async {
                self?.appState.currentRMS = rms
            }
        }
        print("[TranscriptionPipeline] Audio capture started")
    }

    func stopRecordingAndProcess() async throws -> String {
        let pipelineStart = Date()
        NSLog("[TranscriptionPipeline] stopRecordingAndProcess() called")

        // Stop recording
        guard let audioBuffer = audioCapture.stopCapture() else {
            NSLog("[TranscriptionPipeline] ❌ No audio buffer captured (too short or empty)")
            appState.isRecording = false
            appState.creatureState = .sleeping
            throw YapYapError.noAudioRecorded
        }

        let audioDuration = Double(audioBuffer.frameLength) / audioCapture.sampleRate
        NSLog("[TranscriptionPipeline] ✅ Audio buffer: \(audioBuffer.frameLength) frames (\(String(format: "%.1f", audioDuration))s)")

        appState.isRecording = false
        appState.creatureState = .processing
        appState.isProcessing = true

        SoundManager.shared.playStop()
        HapticManager.shared.tap()

        do {
            // SKIP VAD — WhisperKit handles silence natively, VAD adds 100-300ms latency
            // Feed raw audio directly to STT

            // STT transcription — pass user's language setting to the engine
            var stageStart = Date()
            let settings = try fetchSettings()
            let transcription = try await sttEngine!.transcribe(audioBuffer: audioBuffer, language: settings.language)
            let rawText = transcription.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            NSLog("[TranscriptionPipeline] STT: \"\(rawText)\" (\(String(format: "%.0f", Date().timeIntervalSince(stageStart) * 1000))ms)")

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

                cleanedText = try await llmEngine!.cleanup(rawText: correctedText, context: context)
                NSLog("[TranscriptionPipeline] LLM: \"\(cleanedText)\" (\(String(format: "%.0f", Date().timeIntervalSince(stageStart) * 1000))ms)")

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
                pasteManager.paste(cleanedText)
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

            // Auto-learn corrections: monitor the focused text field for user edits
            if settings.autoPaste {
                personalDict.monitorAndLearn(pastedText: cleanedText)
            }

            // Move history save + analytics off the critical path.
            // Text is already pasted, no need to block on disk I/O.
            let finalWordCount = cleanedText.split(separator: " ").count
            let sttModelId = sttEngine?.modelInfo.id ?? "unknown"
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
                        llmModel: self?.llmEngine?.modelId ?? "unknown",
                        sourceApp: sourceApp,
                        language: transcription.language ?? "en"
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
                Task { @MainActor in
                    self?.appState.updateStats()
                }
            }

            let totalMs = Date().timeIntervalSince(pipelineStart) * 1000
            NSLog("[TranscriptionPipeline] ✅ Complete in \(String(format: "%.0f", totalMs))ms: \"\(cleanedText)\"")
            return cleanedText

        } catch {
            NSLog("[TranscriptionPipeline] ❌ Error: \(error)")
            appState.creatureState = .sleeping
            appState.isProcessing = false
            appState.partialTranscription = nil
            throw error
        }
    }

    func cancelRecording() {
        audioCapture.cancelCapture()
        appState.isRecording = false
        appState.isProcessing = false
        appState.creatureState = .sleeping
        appState.partialTranscription = nil
        isCommandMode = false
    }

    // MARK: - Command Mode

    private func handleCommandMode(rawText: String, settings: AppSettings) async throws -> String {
        let selectedText = AppContextDetector.getSelectedText() ?? ""
        guard !selectedText.isEmpty else {
            appState.creatureState = .sleeping
            appState.isProcessing = false
            return rawText // Just paste the raw text if nothing is selected
        }

        let prompt = CommandMode.buildPrompt(command: rawText, selectedText: selectedText)
        let result = try await llmEngine!.cleanup(rawText: prompt, context: CleanupContext(
            stylePrompt: "",
            formality: .neutral,
            language: settings.language,
            appContext: nil,
            cleanupLevel: .medium,
            removeFillers: false,
            experimentalPrompts: settings.experimentalPrompts
        ))

        pasteManager.paste(result)
        appState.creatureState = .sleeping
        appState.isProcessing = false
        appState.lastTranscription = result
        return result
    }

    // MARK: - Snippet

    private func handleSnippet(snippet: VoiceSnippet, settings: AppSettings) async throws -> String {
        if settings.autoPaste {
            pasteManager.paste(snippet.expansion)
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

    // MARK: - Filler Detection

    /// Quick check for common filler words that indicate LLM cleanup would help
    private static func containsFillers(_ text: String) -> Bool {
        let lower = text.lowercased()
        return fillerWords.contains(where: { lower.contains($0) })
    }

    // MARK: - Output Validation

    /// Strip example echo: small models sometimes echo few-shot examples before the actual output.
    /// Detects known example phrases or "Transcript:" markers and strips everything before them.
    private static func stripExampleEcho(output: String, input: String) -> String {
        var cleaned = output

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
            "I was thinking we should have a meeting tomorrow to discuss the project timeline.",
            "An iOS app\n2. A website\n3. API documentation",
            "Pick up groceries",
            "Fix the auth bug",
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

        let inputWords = Set(input.lowercased().split(separator: " ")
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 2 && !stopWords.contains($0) })

        let outputWords = Set(output.lowercased().split(separator: " ")
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 2 && !stopWords.contains($0) })

        guard !inputWords.isEmpty else { return true }

        let overlap = inputWords.intersection(outputWords).count
        let overlapRatio = Double(overlap) / Double(inputWords.count)

        NSLog("[TranscriptionPipeline] Validation: \(overlap)/\(inputWords.count) content words overlap (ratio: \(String(format: "%.2f", overlapRatio)))")

        // At least 30% of input content words should appear in output
        return overlapRatio >= 0.3
    }

    // MARK: - Persistence

    private func fetchSettings() throws -> AppSettings {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AppSettings>()
        return try context.fetch(descriptor).first ?? AppSettings()
    }

}
