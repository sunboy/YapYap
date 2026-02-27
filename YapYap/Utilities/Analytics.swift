// Analytics.swift
// YapYap — Privacy-respecting usage analytics via PostHog
// Tracks high-level product metrics only. No audio, no transcribed text, no PII.
import PostHog
import Foundation

struct Analytics {

    // MARK: - Setup

    static func start() {
        guard isEnabled else { return }

        let config = PostHogConfig(
            apiKey: "phc_kOGqJIy7F3yxPfI8w3WB89E5s4BJ364Qrq6X8HEK6LY",
            host: "https://us.i.posthog.com"
        )

        // Disable automatic capture — we control exactly what's sent
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false

        // Use a random stable ID per install — no name, email, or device fingerprint
        config.personProfiles = .never

        #if DEBUG
        config.debug = true
        #endif

        PostHogSDK.shared.setup(config)

        // Identify this install with a random UUID (generated once, stored locally)
        PostHogSDK.shared.identify(installId)
    }

    // MARK: - App lifecycle

    /// Called once on very first launch after onboarding completes
    static func trackInstall(sttModel: String, llmModel: String) {
        capture("app_installed", properties: [
            "stt_model": sttModel,
            "llm_model": llmModel,
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "app_version": appVersion
        ])
    }

    static func trackAppLaunched() {
        capture("app_launched", properties: [
            "app_version": appVersion
        ])
    }

    // MARK: - Transcription

    static func trackTranscription(
        sttModel: String,
        llmModel: String?,
        durationSeconds: Double,
        wordCount: Int,
        appCategory: String,
        hadLLMCleanup: Bool
    ) {
        capture("transcription_completed", properties: [
            "stt_model": sttModel,
            "llm_model": llmModel ?? "none",
            "duration_seconds": durationSeconds,
            "word_count": wordCount,
            "app_category": appCategory,
            "had_llm_cleanup": hadLLMCleanup
        ])
    }

    static func trackTranscriptionFailed(sttModel: String, reason: String) {
        capture("transcription_failed", properties: [
            "stt_model": sttModel,
            "reason": reason
        ])
    }

    // MARK: - Model management

    static func trackModelDownloaded(modelId: String, modelType: String) {
        capture("model_downloaded", properties: [
            "model_id": modelId,
            "model_type": modelType // "stt" or "llm"
        ])
    }

    static func trackModelChanged(modelType: String, fromModel: String, toModel: String) {
        capture("model_changed", properties: [
            "model_type": modelType,
            "from_model": fromModel,
            "to_model": toModel
        ])
    }

    // MARK: - Settings

    static func trackSettingChanged(setting: String, value: String) {
        capture("setting_changed", properties: [
            "setting": setting,
            "value": value
        ])
    }

    // MARK: - Onboarding

    static func trackOnboardingStep(step: Int, stepName: String) {
        capture("onboarding_step_viewed", properties: [
            "step": step,
            "step_name": stepName
        ])
    }

    static func trackOnboardingCompleted() {
        capture("onboarding_completed")
    }

    // MARK: - Opt-in/out

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "analyticsEnabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "analyticsEnabled")
            if !newValue {
                PostHogSDK.shared.optOut()
            } else {
                PostHogSDK.shared.optIn()
            }
        }
    }

    // MARK: - Private

    private static func capture(_ event: String, properties: [String: Any] = [:]) {
        guard isEnabled else { return }
        PostHogSDK.shared.capture(event, properties: properties)
    }

    private static var installId: String {
        let key = "analyticsInstallId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}
