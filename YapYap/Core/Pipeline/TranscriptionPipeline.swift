// TranscriptionPipeline.swift
// YapYap — Orchestrates audio → VAD → STT → cleanup → paste
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
    private var vadManager: VADManager?
    private let container: ModelContainer
    private var isCommandMode: Bool = false

    init(appState: AppState, container: ModelContainer) {
        self.appState = appState
        self.container = container
        self.audioCapture = AudioCaptureManager()
        self.pasteManager = PasteManager()
        self.vadManager = VADManager()
    }

    // MARK: - Model Loading

    func ensureModelsLoaded() async throws {
        let settings = try fetchSettings()

        // Load STT if not loaded
        if sttEngine == nil || !sttEngine!.isLoaded {
            sttEngine = STTEngineFactory.create(modelId: settings.sttModelId)
            try await sttEngine!.loadModel { progress in
                // Progress update could be published to AppState
            }
        }

        // Load LLM if not loaded
        if llmEngine == nil || !llmEngine!.isLoaded {
            llmEngine = MLXEngine()
            try await llmEngine!.loadModel(id: settings.llmModelId) { progress in
                // Progress update could be published to AppState
            }
        }
    }

    // MARK: - Recording

    func startRecording(isCommandMode: Bool = false) async throws {
        try await ensureModelsLoaded()

        self.isCommandMode = isCommandMode
        appState.creatureState = .recording
        appState.isRecording = true

        SoundManager.shared.playStart()
        HapticManager.shared.tap()

        try await audioCapture.startCapture { [weak self] rms in
            DispatchQueue.main.async {
                self?.appState.currentRMS = rms
            }
        }
    }

    func stopRecordingAndProcess() async throws -> String {
        // Stop recording
        guard let audioBuffer = audioCapture.stopCapture() else {
            appState.isRecording = false
            appState.creatureState = .sleeping
            throw YapYapError.noAudioRecorded
        }

        appState.isRecording = false
        appState.creatureState = .processing
        appState.isProcessing = true

        SoundManager.shared.playStop()
        HapticManager.shared.tap()

        do {
            // VAD filter — strip silence and noise segments
            let speechSegments = try await vadManager?.filterSpeechSegments(from: audioBuffer) ?? []
            let processBuffer: AVAudioPCMBuffer
            if speechSegments.isEmpty {
                // Fall back to original buffer if VAD finds nothing
                processBuffer = audioBuffer
            } else {
                // Concatenate speech segments
                processBuffer = AudioSegment.concatenate(speechSegments) ?? audioBuffer
            }

            // STT transcription
            let transcription = try await sttEngine!.transcribe(audioBuffer: processBuffer)
            let rawText = transcription.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            guard !rawText.isEmpty else {
                appState.creatureState = .sleeping
                appState.isProcessing = false
                throw YapYapError.noAudioRecorded
            }

            let settings = try fetchSettings()

            // Check for command mode
            if isCommandMode || CommandMode.isCommand(rawText) {
                return try await handleCommandMode(rawText: rawText, settings: settings)
            }

            // Check for snippet trigger
            let snippetManager = SnippetManager()
            if let snippet = snippetManager.matchSnippet(from: rawText) {
                return try await handleSnippet(snippet: snippet, settings: settings)
            }

            // Apply personal dictionary corrections
            let personalDict = PersonalDictionary()
            let correctedText = personalDict.applyCorrections(to: rawText)

            // Detect app context
            let styleSettings = StyleSettings()
            let appContext = AppContextDetector.detect(settings: styleSettings)

            // LLM cleanup
            let context = CleanupContext(
                stylePrompt: settings.stylePrompt,
                formality: CleanupContext.Formality(rawValue: settings.formality) ?? .neutral,
                language: settings.language,
                appContext: appContext,
                cleanupLevel: CleanupContext.CleanupLevel(rawValue: settings.cleanupLevel) ?? .medium,
                removeFillers: true
            )

            var cleanedText = try await llmEngine!.cleanup(rawText: correctedText, context: context)

            // Post-processing: apply output formatting
            cleanedText = OutputFormatter.format(cleanedText, for: appContext)

            // Post-processing: regex filler filter safety net
            cleanedText = FillerFilter.removeFillers(from: cleanedText, aggressive: settings.cleanupLevel == "heavy")

            // Paste
            if settings.autoPaste {
                pasteManager.paste(cleanedText)
            }
            if settings.copyToClipboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cleanedText, forType: .string)
            }

            // Save to history
            try saveTranscription(
                raw: rawText,
                cleaned: cleanedText,
                duration: transcription.processingTime,
                sttModel: sttEngine?.modelInfo.id ?? "unknown",
                sourceApp: appContext.appName
            )

            // Update analytics
            await AnalyticsTracker.shared.recordTranscription(
                wordCount: cleanedText.split(separator: " ").count,
                duration: transcription.processingTime
            )

            // Update state
            appState.creatureState = .sleeping
            appState.isProcessing = false
            appState.lastTranscription = cleanedText

            // Update stats in popover
            appState.updateStats()

            return cleanedText

        } catch {
            appState.creatureState = .sleeping
            appState.isProcessing = false
            throw error
        }
    }

    func cancelRecording() {
        audioCapture.cancelCapture()
        appState.isRecording = false
        appState.isProcessing = false
        appState.creatureState = .sleeping
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
            removeFillers: false
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

    // MARK: - Persistence

    private func fetchSettings() throws -> AppSettings {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AppSettings>()
        return try context.fetch(descriptor).first ?? AppSettings()
    }

    private func saveTranscription(raw: String, cleaned: String, duration: TimeInterval, sttModel: String, sourceApp: String) throws {
        let context = ModelContext(container)
        let entry = Transcription(
            rawText: raw,
            cleanedText: cleaned,
            durationSeconds: duration,
            wordCount: cleaned.split(separator: " ").count,
            sttModel: sttModel,
            llmModel: llmEngine?.modelId ?? "unknown",
            sourceApp: sourceApp,
            language: "en"
        )
        context.insert(entry)
        try context.save()
    }
}
