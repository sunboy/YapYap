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
    var microphoneId: String?
    var gpuAcceleration: Bool
    var autoDownloadModels: Bool

    init(
        sttModelId: String = "whisper-large-v3-turbo",
        llmModelId: String = "qwen-1.5b",
        stylePrompt: String = "",
        formality: String = "casual",
        cleanupLevel: String = "medium",
        language: String = "en",
        pushToTalkHotkey: Data? = nil,
        handsFreeHotkey: Data? = nil,
        launchAtLogin: Bool = false,
        showFloatingBar: Bool = true,
        autoPaste: Bool = true,
        copyToClipboard: Bool = false,
        notifyOnComplete: Bool = false,
        floatingBarPosition: String = "center",
        historyLimit: Int = 100,
        soundFeedback: Bool = true,
        hapticFeedback: Bool = true,
        microphoneId: String? = nil,
        gpuAcceleration: Bool = true,
        autoDownloadModels: Bool = false
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
        self.microphoneId = microphoneId
        self.gpuAcceleration = gpuAcceleration
        self.autoDownloadModels = autoDownloadModels
    }

    static func defaults() -> AppSettings {
        return AppSettings()
    }
}
