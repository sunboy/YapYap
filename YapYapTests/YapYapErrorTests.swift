// YapYapErrorTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class YapYapErrorTests: XCTestCase {

    func testModelNotLoadedDescription() {
        let error = YapYapError.modelNotLoaded
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("model") || error.errorDescription!.contains("Model"))
    }

    func testModelDownloadFailedDescription() {
        let error = YapYapError.modelDownloadFailed("Network timeout")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Network timeout"))
    }

    func testMicrophonePermissionDescription() {
        let error = YapYapError.microphonePermissionDenied
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.lowercased().contains("microphone"))
    }

    func testAccessibilityPermissionDescription() {
        let error = YapYapError.accessibilityPermissionDenied
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.lowercased().contains("accessibility"))
    }

    func testNoAudioRecordedDescription() {
        let error = YapYapError.noAudioRecorded
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.lowercased().contains("speech") || error.errorDescription!.lowercased().contains("detected"))
    }

    func testAllErrorsHaveDescriptions() {
        let errors: [YapYapError] = [
            .modelNotLoaded,
            .modelDownloadFailed("test"),
            .microphonePermissionDenied,
            .accessibilityPermissionDenied,
            .audioCaptureFailed(NSError(domain: "", code: 0)),
            .transcriptionFailed(NSError(domain: "", code: 0)),
            .cleanupFailed(NSError(domain: "", code: 0)),
            .pasteFailed(NSError(domain: "", code: 0)),
            .noAudioRecorded,
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "\(error) description should not be empty")
        }
    }
}
