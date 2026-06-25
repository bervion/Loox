import XCTest
import UIKit
@testable import Vaultify

/// Phase 4: avatar downscale + sealed round-trip through the repository.
@MainActor
final class ProfileAvatarTests: XCTestCase {

    private func makeStack() -> (repo: VaultRepository, store: VaultStore) {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: [UInt8](repeating: 0x2a, count: 32))
        let store = VaultStore(inMemory: true)
        let repo = VaultRepository(store: store, session: session)
        repo.reload()
        return (repo, store)
    }

    private func solidImage(_ size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testDownscaleCapsLongestSide() throws {
        let data = try XCTUnwrap(AvatarImage.downscaledJPEG(solidImage(CGSize(width: 1000, height: 500))))
        let img = try XCTUnwrap(UIImage(data: data))
        XCTAssertLessThanOrEqual(max(img.size.width, img.size.height), AvatarImage.maxDimension)
    }

    func testSetAvatarRoundTrips() throws {
        let (repo, _) = makeStack()
        try repo.add(VaultItem(category: .identity, title: "Me"))
        let id = repo.items[0].id
        repo.setAvatar(solidImage(CGSize(width: 300, height: 300)), for: id)
        XCTAssertNotNil(repo.avatarImage(for: id))
        repo.setAvatar(nil, for: id)
        XCTAssertNil(repo.avatarImage(for: id))
    }

    func testAvatarSealedAtRest() throws {
        let (repo, store) = makeStack()
        try repo.add(VaultItem(category: .identity, title: "Me"))
        let id = repo.items[0].id
        let plaintext = try XCTUnwrap(AvatarImage.downscaledJPEG(solidImage(CGSize(width: 100, height: 100))))
        repo.setAvatar(solidImage(CGSize(width: 100, height: 100)), for: id)
        let sealed = try XCTUnwrap(store.record(id: id)?.avatarSealed)
        XCTAssertNotEqual(sealed, plaintext)  // ciphertext, not the raw JPEG
    }

    func testSetAvatarMarksDirty() throws {
        let (repo, store) = makeStack()
        try repo.add(VaultItem(category: .identity, title: "Me"))
        let id = repo.items[0].id
        try XCTUnwrap(store.record(id: id)).dirty = false
        try store.context.save()
        repo.setAvatar(solidImage(CGSize(width: 50, height: 50)), for: id)
        XCTAssertTrue(try XCTUnwrap(store.record(id: id)).dirty)
    }
}
