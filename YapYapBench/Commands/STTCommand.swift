// STTCommand.swift
// YapYapBench — Transcribe a WAV file using an STT model
import ArgumentParser
import Foundation

struct STTCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stt",
        abstract: "Transcribe a WAV file using a speech-to-text model."
    )

    @Argument(help: "WAV file to transcribe.")
    var file: String

    @Option(name: .long, help: "STT model ID (default: whisper-small).")
    var sttModel: String = "whisper-small"

    @Option(name: .long, help: "Language code for transcription (default: en).")
    var language: String = "en"

    func run() async throws {
        let url = URL(fileURLWithPath: file)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BenchError.sttFailed("File not found: \(file)")
        }

        // Load WAV
        FileHandle.standardError.write("Loading \(file)...\n".data(using: .utf8)!)
        let (buffer, duration) = try WAVLoader.load(url: url)
        FileHandle.standardError.write(String(format: "Audio: %.1fs, %d frames\n", duration, buffer.frameLength).data(using: .utf8)!)

        // Create STT engine
        guard STTModelRegistry.model(for: sttModel) != nil else {
            throw BenchError.invalidModel("Unknown STT model: \(sttModel). Run 'yapyapbench list' to see available models.")
        }
        let engine = STTEngineFactory.create(modelId: sttModel)

        // Load model
        FileHandle.standardError.write("Loading STT model '\(sttModel)'...\n".data(using: .utf8)!)
        try await engine.loadModel { progress in
            let pct = Int(progress * 100)
            FileHandle.standardError.write("\rLoading: \(pct)%".data(using: .utf8)!)
        }
        FileHandle.standardError.write("\n".data(using: .utf8)!)

        // Transcribe
        FileHandle.standardError.write("Transcribing...\n".data(using: .utf8)!)
        let result = try await engine.transcribe(audioBuffer: buffer, language: language)

        FileHandle.standardError.write(String(format: "Latency: %.0fms\n", result.processingTime * 1000).data(using: .utf8)!)
        if let lang = result.language {
            FileHandle.standardError.write("Detected language: \(lang)\n".data(using: .utf8)!)
        }

        // Output transcript to stdout
        print(result.text)
    }
}
