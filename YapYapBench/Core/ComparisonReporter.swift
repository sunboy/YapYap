// ComparisonReporter.swift
// YapYapBench — Compare two corpus benchmark runs and report regressions/improvements
import Foundation

struct ComparisonReporter {

    struct RunKey: Hashable {
        let corpusId: String
        let modelId: String
        let context: String
        let cleanupLevel: String
    }

    struct ScoreChange: Codable {
        let corpusId: String
        let modelId: String
        let context: String
        let cleanupLevel: String
        let previousScore: Double
        let currentScore: Double
        let delta: Double
        let newFailedChecks: [String]
    }

    struct ComparisonReport: Codable {
        let previousTimestamp: String
        let currentTimestamp: String
        let regressions: [ScoreChange]
        let improvements: [ScoreChange]
        let newFailures: Int
        let newPasses: Int
        let netChange: Int
        let previousOverallPassRate: Double
        let currentOverallPassRate: Double
    }

    /// Compare two CorpusBenchmarkResult JSONs and produce a report.
    static func compare(previous: Data, current: Data) throws -> ComparisonReport {
        let decoder = JSONDecoder()
        let prev = try decoder.decode(CorpusBenchmarkResult.self, from: previous)
        let curr = try decoder.decode(CorpusBenchmarkResult.self, from: current)

        // Build lookup maps
        var prevScores: [RunKey: (score: Double, passed: Bool, failedChecks: [String])] = [:]
        var currScores: [RunKey: (score: Double, passed: Bool, failedChecks: [String])] = [:]

        for run in prev.runs {
            let key = RunKey(corpusId: run.corpusId, modelId: run.llmModelId,
                           context: run.context.category, cleanupLevel: run.cleanupLevel)
            prevScores[key] = (run.scoring.score, run.scoring.passed, run.scoring.failedChecks)
        }

        for run in curr.runs {
            let key = RunKey(corpusId: run.corpusId, modelId: run.llmModelId,
                           context: run.context.category, cleanupLevel: run.cleanupLevel)
            currScores[key] = (run.scoring.score, run.scoring.passed, run.scoring.failedChecks)
        }

        // Find regressions and improvements
        var regressions: [ScoreChange] = []
        var improvements: [ScoreChange] = []
        var newFailures = 0
        var newPasses = 0

        let allKeys = Set(prevScores.keys).union(currScores.keys)
        for key in allKeys {
            guard let prevScore = prevScores[key], let currScore = currScores[key] else { continue }

            let delta = currScore.score - prevScore.score
            if delta < -0.05 {  // Score dropped by >5%
                regressions.append(ScoreChange(
                    corpusId: key.corpusId, modelId: key.modelId,
                    context: key.context, cleanupLevel: key.cleanupLevel,
                    previousScore: prevScore.score, currentScore: currScore.score,
                    delta: delta,
                    newFailedChecks: currScore.failedChecks.filter { !prevScore.failedChecks.contains($0) }
                ))
            } else if delta > 0.05 {  // Score improved by >5%
                improvements.append(ScoreChange(
                    corpusId: key.corpusId, modelId: key.modelId,
                    context: key.context, cleanupLevel: key.cleanupLevel,
                    previousScore: prevScore.score, currentScore: currScore.score,
                    delta: delta, newFailedChecks: []
                ))
            }

            if prevScore.passed && !currScore.passed { newFailures += 1 }
            if !prevScore.passed && currScore.passed { newPasses += 1 }
        }

        let prevPassRate = prevScores.isEmpty ? 0 : Double(prevScores.values.filter(\.passed).count) / Double(prevScores.count)
        let currPassRate = currScores.isEmpty ? 0 : Double(currScores.values.filter(\.passed).count) / Double(currScores.count)

        return ComparisonReport(
            previousTimestamp: prev.timestamp,
            currentTimestamp: curr.timestamp,
            regressions: regressions.sorted { $0.delta < $1.delta },
            improvements: improvements.sorted { $0.delta > $1.delta },
            newFailures: newFailures,
            newPasses: newPasses,
            netChange: newPasses - newFailures,
            previousOverallPassRate: prevPassRate,
            currentOverallPassRate: currPassRate
        )
    }

    /// Print comparison as a markdown table to stderr.
    static func printReport(_ report: ComparisonReport) {
        var out = ""

        out += "\n### Regression Comparison\n"
        out += "Previous: \(report.previousTimestamp)  →  Current: \(report.currentTimestamp)\n"
        out += "Pass rate: \(pct(report.previousOverallPassRate)) → \(pct(report.currentOverallPassRate))\n\n"

        if !report.regressions.isEmpty {
            out += "### Regressions (\(report.regressions.count))\n"
            out += "| Model | Corpus Entry | Context | Level | Was | Now | Delta | New Failures |\n"
            out += "|-------|-------------|---------|-------|-----|-----|-------|--------------|\n"
            for r in report.regressions {
                out += "| \(r.modelId) | \(r.corpusId) | \(r.context) | \(r.cleanupLevel) | \(pct(r.previousScore)) | \(pct(r.currentScore)) | \(String(format: "%+.0f%%", r.delta * 100)) | \(r.newFailedChecks.joined(separator: ", ")) |\n"
            }
            out += "\n"
        }

        if !report.improvements.isEmpty {
            out += "### Improvements (\(report.improvements.count))\n"
            out += "| Model | Corpus Entry | Context | Level | Was | Now | Delta |\n"
            out += "|-------|-------------|---------|-------|-----|-----|-------|\n"
            for r in report.improvements {
                out += "| \(r.modelId) | \(r.corpusId) | \(r.context) | \(r.cleanupLevel) | \(pct(r.previousScore)) | \(pct(r.currentScore)) | \(String(format: "%+.0f%%", r.delta * 100)) |\n"
            }
            out += "\n"
        }

        out += "**New Failures:** \(report.newFailures)  **New Passes:** \(report.newPasses)  **Net:** \(report.netChange >= 0 ? "+" : "")\(report.netChange)\n"

        FileHandle.standardError.write(out.data(using: .utf8)!)
    }

    private static func pct(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
