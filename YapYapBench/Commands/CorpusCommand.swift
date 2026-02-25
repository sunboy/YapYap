// CorpusCommand.swift
// YapYapBench — Run hardcoded test corpus through all models, score, compare, report
import ArgumentParser
import Foundation
import MLX

struct CorpusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "corpus",
        abstract: "Run the test corpus through all models × contexts × levels with automated scoring."
    )

    @Option(name: .long, help: "Comma-separated LLM model IDs, or 'all' (default: all).")
    var llmModels: String = "all"

    @Option(name: .long, help: "Comma-separated contexts, or 'all' (default: all).")
    var contexts: String = "all"

    @Option(name: .long, help: "Comma-separated cleanup levels, or 'all' (default: all).")
    var cleanupLevels: String = "all"

    @Flag(name: .long, help: "Enable experimental prompts.")
    var experimental: Bool = false

    @Option(name: .shortAndLong, help: "Output JSON to file.")
    var output: String?

    @Flag(name: .long, help: "Print scored report table to stderr.")
    var table: Bool = false

    @Option(name: .long, help: "Compare against a previous result JSON file.")
    var compare: String?

    @Flag(name: .long, help: "Keep model weights on disk after testing (default: delete).")
    var keepModels: Bool = false

    func run() async throws {
        let llmModelIds = parseLLMModels(llmModels)
        let contextList = ContextFactory.parseContexts(contexts)
        let levels = ContextFactory.parseCleanupLevels(cleanupLevels)
        let corpus = TestCorpus.entries

        log("Corpus benchmark starting")
        log("  Corpus entries: \(corpus.count)")
        log("  Models: \(llmModelIds.joined(separator: ", "))")
        log("  Contexts: \(contextList.joined(separator: ", "))")
        log("  Levels: \(levels.map(\.rawValue).joined(separator: ", "))")
        log("  Total runs: \(corpus.count * llmModelIds.count * contextList.count * levels.count)")

        let llmRunner = BenchmarkLLMRunner()
        var allRuns: [CorpusRunResult] = []

        for (modelIndex, llmModelId) in llmModelIds.enumerated() {
            guard let modelInfo = LLMModelRegistry.model(for: llmModelId) else {
                log("WARNING: Unknown model '\(llmModelId)', skipping")
                continue
            }

            log("\n=== [\(modelIndex + 1)/\(llmModelIds.count)] Model: \(llmModelId) (\(modelInfo.family.rawValue), \(modelInfo.sizeDescription)) ===")

            // Load model
            log("Downloading/loading model...")
            do {
                try await llmRunner.loadModel(id: llmModelId) { progress in
                    let pct = Int(progress * 100)
                    if pct % 25 == 0 { self.log("  Loading: \(pct)%") }
                }
                log("Model loaded.")
            } catch {
                log("ERROR: Failed to load model '\(llmModelId)': \(error.localizedDescription)")
                log("  Skipping this model and continuing...")
                continue
            }

            var modelRuns: [CorpusRunResult] = []

            // Run all corpus entries against this model
            for (entryIndex, entry) in corpus.enumerated() {
                for contextName in contextList {
                    let appContext = ContextFactory.makeAppContext(for: contextName)

                    for level in levels {
                        let cleanupContext = ContextFactory.makeCleanupContext(
                            appContext: appContext,
                            cleanupLevel: level,
                            experimentalPrompts: experimental
                        )

                        let prompt = llmRunner.getPrompt(rawText: entry.rawText, context: cleanupContext)

                        do {
                            let metrics = try await llmRunner.run(rawText: entry.rawText, context: cleanupContext)

                            // Post-processing pipeline
                            let fmtStart = Date()
                            let afterFormatter = OutputFormatter.format(metrics.sanitizedOutput, for: appContext)
                            let fmtMs = Int(Date().timeIntervalSince(fmtStart) * 1000)

                            let filterStart = Date()
                            let afterFilter = cleanupContext.removeFillers
                                ? FillerFilter.removeFillers(from: afterFormatter, aggressive: level == .heavy)
                                : afterFormatter
                            let filterMs = Int(Date().timeIntervalSince(filterStart) * 1000)

                            let finalOutput = afterFilter

                            // Validation
                            let overlapRatio = computeOverlap(input: entry.rawText, output: finalOutput)
                            let isValid = !finalOutput.isEmpty && overlapRatio > 0.2

                            // Quality scoring
                            let scoring = QualityScorer.score(
                                entry: entry,
                                rawInput: entry.rawText,
                                finalOutput: finalOutput,
                                cleanupLevel: level.rawValue,
                                contextCategory: appContext.category.rawValue
                            )

                            let sizeLabel: String
                            switch modelInfo.size {
                            case .small: sizeLabel = "small"
                            case .medium: sizeLabel = "medium"
                            case .large: sizeLabel = "large"
                            }

                            let run = CorpusRunResult(
                                corpusId: entry.id,
                                corpusCategory: entry.category,
                                llmModelId: llmModelId,
                                llmModelFamily: modelInfo.family.rawValue,
                                llmModelSize: sizeLabel,
                                context: ContextInfo(category: appContext.category.rawValue, appName: appContext.appName),
                                cleanupLevel: level.rawValue,
                                experimentalPrompts: experimental,
                                prompt: PromptInfo(system: prompt.system, user: prompt.user),
                                rawInput: entry.rawText,
                                output: OutputStages(
                                    rawLLM: metrics.rawOutput,
                                    afterSanitization: metrics.sanitizedOutput,
                                    afterOutputFormatter: afterFormatter,
                                    afterFillerFilter: afterFilter,
                                    final_: finalOutput
                                ),
                                timing: TimingInfo(
                                    prefillMs: metrics.prefillMs,
                                    generationMs: metrics.generationMs,
                                    totalLLMMs: metrics.totalMs,
                                    outputFormatterMs: fmtMs,
                                    fillerFilterMs: filterMs
                                ),
                                tokens: TokenInfo(
                                    promptTokens: metrics.promptTokens,
                                    generationTokens: metrics.generationTokens,
                                    tokensPerSecond: metrics.tokensPerSecond
                                ),
                                validation: ValidationInfo(isValid: isValid, overlapRatio: overlapRatio),
                                scoring: scoring
                            )
                            modelRuns.append(run)

                            // Progress log (compact)
                            let scoreStr = String(format: "%.0f%%", scoring.score * 100)
                            let status = scoring.passed ? "PASS" : "FAIL"
                            if !scoring.passed || entryIndex % 10 == 0 {
                                log("  [\(entryIndex + 1)/\(corpus.count)] \(entry.id) × \(contextName) × \(level.rawValue) → \(status) (\(scoreStr)) \(metrics.totalMs)ms")
                            }
                        } catch {
                            log("  ERROR: \(entry.id) × \(contextName) × \(level.rawValue): \(error.localizedDescription)")
                        }
                    }
                }
            }

            allRuns.append(contentsOf: modelRuns)

            // Summary for this model
            let passCount = modelRuns.filter(\.scoring.passed).count
            let avgScore = modelRuns.isEmpty ? 0 : modelRuns.map(\.scoring.score).reduce(0, +) / Double(modelRuns.count)
            log("\n  Model \(llmModelId): \(passCount)/\(modelRuns.count) passed (avg score: \(String(format: "%.0f%%", avgScore * 100)))")

            // Unload model
            llmRunner.unloadModel()
            GPU.set(cacheLimit: 0)
            try? await Task.sleep(for: .milliseconds(500))
            GPU.set(cacheLimit: GPU.cacheLimit)

            // Delete model weights from disk
            if !keepModels {
                deleteModelWeights(modelInfo: modelInfo)
            }
        }

        // Build result
        let result = CorpusBenchmarkResult(runs: allRuns)

        // Output JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let jsonData = try? encoder.encode(result),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            log("ERROR: Failed to encode results")
            return
        }

        if let outputPath = output {
            try jsonString.write(toFile: outputPath, atomically: true, encoding: .utf8)
            log("\nResults written to \(outputPath)")
        } else {
            print(jsonString)
        }

        // Print scored report table
        if table {
            printScoredReport(result)
        }

        // Comparison
        if let comparePath = compare {
            do {
                let previousData = try Data(contentsOf: URL(fileURLWithPath: comparePath))
                let report = try ComparisonReporter.compare(previous: previousData, current: jsonData)
                ComparisonReporter.printReport(report)
            } catch {
                log("ERROR: Failed to load comparison file: \(error.localizedDescription)")
            }
        }

        log("\nCorpus benchmark complete. \(result.totalRuns) total runs across \(result.modelSummaries.count) models.")
    }

    // MARK: - Model Deletion

    private func deleteModelWeights(modelInfo: LLMModelInfo) {
        let hfCacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
        let repoName = "models--" + modelInfo.huggingFaceId.replacingOccurrences(of: "/", with: "--")
        let modelDir = hfCacheDir.appendingPathComponent(repoName)

        if FileManager.default.fileExists(atPath: modelDir.path) {
            do {
                // Get size before deletion
                let size = try FileManager.default.allocatedSizeOfDirectory(at: modelDir)
                try FileManager.default.removeItem(at: modelDir)
                let sizeMB = size / (1024 * 1024)
                log("  Deleted model weights: \(modelInfo.id) (freed \(sizeMB)MB)")
            } catch {
                log("  WARNING: Failed to delete model \(modelInfo.id): \(error.localizedDescription)")
            }
        } else {
            log("  Model directory not found for deletion: \(modelDir.path)")
        }
    }

    // MARK: - Scored Report

    private func printScoredReport(_ result: CorpusBenchmarkResult) {
        var out = "\n### Corpus Benchmark Results\n\n"

        // Per-model detail (only show failures and every 10th entry)
        for summary in result.modelSummaries {
            out += "### \(summary.modelId) — \(pct(summary.passRate)) pass rate (avg score: \(pct(summary.avgScore)))\n"

            let modelRuns = result.runs.filter { $0.llmModelId == summary.modelId }
            let failures = modelRuns.filter { !$0.scoring.passed }

            if !failures.isEmpty {
                out += "| Entry | Context | Level | Score | Failed Checks | Output |\n"
                out += "|-------|---------|-------|-------|---------------|--------|\n"
                for run in failures.prefix(20) {
                    let output = String(run.output.final_.prefix(50)).replacingOccurrences(of: "\n", with: " ")
                    out += "| \(run.corpusId) | \(run.context.category) | \(run.cleanupLevel) | \(pct(run.scoring.score)) | \(run.scoring.failedChecks.joined(separator: ", ")) | \(output) |\n"
                }
                if failures.count > 20 {
                    out += "... and \(failures.count - 20) more failures\n"
                }
            } else {
                out += "All runs passed.\n"
            }

            if !summary.failureBreakdown.isEmpty {
                out += "\nFailure breakdown:\n"
                for (check, count) in summary.failureBreakdown.sorted(by: { $0.value > $1.value }) {
                    out += "  \(check): \(count)\n"
                }
            }
            out += "\n"
        }

        // Overall summary table
        out += "### Overall Summary\n\n"
        out += "| Model | Runs | Avg Score | Pass Rate | Avg ms | Avg tok/s | Top Failure |\n"
        out += "|-------|------|-----------|-----------|--------|-----------|-------------|\n"
        for s in result.modelSummaries {
            let topFailure = s.failureBreakdown.max(by: { $0.value < $1.value })?.key ?? "—"
            out += "| \(s.modelId) | \(s.totalRuns) | \(pct(s.avgScore)) | \(pct(s.passRate)) | \(s.avgTotalMs) | \(String(format: "%.0f", s.avgTokPerSec)) | \(topFailure) |\n"
        }
        out += "\n"

        FileHandle.standardError.write(out.data(using: .utf8)!)
    }

    // MARK: - Helpers

    private func computeOverlap(input: String, output: String) -> Double {
        let inputWords = Set(input.lowercased().split(separator: " ").map(String.init))
        let outputWords = Set(output.lowercased().split(separator: " ").map(String.init))
        guard !inputWords.isEmpty else { return 0 }
        return Double(inputWords.intersection(outputWords).count) / Double(inputWords.count)
    }

    private func pct(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func log(_ message: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let ts = f.string(from: Date())
        FileHandle.standardError.write("[\(ts)] \(message)\n".data(using: .utf8)!)
    }
}

// MARK: - FileManager directory size helper

extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> UInt64 {
        var size: UInt64 = 0
        let enumerator = self.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            size += UInt64(resourceValues.fileSize ?? 0)
        }
        return size
    }
}
