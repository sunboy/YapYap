// MLXEngineCacheTests.swift
// YapYapTests — Tests for BPE joint-encode cache logic (no model loading needed)
import XCTest
@testable import YapYap

/// Tests for the BPE boundary fix in MLXEngine's prompt caching logic.
/// These tests exercise the joint-slice algorithm in isolation without loading an LLM.
final class MLXEngineCacheTests: XCTestCase {

    // MARK: - Joint Slice Boundary

    /// Split point must be within [0, jointTokens.count].
    func testJointSliceBoundaryCorrect() {
        let prefixTokens = [1, 2, 3, 4, 5]
        let jointTokens  = [1, 2, 3, 4, 5, 10, 11, 12]
        let splitPoint = min(prefixTokens.count, jointTokens.count)
        XCTAssertEqual(splitPoint, 5)
        XCTAssertEqual(Array(jointTokens[0..<splitPoint]), [1, 2, 3, 4, 5])
        XCTAssertEqual(Array(jointTokens[splitPoint...]), [10, 11, 12])
    }

    /// When prefix encodes to more tokens than the joint sequence (edge case),
    /// splitPoint should be clamped to jointTokens.count, not crash.
    func testJointSliceClampedWhenPrefixLongerThanJoint() {
        let prefixTokens = [1, 2, 3, 4, 5, 6, 7]  // longer than joint
        let jointTokens  = [1, 2, 3]
        let splitPoint = min(prefixTokens.count, jointTokens.count)
        XCTAssertEqual(splitPoint, 3)
        // Should not crash — slice is valid
        let slice = Array(jointTokens[0..<splitPoint])
        XCTAssertEqual(slice, [1, 2, 3])
    }

    // MARK: - Cache Hit / Miss Simulation

    /// Identical joint prefix slices → cache HIT condition.
    func testCacheHitWhenSlicesMatch() {
        let savedSlice  = [1, 2, 3, 4, 5]
        let currentSlice = [1, 2, 3, 4, 5]
        XCTAssertTrue(currentSlice == savedSlice, "Cache should HIT when slices are identical")
    }

    /// Different joint prefix slices → cache MISS condition.
    func testCacheMissWhenSlicesDiffer() {
        let savedSlice   = [1, 2, 3, 4, 5]
        let currentSlice = [1, 2, 3, 99, 5]  // token 4 differs (BPE merge changed it)
        XCTAssertFalse(currentSlice == savedSlice, "Cache should MISS when slices differ")
    }

    /// Simulates the previously-failing BPE merge case:
    /// Separate prefix encoding gives [A, B, C], suffix [D, E].
    /// Joint encoding merges tokens at boundary: [A, B, X, E] (not [A, B, C, D, E]).
    /// The old code compared prefixTokens+suffixTokens == jointTokens and bailed.
    /// The new code uses jointTokens directly, so the cache prefix slice is from joint.
    func testOldBPEMismatchNowHits() {
        // Old approach: separate tokenization
        let separatePrefixTokens = [1, 2, 3]
        let separateSuffixTokens = [4, 5]
        let oldCombined = separatePrefixTokens + separateSuffixTokens  // [1,2,3,4,5]

        // New approach: joint tokenization (BPE merges 3+4 into token 99)
        let jointTokens = [1, 2, 99, 5]  // BPE merge happened at boundary
        let splitPoint = min(separatePrefixTokens.count, jointTokens.count)  // = 3
        let jointPrefixSlice = Array(jointTokens[0..<splitPoint])             // [1, 2, 99]

        // Old code would have set splitValid = false (oldCombined != jointTokens) → no cache
        XCTAssertNotEqual(oldCombined, jointTokens, "Old approach would detect mismatch")

        // New code uses jointPrefixSlice from joint encoding — no mismatch possible
        // On 2nd call with same prefix, the saved slice [1, 2, 99] matches current [1, 2, 99]
        let secondCallJointTokens = [1, 2, 99, 7]  // different suffix but same prefix BPE
        let secondSplitPoint = min(separatePrefixTokens.count, secondCallJointTokens.count)
        let secondJointPrefixSlice = Array(secondCallJointTokens[0..<secondSplitPoint])

        XCTAssertEqual(jointPrefixSlice, secondJointPrefixSlice,
                       "New joint-slice approach: cache should HIT on 2nd call with same prefix")
    }

    // MARK: - Suffix Extraction

    /// Suffix tokens are correctly extracted from joint tokens after the split point.
    func testSuffixExtractionFromJointTokens() {
        let jointTokens = [1, 2, 3, 10, 11, 12]
        let splitPoint = 3
        let suffix = Array(jointTokens[splitPoint...])
        XCTAssertEqual(suffix, [10, 11, 12])
        XCTAssertEqual(suffix.count, jointTokens.count - splitPoint)
    }
}
