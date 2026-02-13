import Foundation
import SwiftData

@Model
final class PowerModeRule {
    var id: UUID
    var appBundleId: String?
    var urlPattern: String?
    var stylePrompt: String
    var formality: String
    var cleanupLevel: String
    var sttModelId: String?
    var llmModelId: String?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        appBundleId: String? = nil,
        urlPattern: String? = nil,
        stylePrompt: String = "",
        formality: String = "casual",
        cleanupLevel: String = "medium",
        sttModelId: String? = nil,
        llmModelId: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.appBundleId = appBundleId
        self.urlPattern = urlPattern
        self.stylePrompt = stylePrompt
        self.formality = formality
        self.cleanupLevel = cleanupLevel
        self.sttModelId = sttModelId
        self.llmModelId = llmModelId
        self.isEnabled = isEnabled
    }
}
