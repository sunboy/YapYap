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

    // MARK: - Bare File Tagging (no "at" prefix)

    func testBareFileTagging() {
        let result = OutputFormatter.applyFileTagging("work on notes.ts and files.ts")
        XCTAssertTrue(result.contains("@notes.ts"))
        XCTAssertTrue(result.contains("@files.ts"))
    }

    func testBareFileTaggingSingleFile() {
        let result = OutputFormatter.applyFileTagging("check the package.json configuration")
        XCTAssertTrue(result.contains("@package.json"))
    }

    func testBareFileTaggingDoesNotDoubleTag() {
        let result = OutputFormatter.applyFileTagging("check @main.swift")
        XCTAssertEqual(result.filter { $0 == "@" }.count, 1)
    }

    func testBareFileTaggingIgnoresDottedPaths() {
        let result = OutputFormatter.applyFileTagging("bundle is com.apple.Safari")
        XCTAssertFalse(result.contains("@apple"))
        XCTAssertFalse(result.contains("@Safari"))
    }

    func testBareFileTaggingMixedWithAtPrefix() {
        let result = OutputFormatter.applyFileTagging("look at main.swift and also config.json")
        XCTAssertTrue(result.contains("@main.swift"))
        XCTAssertTrue(result.contains("@config.json"))
    }

    func testBareFileTaggingInIDEChatPipeline() {
        let ctx = AppContext(bundleId: "", appName: "Cursor", category: .codeEditor, style: .formal, windowTitle: "Composer", focusedFieldText: nil, isIDEChatPanel: true)
        let result = OutputFormatter.format("I want you to work on notes.ts and files.ts", for: ctx)
        XCTAssertTrue(result.contains("@notes.ts"))
        XCTAssertTrue(result.contains("@files.ts"))
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

    // MARK: - Work Messaging (@mentions, #channels)

    func testSlackMentionConversion() {
        let ctx = AppContext(bundleId: "", appName: "Slack", category: .workMessaging, style: .casual, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let result = OutputFormatter.format("Hey at john can you review this", for: ctx)
        XCTAssertTrue(result.contains("@john"))
    }

    func testSlackChannelConversion() {
        let ctx = AppContext(bundleId: "", appName: "Slack", category: .workMessaging, style: .casual, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let result = OutputFormatter.format("Post it in hashtag general", for: ctx)
        XCTAssertTrue(result.contains("#general"))
    }

    func testSlackHashChannelConversion() {
        let result = OutputFormatter.applySlackFormatting("Check hash engineering for updates")
        XCTAssertTrue(result.contains("#engineering"))
    }

    func testSlackMentionSkipsStopwords() {
        let result = OutputFormatter.applySlackFormatting("Meet me at noon at the office")
        XCTAssertFalse(result.contains("@noon"))
        XCTAssertFalse(result.contains("@the"))
    }

    func testSlackMentionSkipsFilenames() {
        let result = OutputFormatter.applySlackFormatting("Look at main.swift for details")
        // "main.swift" contains a dot — should not become @main.swift in slack context
        // (file tagging is separate from mention conversion)
        XCTAssertFalse(result.contains("@main"))
    }

    func testSlackMentionMultiple() {
        let result = OutputFormatter.applySlackFormatting("Hey at sarah and at mike please review")
        XCTAssertTrue(result.contains("@sarah"))
        XCTAssertTrue(result.contains("@mike"))
    }

    func testSlackFormattingNotAppliedToEmail() {
        let ctx = AppContext(bundleId: "", appName: "Mail", category: .email, style: .formal, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let result = OutputFormatter.format("Meet me at noon", for: ctx)
        XCTAssertFalse(result.contains("@noon"))
    }

    // MARK: - Email Formatting

    func testEmailParagraphBreaksAtTransition() {
        let ctx = AppContext(bundleId: "", appName: "Mail", category: .email, style: .formal, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let result = OutputFormatter.format("The project is going well. The team delivered on time. However the budget needs review. We are over by 10 percent.", for: ctx)
        XCTAssertTrue(result.contains("\n\nHowever"))
    }

    func testEmailNoBreaksForShortText() {
        let result = OutputFormatter.applyEmailFormatting("Hello there. How are you?")
        // Only 2 sentences, not enough for paragraph breaks
        XCTAssertFalse(result.contains("\n\n"))
    }

    func testEmailBreaksAtMultipleTransitions() {
        let input = "The project is done. The team is happy. Additionally we saved budget. The client is pleased. Finally we shipped on time."
        let result = OutputFormatter.applyEmailFormatting(input)
        XCTAssertTrue(result.contains("\n\nAdditionally"))
        XCTAssertTrue(result.contains("\n\nFinally"))
    }

    func testEmailGreetingExtracted() {
        let input = "Hi Robert, I found your contact on the conference page and noticed that you are an organizer for the upcoming AI summit."
        let result = OutputFormatter.applyEmailFormatting(input)
        XCTAssertTrue(result.hasPrefix("Hi Robert,\n\n"))
    }

    func testEmailSignOffExtracted() {
        let input = "I found your contact on the conference page. I'd like to present my profile. I'm an expert in AI and data engineering. Thanks, Sandeep"
        let result = OutputFormatter.applyEmailFormatting(input)
        XCTAssertTrue(result.contains("\n\nThanks,\nSandeep"))
    }

    func testEmailGreetingAndSignOff() {
        let input = "Hello Sarah, The project is going well and we delivered on time. I wanted to update you on our progress. Best regards, John"
        let result = OutputFormatter.applyEmailFormatting(input)
        XCTAssertTrue(result.hasPrefix("Hello Sarah,\n\n"))
        XCTAssertTrue(result.hasSuffix("Best regards,\nJohn"))
    }

    func testEmailNoGreetingWithoutName() {
        let input = "Hello there. The project is going well. We delivered on time."
        let result = OutputFormatter.applyEmailFormatting(input)
        XCTAssertFalse(result.hasPrefix("Hello there\n\n"))
    }

    // MARK: - AI Chat File Tagging

    func testAIChatFileTagging() {
        let ctx = AppContext(bundleId: "", appName: "ChatGPT", category: .aiChat, style: .casual, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let result = OutputFormatter.format("Look at main.swift for the implementation", for: ctx)
        XCTAssertTrue(result.contains("@main.swift"))
    }

    func testAIChatBareFileTagging() {
        let ctx = AppContext(bundleId: "", appName: "Claude", category: .aiChat, style: .casual, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let result = OutputFormatter.format("Work on notes.ts and files.ts", for: ctx)
        XCTAssertTrue(result.contains("@notes.ts"))
        XCTAssertTrue(result.contains("@files.ts"))
    }

    func testAIChatFileTaggingDisabledBySettings() {
        let ctx = AppContext(bundleId: "", appName: "ChatGPT", category: .aiChat, style: .casual, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        var settings = StyleSettings()
        settings.ideFileTagging = false
        let result = OutputFormatter.format("Look at main.swift", for: ctx, styleSettings: settings)
        XCTAssertFalse(result.contains("@main.swift"))
    }

    // MARK: - List Formatting (Ordinal Safety Net)

    func testListFormattingOrdinals() {
        let input = "First, buy groceries. Second, do laundry. Third, pick up the kids."
        let result = OutputFormatter.applyListFormatting(input)
        XCTAssertTrue(result.contains("1."))
        XCTAssertTrue(result.contains("\n2."))
        XCTAssertTrue(result.contains("\n3."))
    }

    func testListFormattingSingleOrdinalNoConversion() {
        let input = "First, let me explain how this works."
        let result = OutputFormatter.applyListFormatting(input)
        XCTAssertFalse(result.contains("1."))
    }

    func testListFormattingProseNotConverted() {
        let input = "I went to the store, grabbed some food, and came home."
        let result = OutputFormatter.applyListFormatting(input)
        XCTAssertFalse(result.contains("\n"))
    }

    func testListFormattingNumberWord() {
        let input = "Number one, buy groceries. Number two, do laundry."
        let result = OutputFormatter.applyListFormatting(input)
        XCTAssertTrue(result.contains("1."))
        XCTAssertTrue(result.contains("2."))
    }

    func testListFormattingInPipeline() {
        let ctx = AppContext(bundleId: "", appName: "Notes", category: .documents, style: .formal, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let result = OutputFormatter.format("First, buy groceries. Second, do laundry. Third, pick up the kids.", for: ctx)
        XCTAssertTrue(result.contains("1."))
        XCTAssertTrue(result.contains("\n"))
    }

    // MARK: - Colon-List Detection

    func testColonListWithThreeItemsAndConjunction() {
        let input = "A couple of things for tomorrow: check Reddit, GitHub Actions job run status, and finish working on the voice app."
        let result = OutputFormatter.applyColonListFormatting(input)
        XCTAssertTrue(result.contains("1. Check Reddit"))
        XCTAssertTrue(result.contains("\n2. GitHub Actions job run status"))
        XCTAssertTrue(result.contains("\n3. Finish working on the voice app"))
        XCTAssertTrue(result.hasPrefix("A couple of things for tomorrow:"))
    }

    func testColonListWithTwoItems() {
        let input = "Two things: eat lunch and take a walk."
        let result = OutputFormatter.applyColonListFormatting(input)
        XCTAssertTrue(result.contains("1. Eat lunch"))
        XCTAssertTrue(result.contains("\n2. Take a walk"))
    }

    func testColonNonListSingleItem() {
        let input = "The answer: 42."
        let result = OutputFormatter.applyColonListFormatting(input)
        // Single item after colon — not a list
        XCTAssertEqual(result, input)
    }

    func testColonListPreservesIntro() {
        let input = "Things to pick up: milk, eggs, bread."
        let result = OutputFormatter.applyColonListFormatting(input)
        XCTAssertTrue(result.hasPrefix("Things to pick up:"))
        XCTAssertTrue(result.contains("1. Milk"))
        XCTAssertTrue(result.contains("2. Eggs"))
        XCTAssertTrue(result.contains("3. Bread"))
    }

    func testColonListWithoutConjunction() {
        let input = "Pick up: milk, eggs, bread."
        let result = OutputFormatter.applyColonListFormatting(input)
        XCTAssertTrue(result.contains("1. Milk"))
        XCTAssertTrue(result.contains("2. Eggs"))
        XCTAssertTrue(result.contains("3. Bread"))
    }

    func testColonListTimeNotTriggered() {
        let input = "Meet at 3:00 and bring lunch."
        let result = OutputFormatter.applyColonListFormatting(input)
        // Time colon should not trigger list detection
        XCTAssertEqual(result, input)
    }

    func testColonListInFullPipeline() {
        let ctx = AppContext(bundleId: "", appName: "Notes", category: .documents, style: .formal, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let result = OutputFormatter.format("Things to do: check email, review the PR, and update the docs.", for: ctx)
        XCTAssertTrue(result.contains("1."))
        XCTAssertTrue(result.contains("2."))
        XCTAssertTrue(result.contains("3."))
    }

    func testColonListWithOrConjunction() {
        let input = "Choose one: pizza, sushi, or tacos."
        let result = OutputFormatter.applyColonListFormatting(input)
        XCTAssertTrue(result.contains("1. Pizza"))
        XCTAssertTrue(result.contains("2. Sushi"))
        XCTAssertTrue(result.contains("3. Tacos"))
    }

    func testColonNonListSentence() {
        let input = "He said: the project is going well."
        let result = OutputFormatter.applyColonListFormatting(input)
        // No commas, single clause — not a list
        XCTAssertEqual(result, input)
    }

    // MARK: - Split List Items Helper

    func testSplitListItemsBasic() {
        let items = OutputFormatter.splitListItems("milk, eggs, and bread")
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0], "milk")
        XCTAssertEqual(items[1], "eggs")
        XCTAssertEqual(items[2], "bread")
    }

    func testSplitListItemsTwoWithAnd() {
        let items = OutputFormatter.splitListItems("eat lunch and take a walk")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0], "eat lunch")
        XCTAssertEqual(items[1], "take a walk")
    }

    func testSplitListItemsSingleItem() {
        let items = OutputFormatter.splitListItems("just one thing")
        XCTAssertEqual(items.count, 1)
    }
}
