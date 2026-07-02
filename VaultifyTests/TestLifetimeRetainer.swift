import Foundation

/// Keeps in-memory store stacks alive for the duration of the test process.
///
/// Xcode 27 beta's app-hosted XCTest runner can abort while deallocating some
/// main-actor SwiftData/Observation objects. Retaining these short-lived test
/// fixtures avoids that runner bug without changing production lifetimes.
@MainActor
enum TestLifetimeRetainer {
    private static var retained: [AnyObject] = []

    static func retain(_ objects: AnyObject...) {
        retained.append(contentsOf: objects)
    }
}
