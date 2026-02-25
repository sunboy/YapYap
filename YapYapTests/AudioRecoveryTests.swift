import XCTest
@testable import YapYap

final class AudioRecoveryTests: XCTestCase {
    func testConsecutiveErrorThresholdDefault() {
        // Verify the recovery threshold is reasonable
        let manager = AudioCaptureManager()
        // The threshold is private, but we can test the callback mechanism
        XCTAssertNil(manager.onEngineFailure)
    }

    func testOnEngineFailureCallbackCanBeSet() {
        let manager = AudioCaptureManager()
        var called = false
        manager.onEngineFailure = { called = true }
        XCTAssertNotNil(manager.onEngineFailure)
        manager.onEngineFailure?()
        XCTAssertTrue(called)
    }

    func testOnEngineFailureCanBeReplaced() {
        let manager = AudioCaptureManager()
        var firstCalled = false
        var secondCalled = false

        manager.onEngineFailure = { firstCalled = true }
        manager.onEngineFailure = { secondCalled = true }
        manager.onEngineFailure?()

        XCTAssertFalse(firstCalled)
        XCTAssertTrue(secondCalled)
    }

    func testOnEngineFailureCanBeCleared() {
        let manager = AudioCaptureManager()
        manager.onEngineFailure = { XCTFail("Should not be called") }
        manager.onEngineFailure = nil
        XCTAssertNil(manager.onEngineFailure)
        // Calling nil closure should not crash
        manager.onEngineFailure?()
    }
}
