# Code review — Vault Audit (feat/vault-audit) — 260711

Reviewer: code-reviewer subagent. Verdict: **DONE_WITH_CONCERNS**. 560/560 tests, cả 2 target compile.

## Findings + resolution

| # | Sev | Finding | Resolution (cùng ngày) |
|---|-----|---------|------------------------|
| 1 | critical | Engine chạy trên MainActor: `SWIFT_APPROACHABLE_CONCURRENCY` (SE-0461 NonisolatedNonsendingByDefault) khiến `Task {}` từ @MainActor chạy toàn bộ rules/hash/scoring trên main | ✅ `Task.detached(priority: .userInitiated)` trong AuditRunController + doc comment |
| 2 | major | `eraseEverything()` không wipe `audit-pwned-cache.bin` + Keychain secret | ✅ `AuditLocalCache.clearPersisted()` gọi trong erase path |
| 3 | major | `secretMarker` = SHA256(password) không salt, vào CK recordName plaintext → offline password oracle | ✅ HMAC key dẫn xuất Vault Key (`AuditFingerprint.markerKey`), `AuditContext.secretMarkerKey`; fallback SHA256 chỉ cho tests |
| 4 | major | Không cancel audit khi lock; snapshot plaintext + save sau lock | ✅ onChange lock → cancel; fresh-key guard trước save trong MainActor.run |
| 5 | minor | quality.weak + quality.contains-context double-fire cho 1 password | ✅ context-echo suppress weak finding |
| 6 | minor | WatchtowerStrengthScreen chạy engine per render | ✅ cache @State + .task/.onChange |
| 7 | minor | Meter hiện bits legacy mâu thuẫn grade mới | ✅ bits = log10Guesses × 3.3219 |
| 8 | minor | Catalog match nondeterministic (hash order) | ✅ longest-suffix max |
| 9-16 | low | titleKey dead, ForEach id completedAt, try? save nuốt lỗi, retry 4xx, literal sizes, Calendar tz, tie-order jitter, keychain create race (self-healing) | ⏳ ghi nợ trong plan.md |

Verified sạch: LWW sync đúng pattern folder, sealed payload không plaintext, HIBP k-anonymity +
Add-Padding + no logging, cancelled audit không ghi gì, score = Σ pillars, localization VI đủ,
state restoration an toàn (path không persist nhánh này), fix-queue deterministic.

## Unresolved questions
- Marker HMAC đã đổi TRƯỚC khi có bất kỳ dữ liệu synced nào — không có migration cost.
- Low nits 9-16 gom vào polish pass sau.
