// main.swift
// YapYapBench — Pipeline benchmarking CLI tool
import ArgumentParser

@main
struct YapYapBench: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "yapyapbench",
        abstract: "Benchmark YapYap STT + LLM pipeline across models and contexts.",
        version: "1.0.0",
        subcommands: [
            ListCommand.self,
            RecordCommand.self,
            STTCommand.self,
            RunCommand.self,
            BatchCommand.self,
            CorpusCommand.self,
        ],
        defaultSubcommand: ListCommand.self
    )
}
