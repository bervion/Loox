import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Vaultify

/// Device-independent snapshot settings.
///
/// `SnapshotTesting` renders at the HOST simulator's `displayScale` unless one
/// is supplied, and it compares the raster size before it compares a single
/// pixel. Every reference in this target was recorded on an @2x device and then
/// replayed on the @3x iPhone 17 Pro the CI simulator policy pins, so all three
/// tests failed with
/// `Newly-taken snapshot@(390.0, 700.0) does not match reference@(260.0, 466.67)`
/// — a size mismatch, not a rendering regression. Pinning the scale here makes
/// a reference valid on any device the suites are ever pointed at.
enum SnapshotEnvironment {
    /// Recorded at @2x: half the pixels of @3x for the same points, and the
    /// scale the existing references were captured at.
    static let displayScale: CGFloat = 2

    static let traits = UITraitCollection { traits in
        traits.displayScale = displayScale
    }
}

extension Snapshotting where Value: SwiftUI.View, Format == UIImage {
    /// A fixed-size image strategy with the raster scale pinned, so a reference
    /// recorded on one simulator stays valid on the next one.
    static func scaledImage(width: CGFloat, height: CGFloat) -> Snapshotting {
        .image(
            layout: .fixed(width: width, height: height),
            traits: SnapshotEnvironment.traits
        )
    }
}

/// The one `AppEnvironment` every case in this target renders against.
///
/// Deliberately shared and never released. `AppEnvironment.init` installs
/// closures onto the process-wide `LooxEntitlementClientHooks` statics, so
/// building a SECOND environment drops the previous one's
/// `LooxEntitlementCoordinator` — a `@MainActor` class whose isolated `deinit`
/// runs through the `swift_task_deinitOnExecutorMainActorBackDeploy` shim the
/// iOS 17.3 deployment floor forces in. On Xcode 27.0 / iOS 26.3 that shim
/// aborts in libmalloc ("pointer being freed was not allocated") and takes the
/// whole test host down mid-suite. The shipping app builds exactly one
/// environment and never deallocates it, so holding one here models the app
/// instead of papering over anything the product does.
@MainActor
enum SnapshotAppEnvironment {
    private static var shared: AppEnvironment?

    static func make() throws -> AppEnvironment {
        if let shared { return shared }
        let configuration = try UITestConfiguration.parse(arguments: [
            "Vaultify",
            UITestConfiguration.launchFlag,
            UITestConfiguration.fixtureArgument,
            UITestConfiguration.Fixture.vaultEditSaveRelock.rawValue,
        ])
        let environment = AppEnvironment(uiTestConfiguration: configuration)
        shared = environment
        return environment
    }
}

@MainActor
func makeSnapshotEnvironment() throws -> AppEnvironment {
    try SnapshotAppEnvironment.make()
}
