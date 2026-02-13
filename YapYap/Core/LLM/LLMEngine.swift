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

    enum Formality: String, Codable {
        case casual, neutral, formal
    }

    enum CleanupLevel: String, Codable {
        case light, medium, heavy
    }
}

protocol LLMEngine: AnyObject {
    var isLoaded: Bool { get }
    var modelId: String? { get }
    func loadModel(id: String, progressHandler: @escaping (Double) -> Void) async throws
    func unloadModel()
    func cleanup(rawText: String, context: CleanupContext) async throws -> String
}
