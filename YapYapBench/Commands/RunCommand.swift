// RunCommand.swift
// YapYapBench — Run a single WAV file through the STT + LLM benchmark matrix
import ArgumentParser
import Foundation

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a WAV file through the STT + LLM benchmark matrix."
    )

    @Argument(help: "WAV file to benchmark.")
    var file: String

    @Option(name: .long, help: "STT model ID (default: whisper-small).")
    var sttModel: String = "whisper-small"

    @Option(name: .long, help: "Comma-separated LLM model IDs, or 'all' (default: recommended model).")
    var llmModels: String?

    @Option(name: .long, help: "Comma-separated contexts, or 'all' (default: email).")
    var contexts: String = "email"

    @Option(name: .long, help: "Comma-separated cleanup levels, or 'all' (default: medium).")
    var cleanupLevels: String = "medium"

    @Option(name: .long, help: "Pre-transcribed text (skip STT).")
    var transcript: String?

    @Option(name: .shortAndLong, help: "Output JSON to file instead of stdout.")
    var output: String?

    @Flag(name: .long, help: "Print markdown comparison table to stderr.")
    var table: Bool = false

    @Flag(name: .long, help: "Enable experimental prompts (upgrade small model prompts).")
    var experimental: Bool = false

    @Option(name: .long, help: "Language code for STT (default: en).")
    var language: String = "en"

    func run() async throws {
        let url = URL(fileURLWithPath: file)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BenchError.sttFailed("File not found: \(file)")
        }

        let llmModelIds = parseLLMModels(llmModels)
        let contextList = ContextFactory.parseContexts(contexts)
        let levels = ContextFactory.parseCleanupLevels(cleanupLevels)

        let config = BenchmarkConfig(
            sttModelId: sttModel,
            llmModelIds: llmModelIds,
            contextNames: contextList,
            cleanupLevels: levels,
            experimentalPrompts: experimental,
            language: language
        )

        let runner = BenchmarkRunner()
        let recording = try await runner.runSingle(wavURL: url, transcript: transcript, config: config)

        let sttConfig = transcript == nil ? STTConfig(modelId: sttModel, language: language) : nil
        let result = BenchmarkResult(sttConfig: sttConfig, recordings: [recording])

        outputResults(result, to: output, table: table)
    }
}

// MARK: - Shared Helpers

func parseLLMModels(_ input: String?) -> [String] {
    guard let input = input else {
        return [LLMModelRegistry.recommendedModel.id]
    }
    if input.lowercased() == "all" {
        return LLMModelRegistry.allModels.map(\.id)
    }
    return input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
}

func outputResults(_ result: BenchmarkResult, to outputPath: String?, table: Bool) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let jsonData = try? encoder.encode(result),
          let jsonString = String(data: jsonData, encoding: .utf8) else {
        FileHandle.standardError.write("ERROR: Failed to encode results to JSON\n".data(using: .utf8)!)
        return
    }

    if let outputPath = outputPath {
        do {
            try jsonString.write(toFile: outputPath, atomically: true, encoding: .utf8)
            FileHandle.standardError.write("Results written to \(outputPath)\n".data(using: .utf8)!)
        } catch {
            FileHandle.standardError.write("ERROR: Failed to write to \(outputPath): \(error)\n".data(using: .utf8)!)
        }
    } else {
        print(jsonString)
    }

    if table {
        TableFormatter.printTable(result)
    }
}
