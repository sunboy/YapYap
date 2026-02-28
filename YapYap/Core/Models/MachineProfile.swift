// MachineProfile.swift
// YapYap — Detects hardware capabilities and recommends model defaults
import Foundation

/// Hardware capability tier used to select appropriate default models.
enum MachineTier: String, Codable {
    /// 8GB RAM, base M1/M2 — use small models (<=2B) to stay under memory budget
    case low
    /// 16GB RAM, M1 Pro/M2 Pro or better — can run medium models (3B-4B)
    case mid
    /// 32GB+ RAM, M1 Max/Ultra/M2 Max+ — can comfortably run large models (7B+)
    case high
}

struct MachineProfile {
    let totalRAMBytes: UInt64
    let cpuCoreCount: Int
    let tier: MachineTier

    /// Detect current machine capabilities
    static func detect() -> MachineProfile {
        let ram = ProcessInfo.processInfo.physicalMemory
        let cores = ProcessInfo.processInfo.processorCount
        let tier = classifyTier(ramBytes: ram, cores: cores)
        return MachineProfile(totalRAMBytes: ram, cpuCoreCount: cores, tier: tier)
    }

    /// Classify the machine into a capability tier
    static func classifyTier(ramBytes: UInt64, cores: Int) -> MachineTier {
        let ramGB = Double(ramBytes) / (1024 * 1024 * 1024)
        if ramGB >= 32 {
            return .high
        } else if ramGB >= 16 {
            return .mid
        } else {
            return .low
        }
    }

    /// Recommended MLX model ID for this machine's tier
    var recommendedMLXModelId: String {
        switch tier {
        case .low:
            // 8GB: use Qwen 1.5B — smallest multilingual option
            return "qwen-2.5-1.5b"
        case .mid:
            // 16GB: use Gemma 3 4B — best quality in medium tier
            return "gemma-3-4b"
        case .high:
            // 32GB+: use Qwen 7B — highest quality
            return "qwen-2.5-7b"
        }
    }

    /// Recommended Ollama model tag for this machine's tier
    var recommendedOllamaModelName: String {
        switch tier {
        case .low:
            return "qwen2.5:1.5b"
        case .mid:
            return "gemma3:4b"
        case .high:
            return "qwen2.5:7b"
        }
    }

    /// Human-readable RAM description
    var ramDescription: String {
        let gb = Double(totalRAMBytes) / (1024 * 1024 * 1024)
        return String(format: "%.0f GB", gb)
    }

    /// Human-readable tier description
    var tierDescription: String {
        switch tier {
        case .low: return "Basic (\(ramDescription) RAM)"
        case .mid: return "Capable (\(ramDescription) RAM)"
        case .high: return "High-end (\(ramDescription) RAM)"
        }
    }
}
