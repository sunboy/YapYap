// MachineProfileTests.swift
// YapYapTests — Tests for hardware detection and model recommendations
import XCTest
@testable import YapYap

final class MachineProfileTests: XCTestCase {

    // MARK: - Tier Classification

    func testLowTierFor8GB() {
        let tier = MachineProfile.classifyTier(ramBytes: 8 * 1024 * 1024 * 1024, cores: 8)
        XCTAssertEqual(tier, .low)
    }

    func testLowTierFor4GB() {
        let tier = MachineProfile.classifyTier(ramBytes: 4 * 1024 * 1024 * 1024, cores: 4)
        XCTAssertEqual(tier, .low)
    }

    func testMidTierFor16GB() {
        let tier = MachineProfile.classifyTier(ramBytes: 16 * 1024 * 1024 * 1024, cores: 10)
        XCTAssertEqual(tier, .mid)
    }

    func testMidTierFor24GB() {
        let tier = MachineProfile.classifyTier(ramBytes: 24 * 1024 * 1024 * 1024, cores: 12)
        XCTAssertEqual(tier, .mid)
    }

    func testHighTierFor32GB() {
        let tier = MachineProfile.classifyTier(ramBytes: 32 * 1024 * 1024 * 1024, cores: 10)
        XCTAssertEqual(tier, .high)
    }

    func testHighTierFor64GB() {
        let tier = MachineProfile.classifyTier(ramBytes: 64 * 1024 * 1024 * 1024, cores: 20)
        XCTAssertEqual(tier, .high)
    }

    func testHighTierFor128GB() {
        let tier = MachineProfile.classifyTier(ramBytes: 128 * 1024 * 1024 * 1024, cores: 24)
        XCTAssertEqual(tier, .high)
    }

    // MARK: - Detection

    func testDetectReturnsValidProfile() {
        let profile = MachineProfile.detect()
        XCTAssertGreaterThan(profile.totalRAMBytes, 0)
        XCTAssertGreaterThan(profile.cpuCoreCount, 0)
    }

    func testDetectTierIsConsistent() {
        let profile = MachineProfile.detect()
        let expectedTier = MachineProfile.classifyTier(ramBytes: profile.totalRAMBytes, cores: profile.cpuCoreCount)
        XCTAssertEqual(profile.tier, expectedTier)
    }

    // MARK: - Model Recommendations

    func testLowTierRecommendsSmallMLXModel() {
        let profile = MachineProfile(totalRAMBytes: 8 * 1024 * 1024 * 1024, cpuCoreCount: 8, tier: .low)
        let modelId = profile.recommendedMLXModelId
        let model = LLMModelRegistry.model(for: modelId)
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.size, .small, "Low tier should recommend a small model")
    }

    func testMidTierRecommendsMediumMLXModel() {
        let profile = MachineProfile(totalRAMBytes: 16 * 1024 * 1024 * 1024, cpuCoreCount: 10, tier: .mid)
        let modelId = profile.recommendedMLXModelId
        let model = LLMModelRegistry.model(for: modelId)
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.size, .medium, "Mid tier should recommend a medium model")
    }

    func testHighTierRecommendsLargeMLXModel() {
        let profile = MachineProfile(totalRAMBytes: 32 * 1024 * 1024 * 1024, cpuCoreCount: 10, tier: .high)
        let modelId = profile.recommendedMLXModelId
        let model = LLMModelRegistry.model(for: modelId)
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.size, .large, "High tier should recommend a large model")
    }

    func testOllamaRecommendationExistsForAllTiers() {
        for tier in [MachineTier.low, .mid, .high] {
            let profile = MachineProfile(totalRAMBytes: 8 * 1024 * 1024 * 1024, cpuCoreCount: 8, tier: tier)
            XCTAssertFalse(profile.recommendedOllamaModelName.isEmpty, "Tier \(tier) should have an Ollama recommendation")
        }
    }

    func testGGUFRecommendationExistsForAllTiers() {
        for tier in [MachineTier.low, .mid, .high] {
            let profile = MachineProfile(totalRAMBytes: 8 * 1024 * 1024 * 1024, cpuCoreCount: 8, tier: tier)
            let ggufId = profile.recommendedGGUFModelId
            XCTAssertFalse(ggufId.isEmpty, "Tier \(tier) should have a GGUF recommendation")
            XCTAssertTrue(ggufId.hasPrefix("gguf-"), "GGUF recommendation should have gguf- prefix")
            XCTAssertNotNil(GGUFModelRegistry.model(for: ggufId), "GGUF recommendation \(ggufId) should exist in registry")
        }
    }

    // MARK: - Display Strings

    func testRamDescriptionNotEmpty() {
        let profile = MachineProfile.detect()
        XCTAssertFalse(profile.ramDescription.isEmpty)
        XCTAssertTrue(profile.ramDescription.hasSuffix("GB"))
    }

    func testTierDescriptionNotEmpty() {
        let profile = MachineProfile.detect()
        XCTAssertFalse(profile.tierDescription.isEmpty)
        XCTAssertTrue(profile.tierDescription.contains("RAM"))
    }

    func testTierDescriptionLabels() {
        let low = MachineProfile(totalRAMBytes: 8 * 1024 * 1024 * 1024, cpuCoreCount: 8, tier: .low)
        XCTAssertTrue(low.tierDescription.contains("Basic"))

        let mid = MachineProfile(totalRAMBytes: 16 * 1024 * 1024 * 1024, cpuCoreCount: 10, tier: .mid)
        XCTAssertTrue(mid.tierDescription.contains("Capable"))

        let high = MachineProfile(totalRAMBytes: 32 * 1024 * 1024 * 1024, cpuCoreCount: 10, tier: .high)
        XCTAssertTrue(high.tierDescription.contains("High-end"))
    }
}
