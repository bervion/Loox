import SwiftUI
import XCTest
@testable import Vaultify

/// Pins the full size-class matrix behind `AdaptiveShell.layout`.
///
/// The sidebar shell must never be reachable from a phone-shaped canvas: it removes the
/// tab bar, pins a 200-320pt sidebar, and turns full-screen UIKit pushes into in-column
/// SwiftUI pushes. Keying only off the horizontal class silently did exactly that on a
/// Plus/Max-class iPhone in landscape, so every cell of the matrix is asserted here.
final class AdaptiveShellLayoutTests: XCTestCase {

    // MARK: The four-case matrix

    func testCompactWidthCompactHeightUsesTabs() {
        // Standard-width iPhone in landscape.
        XCTAssertEqual(AdaptiveShell.layout(horizontal: .compact, vertical: .compact), .tabs)
    }

    func testCompactWidthRegularHeightUsesTabs() {
        // Every iPhone in portrait; iPad Slide Over and narrow Split View.
        XCTAssertEqual(AdaptiveShell.layout(horizontal: .compact, vertical: .regular), .tabs)
    }

    func testRegularWidthCompactHeightUsesTabs() {
        // Plus/Max-class iPhone in landscape: regular width, compact height. Only an
        // iPhone ever reports this pair, so it must stay in the tab shell.
        XCTAssertEqual(AdaptiveShell.layout(horizontal: .regular, vertical: .compact), .tabs)
    }

    func testRegularWidthRegularHeightUsesSidebar() {
        // iPad full screen or a wide Split View — the only canvas that earns the sidebar.
        XCTAssertEqual(AdaptiveShell.layout(horizontal: .regular, vertical: .regular), .sidebar)
    }

    // MARK: Unresolved size classes

    func testNilSizeClassesFallBackToTabs() {
        // SwiftUI reports nil before the first layout pass; the phone shell is the safe
        // default and avoids a one-frame sidebar flash.
        XCTAssertEqual(AdaptiveShell.layout(horizontal: nil, vertical: nil), .tabs)
        XCTAssertEqual(AdaptiveShell.layout(horizontal: .regular, vertical: nil), .tabs)
        XCTAssertEqual(AdaptiveShell.layout(horizontal: nil, vertical: .regular), .tabs)
    }

    // MARK: Invariant

    func testSidebarRequiresBothAxesRegular() {
        // Exhaustive sweep: exactly one of the nine (including nil) combinations may
        // resolve to the sidebar.
        let classes: [UserInterfaceSizeClass?] = [nil, .compact, .regular]
        var sidebarCases = 0
        for horizontal in classes {
            for vertical in classes where
                AdaptiveShell.layout(horizontal: horizontal, vertical: vertical) == .sidebar {
                sidebarCases += 1
                XCTAssertEqual(horizontal, .regular)
                XCTAssertEqual(vertical, .regular)
            }
        }
        XCTAssertEqual(sidebarCases, 1)
    }
}
