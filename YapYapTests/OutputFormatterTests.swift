// OutputFormatterTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class OutputFormatterTests: XCTestCase {

    // MARK: - File Tagging

    func testFileTaggingBasic() {
        let result = OutputFormatter.applyFileTagging("Look at main.swift for the implementation")
        XCTAssertTrue(result.contains("@main.swift"))
        XCTAssertFalse(result.contains("at main.swift"))
    }

    func testFileTaggingPython() {
        let result = OutputFormatter.applyFileTagging("Check at utils.py for helpers")
        XCTAssertTrue(result.contains("@utils.py"))
    }

    func testFileTaggingTypeScript() {
        let result = OutputFormatter.applyFileTagging("Update at App.tsx component")
        XCTAssertTrue(result.contains("@App.tsx"))
    }

    func testFileTaggingMultipleFiles() {
        let result = OutputFormatter.applyFileTagging("Look at main.swift and at config.json")
        XCTAssertTrue(result.contains("@main.swift"))
        XCTAssertTrue(result.contains("@config.json"))
    }

    func testFileTaggingIgnoresNonCodeExtensions() {
        let result = OutputFormatter.applyFileTagging("Look at file.pdf for details")
        XCTAssertFalse(result.contains("@file.pdf"))
        XCTAssertTrue(result.contains("at file.pdf"))
    }

    func testFileTaggingPreservesExistingAt() {
        let result = OutputFormatter.applyFileTagging("Contact us at support@email.com")
        // Should not break email addresses (email has @ already)
        XCTAssertTrue(result.contains("support@email.com") || result.contains("at support"))
    }

    // MARK: - Code Token Wrapping

    func testWrappsCamelCase() {
        let result = OutputFormatter.wrapCodeTokens("Update the getUserName function")
        XCTAssertTrue(result.contains("`getUserName`"))
    }

    func testWrappsSnakeCase() {
        let result = OutputFormatter.wrapCodeTokens("Check the user_name variable")
        XCTAssertTrue(result.contains("`user_name`"))
    }

    func testDoesNotWrapNormalWords() {
        let result = OutputFormatter.wrapCodeTokens("The meeting is tomorrow")
        XCTAssertFalse(result.contains("`"))
    }

    func testDoesNotDoubleWrapBackticks() {
        let result = OutputFormatter.wrapCodeTokens("Check `getUserName` already wrapped")
        // Should not produce ``getUserName``
        XCTAssertFalse(result.contains("``"))
    }

    // MARK: - Very Casual Formatting

    func testVeryCasualRemovesTrailingPeriod() {
        let result = OutputFormatter.applyVeryCasual("Hello there.")
        XCTAssertFalse(result.hasSuffix("."))
    }

    func testVeryCasualLowercasesFirst() {
        let result = OutputFormatter.applyVeryCasual("Hello there")
        XCTAssertTrue(result.hasPrefix("h"))
    }

    func testVeryCasualKeepsExclamation() {
        let result = OutputFormatter.applyVeryCasual("Hello there!")
        XCTAssertTrue(result.contains("!"))
    }

    func testVeryCasualKeepsQuestion() {
        let result = OutputFormatter.applyVeryCasual("Is it ready?")
        XCTAssertTrue(result.contains("?"))
    }

    func testVeryCasualMultipleLines() {
        let result = OutputFormatter.applyVeryCasual("Hello there.\nHow are you.")
        let lines = result.components(separatedBy: "\n")
        XCTAssertTrue(lines[0].first?.isLowercase ?? false)
        XCTAssertTrue(lines[1].first?.isLowercase ?? false)
    }

    // MARK: - Full Format Pipeline

    func testFormatForVeryCasualMessaging() {
        let ctx = AppContext(bundleId: "", appName: "Messages", category: .personalMessaging, style: .veryCasual, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let result = OutputFormatter.format("Hello there.", for: ctx)
        XCTAssertTrue(result.hasPrefix("h"))
        XCTAssertFalse(result.hasSuffix("."))
    }

    func testFormatForIDEChatAppliesFileTagging() {
        let ctx = AppContext(bundleId: "", appName: "Cursor", category: .codeEditor, style: .formal, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: true)
        let result = OutputFormatter.format("Look at main.swift", for: ctx)
        XCTAssertTrue(result.contains("@main.swift"))
    }

    func testFormatForCodeEditorWrapsTokens() {
        let ctx = AppContext(bundleId: "", appName: "VS Code", category: .codeEditor, style: .formal, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let result = OutputFormatter.format("Update getUserName function", for: ctx)
        XCTAssertTrue(result.contains("`getUserName`"))
    }

    func testFormatForEmailDoesNotApplyCasualFormatting() {
        let ctx = AppContext(bundleId: "", appName: "Mail", category: .email, style: .formal, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let result = OutputFormatter.format("Hello there.", for: ctx)
        XCTAssertTrue(result.hasPrefix("H"))
        XCTAssertTrue(result.hasSuffix("."))
    }

    // MARK: - IDE Feature Toggles

    func testFileTaggingDisabledBySettings() {
        let ctx = AppContext(bundleId: "", appName: "Cursor", category: .codeEditor, style: .formal, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: true)
        var settings = StyleSettings()
        settings.ideFileTagging = false
        let result = OutputFormatter.format("Look at main.swift", for: ctx, styleSettings: settings)
        XCTAssertFalse(result.contains("@main.swift"))
    }

    func testVariableRecognitionDisabledBySettings() {
        let ctx = AppContext(bundleId: "", appName: "VS Code", category: .codeEditor, style: .formal, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        var settings = StyleSettings()
        settings.ideVariableRecognition = false
        let result = OutputFormatter.format("Update getUserName function", for: ctx, styleSettings: settings)
        XCTAssertFalse(result.contains("`getUserName`"))
    }
}
