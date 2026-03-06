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

        // Register device context as super-properties — attached to every event
        // so we can segment by hardware without sending PII.
        let profile = MachineProfile.current
        let ramGB = Double(profile.totalRAMBytes) / (1024 * 1024 * 1024)
        PostHogSDK.shared.register([
            "$set_once": [
                "device_ram_gb": Int(ramGB),
                "device_cores": profile.cpuCoreCount,
                "device_tier": profile.tier.rawValue,
                "os_version": ProcessInfo.processInfo.operatingSystemVersionString
            ]
        ])
    }

    // MARK: - App lifecycle

    /// Called once on very first launch after onboarding completes
    static func trackInstall(sttModel: String, llmModel: String) {
        capture("app_installed", properties: [
            "stt_model": sttModel,
            "llm_model": llmModel,
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "app_version": appVersion,
            "device_ram_gb": deviceRAMGB,
            "device_cores": deviceCores,
            "device_tier": deviceTier
        ])
    }

    static func trackAppLaunched() {
        capture("app_launched", properties: [
            "app_version": appVersion,
            "device_ram_gb": deviceRAMGB,
            "device_tier": deviceTier
        ])
    }

    // MARK: - Transcription (enriched with performance data)

    static func trackTranscription(
        sttModel: String,
        llmModel: String?,
        durationSeconds: Double,
        wordCount: Int,
        appCategory: String,
        hadLLMCleanup: Bool,
        sttMs: Double = 0,
        llmMs: Double = 0,
        totalPipelineMs: Double = 0,
        vadReductionPct: Double = 0,
        llmTokensPerSec: Double = 0,
        promptCacheHit: Bool = false,
        llmSkipped: Bool = false,
        usedStreaming: Bool = false
    ) {
        capture("transcription_completed", properties: [
            "stt_model": sttModel,
            "llm_model": llmModel ?? "none",
            "duration_seconds": durationSeconds,
            "word_count": wordCount,
            "app_category": appCategory,
            "had_llm_cleanup": hadLLMCleanup,
            // Performance metrics
            "stt_ms": Int(sttMs),
            "llm_ms": Int(llmMs),
            "total_pipeline_ms": Int(totalPipelineMs),
            "vad_reduction_pct": Int(vadReductionPct),
            "llm_tokens_per_sec": Int(llmTokensPerSec),
            "prompt_cache_hit": promptCacheHit,
            "llm_skipped": llmSkipped,
            "used_streaming": usedStreaming
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

    // MARK: - Device helpers (cached)

    private static let deviceRAMGB: Int = {
        Int(Double(MachineProfile.current.totalRAMBytes) / (1024 * 1024 * 1024))
    }()

    private static let deviceCores: Int = MachineProfile.current.cpuCoreCount
    private static let deviceTier: String = MachineProfile.current.tier.rawValue
}
