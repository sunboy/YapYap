// BenchmarkResult.swift
// YapYapBench — Codable JSON schema structs for benchmark output
import Foundation

struct BenchmarkResult: Codable {
    let benchmarkVersion: String
    let timestamp: String
    let machine: MachineInfo
    let sttConfig: STTConfig?
    let recordings: [RecordingResult]
    let summary: BenchmarkSummary

    init(
        sttConfig: STTConfig?,
        recordings: [RecordingResult]
    ) {
        self.benchmarkVersion = "1.0"
        self.timestamp = ISO8601DateFormatter().string(from: Date())
        self.machine = MachineInfo.current()
        self.sttConfig = sttConfig
        self.recordings = recordings
        self.summary = BenchmarkSummary(from: recordings)
    }
}

struct MachineInfo: Codable {
    let chip: String
    let memoryGB: Int
    let osVersion: String

    static func current() -> MachineInfo {
        let chip = getMachineChip()
        let memoryGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        return MachineInfo(chip: chip, memoryGB: memoryGB, osVersion: osVersion)
    }

    private static func getMachineChip() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let cpuBrand = String(cString: brand)
        if !cpuBrand.isEmpty { return cpuBrand }
        // Fallback for Apple Silicon
        var chipSize = 0
        sysctlbyname("hw.chip", nil, &chipSize, nil, 0)
        if chipSize > 0 {
            var chip = [CChar](repeating: 0, count: chipSize)
            sysctlbyname("hw.chip", &chip, &chipSize, nil, 0)
            return String(cString: chip)
        }
        return "Apple Silicon"
    }
}

struct STTConfig: Codable {
    let modelId: String
    let language: String
}

struct RecordingResult: Codable {
    let file: String
    let durationSeconds: Double?
    let stt: STTResult?
    let runs: [LLMRunResult]
}

struct STTResult: Codable {
    let transcript: String
    let latencyMs: Int
    let language: String?
}

struct LLMRunResult: Codable {
    let llmModelId: String
    let llmModelFamily: String
    let llmModelSize: String
    let context: ContextInfo
    let cleanupLevel: String
    let experimentalPrompts: Bool
    let prompt: PromptInfo
    let output: OutputStages
    let timing: TimingInfo
    let tokens: TokenInfo
    let validation: ValidationInfo
}

struct ContextInfo: Codable {
    let category: String
    let appName: String
}

struct PromptInfo: Codable {
    let system: String
    let user: String
}

struct OutputStages: Codable {
    let rawLLM: String
    let afterSanitization: String
    let afterOutputFormatter: String
    let afterFillerFilter: String
    let final_: String

    enum CodingKeys: String, CodingKey {
        case rawLLM
        case afterSanitization
        case afterOutputFormatter
        case afterFillerFilter
        case final_ = "final"
    }
}

struct TimingInfo: Codable {
    let prefillMs: Int
    let generationMs: Int
    let totalLLMMs: Int
    let outputFormatterMs: Int
    let fillerFilterMs: Int
}

struct TokenInfo: Codable {
    let promptTokens: Int
    let generationTokens: Int
    let tokensPerSecond: Double
}

struct ValidationInfo: Codable {
    let isValid: Bool
    let overlapRatio: Double
}

struct BenchmarkSummary: Codable {
    let totalRecordings: Int
    let totalRuns: Int
    let modelComparison: [ModelComparisonEntry]

    init(from recordings: [RecordingResult]) {
        self.totalRecordings = recordings.count
        let allRuns = recordings.flatMap { $0.runs }
        self.totalRuns = allRuns.count

        // Group by model
        var byModel: [String: [LLMRunResult]] = [:]
        for run in allRuns {
            byModel[run.llmModelId, default: []].append(run)
        }

        self.modelComparison = byModel.map { modelId, runs in
            let avgTotal = runs.isEmpty ? 0 : runs.map(\.timing.totalLLMMs).reduce(0, +) / runs.count
            let avgTokPerSec = runs.isEmpty ? 0.0 : runs.map(\.tokens.tokensPerSecond).reduce(0, +) / Double(runs.count)
            let validCount = runs.filter(\.validation.isValid).count
            let passRate = runs.isEmpty ? 0.0 : Double(validCount) / Double(runs.count)
            return ModelComparisonEntry(
                modelId: modelId,
                avgTotalMs: avgTotal,
                avgTokPerSec: avgTokPerSec,
                validationPassRate: passRate
            )
        }.sorted(by: { $0.modelId < $1.modelId })
    }
}

struct ModelComparisonEntry: Codable {
    let modelId: String
    let avgTotalMs: Int
    let avgTokPerSec: Double
    let validationPassRate: Double
}
