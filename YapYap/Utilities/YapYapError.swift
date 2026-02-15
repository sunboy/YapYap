import Foundation

enum YapYapError: LocalizedError {
    case modelNotLoaded
    case modelDownloadFailed(String)
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case audioCaptureFailed(Error)
    case transcriptionFailed(Error)
    case cleanupFailed(Error)
    case pasteFailed(Error)
    case noAudioRecorded
    case noTextSelected

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "AI model is not loaded. Go to Settings → Models to download one."
        case .modelDownloadFailed(let msg):
            return "Failed to download model: \(msg)"
        case .microphonePermissionDenied:
            return "Microphone access is required. Open System Settings → Privacy & Security → Microphone."
        case .accessibilityPermissionDenied:
            return "Accessibility access is required for auto-paste. Open System Settings → Privacy & Security → Accessibility."
        case .audioCaptureFailed(let err):
            return "Audio capture failed: \(err.localizedDescription)"
        case .transcriptionFailed(let err):
            return "Transcription failed: \(err.localizedDescription)"
        case .cleanupFailed(let err):
            return "Text cleanup failed: \(err.localizedDescription)"
        case .pasteFailed(let err):
            return "Paste failed: \(err.localizedDescription)"
        case .noAudioRecorded:
            return "No speech was detected. Try speaking louder or closer to the mic."
        case .noTextSelected:
            return "No text selected. Highlight text first, then give a command."
        }
    }
}
