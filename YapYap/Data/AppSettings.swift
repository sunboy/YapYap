import Foundation
import SwiftData

@Model
final class AppSettings {
    var sttModelId: String
    var llmModelId: String
    var stylePrompt: String
    var formality: String
    var cleanupLevel: String
    var language: String
    var pushToTalkHotkey: Data?
    var handsFreeHotkey: Data?
    var launchAtLogin: Bool
    var showFloatingBar: Bool
    var autoPaste: Bool
    var copyToClipboard: Bool
    var notifyOnComplete: Bool
    var floatingBarPosition: String
    var historyLimit: Int
    var soundFeedback: Bool
    var hapticFeedback: Bool
    var doubleTapActivation: Bool
    var microphoneId: String?
    var gpuAcceleration: Bool
    var autoDownloadModels: Bool
    var experimentalPrompts: Bool
    var pauseMediaDuringRecording: Bool?
    /// Comma-separated list of model IDs that have been successfully loaded at least once.
    /// Used to detect downloaded models that use non-standard cache layouts (e.g. xet).
    var downloadedModelIds: String?
    /// Which inference framework to use for LLM cleanup: "mlx" or "ollama"
    var llmInferenceFramework: String
    /// Ollama server endpoint URL (only used when llmInferenceFramework is "ollama")
    var ollamaEndpoint: String
    /// Ollama model name/tag (e.g. "qwen2.5:1.5b", "llama3.2:3b"). Only used with Ollama.
    var ollamaModelName: String

    init(
        sttModelId: String = "whisper-small",
        llmModelId: String = "gemma-3-4b",
        stylePrompt: String = "",
        formality: String = "neutral",
        cleanupLevel: String = "medium",
        language: String = "en",
        pushToTalkHotkey: Data? = nil,
        handsFreeHotkey: Data? = nil,
        launchAtLogin: Bool = true,
        showFloatingBar: Bool = true,
        autoPaste: Bool = true,
        copyToClipboard: Bool = true,
        notifyOnComplete: Bool = false,
        floatingBarPosition: String = "Bottom center",
        historyLimit: Int = 100,
        soundFeedback: Bool = true,
        hapticFeedback: Bool = true,
        doubleTapActivation: Bool = false,
        microphoneId: String? = nil,
        gpuAcceleration: Bool = true,
        autoDownloadModels: Bool = true,
        experimentalPrompts: Bool = false,
        pauseMediaDuringRecording: Bool? = false,
        downloadedModelIds: String? = nil,
        llmInferenceFramework: String = LLMInferenceFramework.mlx.rawValue,
        ollamaEndpoint: String = OllamaEngine.defaultEndpoint,
        ollamaModelName: String = "qwen2.5:1.5b"
    ) {
        self.sttModelId = sttModelId
        self.llmModelId = llmModelId
        self.stylePrompt = stylePrompt
        self.formality = formality
        self.cleanupLevel = cleanupLevel
        self.language = language
        self.pushToTalkHotkey = pushToTalkHotkey
        self.handsFreeHotkey = handsFreeHotkey
        self.launchAtLogin = launchAtLogin
        self.showFloatingBar = showFloatingBar
        self.autoPaste = autoPaste
        self.copyToClipboard = copyToClipboard
        self.notifyOnComplete = notifyOnComplete
        self.floatingBarPosition = floatingBarPosition
        self.historyLimit = historyLimit
        self.soundFeedback = soundFeedback
        self.hapticFeedback = hapticFeedback
        self.doubleTapActivation = doubleTapActivation
        self.microphoneId = microphoneId
        self.gpuAcceleration = gpuAcceleration
        self.autoDownloadModels = autoDownloadModels
        self.experimentalPrompts = experimentalPrompts
        self.pauseMediaDuringRecording = pauseMediaDuringRecording
        self.downloadedModelIds = downloadedModelIds
        self.llmInferenceFramework = llmInferenceFramework
        self.ollamaEndpoint = ollamaEndpoint
        self.ollamaModelName = ollamaModelName
    }

    static func defaults() -> AppSettings {
        let profile = MachineProfile.current
        return AppSettings(
            llmModelId: profile.recommendedMLXModelId,
            ollamaModelName: profile.recommendedOllamaModelName
        )
    }
}
