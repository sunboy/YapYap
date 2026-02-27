// AppContextDetectorTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class AppContextDetectorTests: XCTestCase {

    // MARK: - App Category

    func testAppCategoryCaseCount() {
        XCTAssertEqual(AppCategory.allCases.count, 11)
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

    // MARK: - Layer 2: Heuristics

    func testHeuristicEmail() {
        XCTAssertEqual(categoryFromHeuristics("com.newco.mail", "New Mail"), .email)
    }

    func testHeuristicTerminal() {
        XCTAssertEqual(categoryFromHeuristics("com.example.myterminal", "My Terminal"), .terminal)
    }

    func testHeuristicCodeEditor() {
        XCTAssertEqual(categoryFromHeuristics("com.example.codeeditor", "Code Editor"), .codeEditor)
    }

    func testHeuristicNotes() {
        XCTAssertEqual(categoryFromHeuristics("com.example.bear", "Bear"), .notes)
    }

    func testHeuristicWorkMessaging() {
        XCTAssertEqual(categoryFromHeuristics("com.newco.slack-clone", "Slack Clone"), .workMessaging)
    }

    func testHeuristicReturnsNil() {
        XCTAssertNil(categoryFromHeuristics("com.unknown.app", "Foo App"))
    }

    // MARK: - Layer 3: Window Title

    func testWindowTitleInbox() {
        XCTAssertEqual(categoryFromWindowTitle("Inbox — Fastmail", nil), .email)
    }

    func testWindowTitleNewMessage() {
        XCTAssertEqual(categoryFromWindowTitle("New Message", nil), .email)
    }

    func testWindowTitleSlack() {
        XCTAssertEqual(categoryFromWindowTitle("general — Slack", nil), .workMessaging)
    }

    func testWindowTitleNilReturnsNil() {
        XCTAssertNil(categoryFromWindowTitle(nil, nil))
    }

    func testFocusedTextShellPrompt() {
        XCTAssertEqual(categoryFromWindowTitle(nil, "output\n$ "), .terminal)
    }

    func testFocusedTextPythonRepl() {
        XCTAssertEqual(categoryFromWindowTitle(nil, ">>> "), .terminal)
    }

    // MARK: - SeenAppInfo Codability

    func testSeenAppInfoRoundTrip() throws {
        let info = SeenAppInfo(appName: "Test", autoDetectedCategory: .notes, lastSeen: Date(timeIntervalSince1970: 1000))
        let decoded = try JSONDecoder().decode(SeenAppInfo.self, from: try JSONEncoder().encode(info))
        XCTAssertEqual(decoded.appName, "Test")
        XCTAssertEqual(decoded.autoDetectedCategory, .notes)
    }

    func testStyleSettingsSeenAppsRoundTrip() throws {
        var s = StyleSettings()
        s.seenApps["com.test.app"] = SeenAppInfo(appName: "Test", autoDetectedCategory: .email, lastSeen: Date())
        let decoded = try JSONDecoder().decode(StyleSettings.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(decoded.seenApps["com.test.app"]?.autoDetectedCategory, .email)
    }

    func testAppCategoryOverridesRoundTrip() throws {
        var s = StyleSettings()
        s.appCategoryOverrides["com.test.app"] = .terminal
        let decoded = try JSONDecoder().decode(StyleSettings.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(decoded.appCategoryOverrides["com.test.app"], .terminal)
    }

    // MARK: - Test helpers

    private func categoryFromHeuristics(_ bundleId: String, _ appName: String) -> AppCategory? {
        AppContextDetector.categoryFromHeuristics(bundleId: bundleId, appName: appName)
    }

    private func categoryFromWindowTitle(_ title: String?, _ focused: String?) -> AppCategory? {
        AppContextDetector.categoryFromWindowTitle(title, focusedText: focused)
    }
}
