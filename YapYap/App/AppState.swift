import Foundation
import SwiftUI

@Observable
final class AppState {
    var creatureState: CreatureState = .sleeping
    var isRecording: Bool = false
    var isProcessing: Bool = false
    var masterToggle: Bool = true
    var currentRMS: Float = 0.0
    var lastTranscription: String?
    var isCommandMode: Bool = false
    /// Raw STT output shown as preview while LLM processes
    var partialTranscription: String?

    // Model loading state
    var isLoadingModels: Bool = false
    var modelLoadingProgress: Double = 0.0
    var modelLoadingStatus: String = ""
    var modelsReady: Bool = false

    // Quick stats for popover
    var todayCount: Int = 0
    var todayWords: Int = 0
    var todayTimeSaved: String = "0m"

    func updateStats() {
        Task { @MainActor in
            let stats = AnalyticsTracker.shared.getTodayStats()
            todayCount = stats.transcriptionCount
            todayWords = stats.wordCount
            let minutes = Int(stats.totalDurationSeconds / 60)
            todayTimeSaved = minutes > 60 ? "\(minutes / 60)h" : "\(minutes)m"
        }
    }
}
