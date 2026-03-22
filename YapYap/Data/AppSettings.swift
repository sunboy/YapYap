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
    /// Which inference framework to use for LLM cleanup: "mlx", "llamacpp", or "ollama"
    var llmInferenceFramework: String
    /// Ollama server endpoint URL (only used when llmInferenceFramework is "ollama")
    var ollamaEndpoint: String
    /// Ollama model name/tag (e.g. "qwen2.5:1.5b", "llama3.2:3b"). Only used with Ollama.
    var ollamaModelName: String
    /// Selected GGUF model ID for llama.cpp framework (e.g. "gguf-gemma-3-4b")
    var llamacppModelId: String
    /// Word count threshold below which LLM cleanup is skipped (fast path). Default 20.
    var llmSkipWordThreshold: Int
    /// STT pipeline mode: "streaming" (live preview) or "batch" (fastest, no preview).
    /// Optional for SwiftData migration — nil treated as "batch".
    var sttMode: String?
    /// Prompt engine version: true = V2 (new unified prompt), false = V1 (classic multi-tier).
    /// Defaults to true. Power users can switch to V1 for compatibility.
    /// Deprecated: use promptVersion instead. Kept for SwiftData migration compatibility.
    var useV2Prompts: Bool
    /// Prompt engine version: "v1", "v2", or "v3". Defaults to "v3" (DSPy-optimized).
    /// V3 uses model-family-specific prompts with static prefix KV caching.
    var promptVersion: String?

    init(
        sttModelId: String = "parakeet-tdt-v3",
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
        ollamaModelName: String = "qwen2.5:1.5b",
        llamacppModelId: String = GGUFModelRegistry.recommendedModel.id,
        llmSkipWordThreshold: Int = 20,
        sttMode: String? = "streaming",
        useV2Prompts: Bool = true,
        promptVersion: String? = CleanupContext.PromptVersion.v3.rawValue
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
        self.llamacppModelId = llamacppModelId
        self.llmSkipWordThreshold = llmSkipWordThreshold
        self.sttMode = sttMode
        self.useV2Prompts = useV2Prompts
        self.promptVersion = promptVersion
    }

    /// Resolved prompt version, falling back through promptVersion → useV2Prompts → v3.
    /// Handles migration from the old boolean useV2Prompts to the new versioned field.
    var resolvedPromptVersion: CleanupContext.PromptVersion {
        if let version = promptVersion, let v = CleanupContext.PromptVersion(rawValue: version) {
            return v
        }
        // Migration: old useV2Prompts boolean → map to v2 or v1
        return useV2Prompts ? .v2 : .v1
    }

    static func defaults() -> AppSettings {
        let profile = MachineProfile.current
        return AppSettings(
            llmModelId: profile.recommendedMLXModelId,
            ollamaModelName: profile.recommendedOllamaModelName,
            llamacppModelId: profile.recommendedGGUFModelId
        )
    }
}
