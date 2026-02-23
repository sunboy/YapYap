// RecordCommand.swift
// YapYapBench — Record audio from microphone to WAV file
import ArgumentParser
import Foundation

struct RecordCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "Record audio from the microphone to a WAV file (16kHz mono)."
    )

    @Argument(help: "Output WAV file path.")
    var output: String

    func run() async throws {
        let url = URL(fileURLWithPath: output)
        let recorder = WAVRecorder()

        FileHandle.standardError.write("Recording to \(output)... Press Enter to stop.\n".data(using: .utf8)!)

        try recorder.record(to: url)

        // Wait for Enter key
        _ = readLine()

        recorder.stop()
        FileHandle.standardError.write("Saved recording to \(output)\n".data(using: .utf8)!)
    }
}
