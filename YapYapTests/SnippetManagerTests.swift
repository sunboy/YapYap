// SnippetManagerTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class SnippetManagerTests: XCTestCase {

    func testMatchExactTrigger() {
        let manager = SnippetManager(shouldPersist: false)
        manager.snippets = [
            VoiceSnippet(trigger: "my email", expansion: "john@example.com")
        ]
        let match = manager.matchSnippet(from: "my email")
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.expansion, "john@example.com")
    }

    func testMatchWithInsertPrefix() {
        let manager = SnippetManager(shouldPersist: false)
        manager.snippets = [
            VoiceSnippet(trigger: "my email", expansion: "john@example.com")
        ]
        let match = manager.matchSnippet(from: "insert my email")
        XCTAssertNotNil(match)
    }

    func testCaseInsensitiveMatch() {
        let manager = SnippetManager(shouldPersist: false)
        manager.snippets = [
            VoiceSnippet(trigger: "My Email", expansion: "john@example.com")
        ]
        let match = manager.matchSnippet(from: "my email")
        XCTAssertNotNil(match)
    }

    func testNoMatch() {
        let manager = SnippetManager(shouldPersist: false)
        manager.snippets = [
            VoiceSnippet(trigger: "my email", expansion: "john@example.com")
        ]
        let match = manager.matchSnippet(from: "send an email to john")
        XCTAssertNil(match)
    }

    func testTrimsWhitespace() {
        let manager = SnippetManager(shouldPersist: false)
        manager.snippets = [
            VoiceSnippet(trigger: "my email", expansion: "john@example.com")
        ]
        let match = manager.matchSnippet(from: "  my email  ")
        XCTAssertNotNil(match)
    }

    func testAddSnippet() {
        let manager = SnippetManager(shouldPersist: false)
        manager.addSnippet(trigger: "test", expansion: "Test expansion")
        XCTAssertEqual(manager.snippets.count, 1)
        XCTAssertEqual(manager.snippets.first?.trigger, "test")
    }

    func testRemoveSnippet() {
        let manager = SnippetManager(shouldPersist: false)
        manager.addSnippet(trigger: "test", expansion: "expansion")
        let id = manager.snippets.first!.id
        manager.removeSnippet(id: id)
        XCTAssertTrue(manager.snippets.isEmpty)
    }

    func testVoiceSnippetInit() {
        let snippet = VoiceSnippet(trigger: "greeting", expansion: "Hello, how can I help?")
        XCTAssertEqual(snippet.trigger, "greeting")
        XCTAssertEqual(snippet.expansion, "Hello, how can I help?")
        XCTAssertFalse(snippet.isTeamShared)
        XCTAssertNotNil(snippet.id)
    }
}
