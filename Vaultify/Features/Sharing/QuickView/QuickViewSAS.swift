import CryptoKit
import Foundation

/// Short Authentication String (SAS) — a human-comparable "2 words + 2
/// digits" phrase derived INDEPENDENTLY on-device and by the browser/backend
/// from public session material (session id + the browser's public enc/sig
/// key hashes). Pure function — no networking, no state.
///
/// BE-parity proven (`workers/loox-quick-view/src/contracts/sas.ts`, frozen
/// vectors `quick-view-sas-vectors-v1.json`): `word1 foam 97` golden.
///
/// Honest framing: the SAS is a sanity-check signal the owner eyeballs
/// against the browser tab, NOT a cryptographic authentication of the
/// `/open` page itself — an attacker-controlled page can render whatever SAS
/// string it wants (all three inputs are public). A mismatch is still a hard
/// block (INV-QV-19) because it catches the case where the app resolved a
/// DIFFERENT session than the one on screen. Uploader authenticity comes
/// ONLY from the App Attest upload assertion, never from SAS equality.
nonisolated enum QuickViewSAS {
    /// HKDF salt AND info — both the literal string `"LOOX-QV-SAS-V1"` (frozen).
    static let hkdfSaltAndInfo = "LOOX-QV-SAS-V1"

    /// Frozen BIP-39 English wordlist (2048 entries, official ordering).
    /// Index 0 = "abandon", index 2047 = "zoo" — must byte-for-byte match
    /// `sas-wordlist.ts` on the worker; never reorder/add/remove entries.
    static let wordCount = 2048

    /// Derive the "word1 word2 DD" phrase for one session.
    ///
    ///   okm = HKDF-SHA256(ikm = session_id‖enc_key_hash‖sig_key_hash,
    ///                     salt = info = utf8("LOOX-QV-SAS-V1"), L = 4)
    ///   word1 = wordlist[(okm[0]<<3) | (okm[1]>>5)]        — bits[0..10]
    ///   word2 = wordlist[((okm[1]&0x1f)<<6) | (okm[2]>>2)] — bits[11..21]
    ///   digits = okm[3] % 100, zero-padded to 2
    ///
    /// Returns `nil` only if the bundled wordlist is missing or the wrong
    /// size (fail-closed — callers must treat `nil` as "cannot show a SAS",
    /// never a silent fallback phrase).
    static func derive(sessionID: Data, encKeyHash: Data, sigKeyHash: Data,
                       words: [String] = QuickViewSASWordList.words) -> String? {
        guard words.count == wordCount else { return nil }
        let ikm = sessionID + encKeyHash + sigKeyHash
        let saltAndInfo = Data(hkdfSaltAndInfo.utf8)
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: saltAndInfo,
            info: saltAndInfo,
            outputByteCount: 4)
        let okm = derivedKey.withUnsafeBytes { Data($0) }
        let word1Index = (Int(okm[0]) << 3) | (Int(okm[1]) >> 5)
        let word2Index = (Int(okm[1] & 0x1f) << 6) | (Int(okm[2]) >> 2)
        let digits = Int(okm[3]) % 100
        return "\(words[word1Index]) \(words[word2Index]) \(String(format: "%02d", digits))"
    }
}

/// Loads the bundled BIP-39 English wordlist used ONLY for SAS rendering —
/// deliberately a separate list from `DicewareWordList` (EFF large list, used
/// for password generation): the two must never be conflated, since SAS
/// derivation depends on this exact 2048-entry ordering matching the worker.
nonisolated enum QuickViewSASWordList {
    static let words: [String] = {
        guard let url = Bundle.main.url(forResource: "sas-wordlist-bip39", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }()
}
