// DesignTokensTests.swift
// YapYapTests — Verify design tokens are properly defined
import XCTest
import SwiftUI
@testable import YapYap

final class DesignTokensTests: XCTestCase {

    // MARK: - Colors Exist

    func testPrimaryColorsExist() {
        _ = Color.ypBg
        _ = Color.ypBg2
        _ = Color.ypBg3
        _ = Color.ypBg4
        _ = Color.ypCard
        _ = Color.ypCard2
        _ = Color.ypBorder
        _ = Color.ypBorderLight
        _ = Color.ypBorderFocus
    }

    func testAccentColorsExist() {
        _ = Color.ypLavender
        _ = Color.ypWarm
        _ = Color.ypMint
        _ = Color.ypZzz
        _ = Color.ypBlush
        _ = Color.ypRed
    }

    func testTextColorsExist() {
        _ = Color.ypText1
        _ = Color.ypText2
        _ = Color.ypText3
        _ = Color.ypText4
    }

    // MARK: - Creature State

    func testCreatureStateEnum() {
        let states: [CreatureState] = [.sleeping, .recording, .processing]
        XCTAssertEqual(states.count, 3)
    }

    // MARK: - Floating Bar Position

    func testFloatingBarPositionCases() {
        let positions = FloatingBarPosition.allCases
        XCTAssertEqual(positions.count, 4)
    }

    func testFloatingBarPositionDisplayNames() {
        XCTAssertEqual(FloatingBarPosition.bottomCenter.displayName, "Bottom Center")
        XCTAssertEqual(FloatingBarPosition.topCenter.displayName, "Top Center")
    }
}
