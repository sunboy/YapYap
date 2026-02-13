// AppContextDetectorTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class AppContextDetectorTests: XCTestCase {

    // MARK: - App Category

    func testAppCategoryCaseCount() {
        XCTAssertEqual(AppCategory.allCases.count, 8)
    }

    func testAppCategoryDisplayNames() {
        XCTAssertEqual(AppCategory.personalMessaging.displayName, "Personal Messaging")
        XCTAssertEqual(AppCategory.workMessaging.displayName, "Work Messaging")
        XCTAssertEqual(AppCategory.email.displayName, "Email")
        XCTAssertEqual(AppCategory.codeEditor.displayName, "Code Editor")
        XCTAssertEqual(AppCategory.browser.displayName, "Browser")
        XCTAssertEqual(AppCategory.documents.displayName, "Documents")
        XCTAssertEqual(AppCategory.aiChat.displayName, "AI Chat")
        XCTAssertEqual(AppCategory.other.displayName, "Other")
    }

    func testAppCategoryIcons() {
        for category in AppCategory.allCases {
            XCTAssertFalse(category.icon.isEmpty, "\(category) should have an icon")
        }
    }

    func testAppCategoryExampleApps() {
        for category in AppCategory.allCases {
            XCTAssertFalse(category.exampleApps.isEmpty, "\(category) should have example apps")
        }
    }

    func testAppCategoryAvailableStyles() {
        // Personal messaging should include veryCasual
        XCTAssertTrue(AppCategory.personalMessaging.availableStyles.contains(.veryCasual))

        // All categories should have at least 2 styles
        for category in AppCategory.allCases {
            XCTAssertGreaterThanOrEqual(category.availableStyles.count, 2)
        }

        // Code editor should NOT have veryCasual
        XCTAssertFalse(AppCategory.codeEditor.availableStyles.contains(.veryCasual))
    }

    // MARK: - Output Style

    func testOutputStyleCaseCount() {
        XCTAssertEqual(OutputStyle.allCases.count, 4)
    }

    func testOutputStyleDisplayNames() {
        XCTAssertEqual(OutputStyle.veryCasual.displayName, "Very Casual")
        XCTAssertEqual(OutputStyle.casual.displayName, "Casual")
        XCTAssertEqual(OutputStyle.excited.displayName, "Excited")
        XCTAssertEqual(OutputStyle.formal.displayName, "Formal")
    }

    func testOutputStylePreviewText() {
        for style in OutputStyle.allCases {
            XCTAssertFalse(style.previewText.isEmpty, "\(style) should have preview text")
        }
    }

    // MARK: - Style Settings

    func testDefaultStyleSettings() {
        let settings = StyleSettings()
        XCTAssertEqual(settings.personalMessaging, .casual)
        XCTAssertEqual(settings.email, .formal)
        XCTAssertEqual(settings.codeEditor, .formal)
        XCTAssertEqual(settings.documents, .formal)
        XCTAssertEqual(settings.aiChat, .casual)
        XCTAssertTrue(settings.ideVariableRecognition)
        XCTAssertTrue(settings.ideFileTagging)
    }

    func testStyleForCategory() {
        let settings = StyleSettings()
        XCTAssertEqual(settings.styleFor(.email), .formal)
        XCTAssertEqual(settings.styleFor(.personalMessaging), .casual)
    }

    func testCustomStyleOverride() {
        var settings = StyleSettings()
        settings.email = .casual
        XCTAssertEqual(settings.styleFor(.email), .casual)
    }
}
