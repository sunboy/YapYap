// TableFormatter.swift
// YapYapBench — Markdown comparison table for terminal output
import Foundation

struct TableFormatter {

    /// Print a markdown comparison table to stderr for quick visual review.
    static func printTable(_ result: BenchmarkResult) {
        guard !result.recordings.isEmpty else {
            FileHandle.standardError.write("No results to display.\n".data(using: .utf8)!)
            return
        }

        let allRuns = result.recordings.flatMap { $0.runs }
        guard !allRuns.isEmpty else {
            FileHandle.standardError.write("No LLM runs to display.\n".data(using: .utf8)!)
            return
        }

        // Header
        let header = "| File | Model | Context | Level | Final Output | Total ms | tok/s | Valid |"
        let separator = "|------|-------|---------|-------|-------------|----------|-------|-------|"

        var lines: [String] = [header, separator]

        for recording in result.recordings {
            let fileName = URL(fileURLWithPath: recording.file).lastPathComponent
            for run in recording.runs {
                let output = truncate(run.output.final_, to: 40)
                let valid = run.validation.isValid ? "yes" : "NO"
                let line = "| \(pad(fileName, 12)) | \(pad(run.llmModelId, 18)) | \(pad(run.context.category, 15)) | \(pad(run.cleanupLevel, 6)) | \(pad(output, 40)) | \(run.timing.totalLLMMs) | \(String(format: "%.0f", run.tokens.tokensPerSecond)) | \(valid) |"
                lines.append(line)
            }
        }

        // Summary
        lines.append("")
        lines.append("### Summary")
        lines.append("")
        lines.append("| Model | Avg Total ms | Avg tok/s | Pass Rate |")
        lines.append("|-------|-------------|-----------|-----------|")
        for entry in result.summary.modelComparison {
            let line = "| \(pad(entry.modelId, 18)) | \(entry.avgTotalMs) | \(String(format: "%.0f", entry.avgTokPerSec)) | \(String(format: "%.0f%%", entry.validationPassRate * 100)) |"
            lines.append(line)
        }

        let tableOutput = lines.joined(separator: "\n") + "\n"
        FileHandle.standardError.write(tableOutput.data(using: .utf8)!)
    }

    private static func truncate(_ text: String, to maxLen: Int) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
        if cleaned.count <= maxLen { return cleaned }
        return String(cleaned.prefix(maxLen - 3)) + "..."
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        if text.count >= width { return String(text.prefix(width)) }
        return text + String(repeating: " ", count: width - text.count)
    }
}
