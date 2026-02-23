// BatchCommand.swift
// YapYapBench — Run all WAV files in a directory through the benchmark matrix
import ArgumentParser
import Foundation

struct BatchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "batch",
        abstract: "Run all WAV files in a directory through the benchmark matrix."
    )

    @Argument(help: "Directory containing WAV files.")
    var directory: String

    @Option(name: .long, help: "STT model ID (default: whisper-small).")
    var sttModel: String = "whisper-small"

    @Option(name: .long, help: "Comma-separated LLM model IDs, or 'all' (default: recommended model).")
    var llmModels: String?

    @Option(name: .long, help: "Comma-separated contexts, or 'all' (default: email).")
    var contexts: String = "email"

    @Option(name: .long, help: "Comma-separated cleanup levels, or 'all' (default: medium).")
    var cleanupLevels: String = "medium"

    @Option(name: .shortAndLong, help: "Output JSON to file instead of stdout.")
    var output: String?

    @Flag(name: .long, help: "Print markdown comparison table to stderr.")
    var table: Bool = false

    @Flag(name: .long, help: "Enable experimental prompts.")
    var experimental: Bool = false

    @Option(name: .long, help: "Language code for STT (default: en).")
    var language: String = "en"

    func run() async throws {
        let dirURL = URL(fileURLWithPath: directory)
        let wavFiles = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })

        guard !wavFiles.isEmpty else {
            throw BenchError.noWAVFiles("No .wav files found in \(directory)")
        }

        FileHandle.standardError.write("Found \(wavFiles.count) WAV file(s) in \(directory)\n".data(using: .utf8)!)

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
        var recordings: [RecordingResult] = []

        for (index, wavURL) in wavFiles.enumerated() {
            FileHandle.standardError.write("\n--- [\(index + 1)/\(wavFiles.count)] \(wavURL.lastPathComponent) ---\n".data(using: .utf8)!)
            let recording = try await runner.runSingle(wavURL: wavURL, transcript: nil, config: config)
            recordings.append(recording)
        }

        let sttConfig = STTConfig(modelId: sttModel, language: language)
        let result = BenchmarkResult(sttConfig: sttConfig, recordings: recordings)

        outputResults(result, to: output, table: table)
    }
}
