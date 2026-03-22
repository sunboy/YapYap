// LLMEngine.swift
// YapYap — LLM engine protocol for text cleanup
import Foundation

struct CleanupContext {
    let stylePrompt: String
    let formality: Formality
    let language: String
    let appContext: AppContext?
    let cleanupLevel: CleanupLevel
    let removeFillers: Bool
    let experimentalPrompts: Bool
    /// Which prompt engine version to use. Defaults to V3 (DSPy-optimized, static prefix caching).
    var promptVersion: PromptVersion = .v3

    /// Backward-compatible accessor for code that checks useV2Prompts.
    var useV2Prompts: Bool {
        get { promptVersion == .v2 }
        set { promptVersion = newValue ? .v2 : .v1 }
    }

    enum Formality: String, Codable {
        case casual, neutral, formal
    }

    enum CleanupLevel: String, Codable {
        case light, medium, heavy
    }

    /// Prompt engine version.
    /// - v1: Classic single system+user prompt with model-size tiers
    /// - v2: Unified multi-turn chat with app context in system prompt
    /// - v3: DSPy-optimized, model-family-specific prompts with static prefix KV caching
    ///       (app context in user message, not system prompt — never invalidates KV cache on app switch)
    enum PromptVersion: String, Codable {
        case v1, v2, v3
    }
}

protocol LLMEngine: AnyObject {
    var isLoaded: Bool { get }
    var modelId: String? { get }
    func loadModel(id: String, progressHandler: @escaping (Double) -> Void) async throws
    func unloadModel()
    func cleanup(rawText: String, context: CleanupContext) async throws -> String
    /// Run a minimal inference to keep model weights resident in memory
    func warmup() async
}
