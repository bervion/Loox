import Foundation

/// Heap buffer for sensitive key material.
///
/// The backing page is locked into physical memory (`mlock`) so it is never
/// written to swap, and is explicitly zeroed with `memset_s` (which the
/// compiler may not optimise away) on release. This is best-effort: CryptoKit
/// value types and Swift `Array` copies may still transiently hold bytes.
nonisolated final class SecureBytes: @unchecked Sendable {
    private let pointer: UnsafeMutableRawPointer
    let count: Int

    init(count: Int) {
        self.count = count
        let alloc = max(count, 1)
        pointer = UnsafeMutableRawPointer.allocate(byteCount: alloc, alignment: 16)
        memset(pointer, 0, alloc)
        _ = mlock(pointer, alloc)
    }

    convenience init(_ bytes: [UInt8]) {
        self.init(count: bytes.count)
        if !bytes.isEmpty {
            bytes.withUnsafeBytes { _ = memcpy(pointer, $0.baseAddress!, $0.count) }
        }
    }

    /// Borrow the raw bytes for the duration of `body`. Do not escape the pointer.
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try body(UnsafeRawBufferPointer(start: pointer, count: count))
    }

    /// Copy out the bytes. Callers are responsible for the resulting `Array`.
    var bytes: [UInt8] { Array(UnsafeRawBufferPointer(start: pointer, count: count)) }

    deinit {
        let alloc = max(count, 1)
        memset_s(pointer, alloc, 0, alloc)
        _ = munlock(pointer, alloc)
        pointer.deallocate()
    }
}

/// Overwrite a byte array in place. Best-effort zeroisation for transient keys.
nonisolated func secureZero(_ bytes: inout [UInt8]) {
    guard !bytes.isEmpty else { return }
    bytes.withUnsafeMutableBytes { _ = memset_s($0.baseAddress!, $0.count, 0, $0.count) }
}
