# Phase 6 — Infra-dependent (DEFERRED / ADR-gated)

**Context:** research/design-spec-item-detail-editor-tools.md (11a/b/c), settings-autofill-profile.md (5c,6d,6e,6f), secondary (10c,10d,10e,10f). Depends: ADRs + backend services.

## Overview
- Priority: P3 (hoãn — chờ hạ tầng)
- Status: deferred
- Gom mọi feature UI phụ thuộc service/backend/crypto chưa tồn tại hoặc cần ADR. KHÔNG build blind. Mỗi mục ghi rõ phần UI-only làm được vs phần block.

## Blocked items (từng mục = 1 quyết định)

### 6.1 Private Email alias — hiển thị trong item/editor/autofill (11a/b/c, 6d)
- **Có sẵn:** EmailAlias model + PersonaAliasesScreen/AliasDetailScreen/AliasEditorSheet (local). RelayFeature flag OFF (memory p3-alias-model).
- **UI-only làm được:** badge PRIVATE + mono alias + "forwards to" line trong Item Detail/Editor/AutoFill row — CHỈ khi alias đã bind local. Copy-luôn-copy-alias.
- **Block:** forwarding thật (loox.email receive-forward), "Tap to activate" real destination, verified inbox — cần backend relay (memory relay-destination plan). Không có backend → forward line hiển thị state local, không guarantee mail thật.
- **Gate:** RelayFeature flag. Nếu OFF → chỉ show alias local, ẩn "forwarding active/verified". ADR: khi nào bật relay.

### 6.2 Device key-provisioning (5c device list, 6e QR máy mới, 6f approve máy cũ)
- **Có sẵn:** SyncSettingsView + PairDeviceSheet (QR pairing UI), JoinVaultFlow.
- **Block (CRITICAL):** "Vault Key never syncs" → multi-device sync non-functional without key provisioning (memory ipad-mac-multiplatform). Design 6e/6f là flow provision key qua QR + approve máy cũ. Cần crypto: máy mới show QR (pubkey), máy cũ seal Vault Key → gửi. **Cần ADR + impl crypto** (không phải UI-only).
- **UI-only làm được:** device list hiển thị + "Pair New Device" entry (đã có). Approve sheet copy.
- **Gate:** ADR key-transfer protocol trước khi ship "Approve → gửi key".

### 6.3 Auto-Dark "Below a brightness level" (10d)
- **Block:** không có public ambient-light API. `UIScreen.brightness` observe khả thi nhưng fragile.
- **Quyết định (Q10 default):** CẮT — giữ Off/System/Scheduled (Phase 4 đã làm). Mục này = chỉ mở lại nếu user yêu cầu + chấp nhận `UIScreen.brightness` polling.

### 6.4 Alias pause/resume lifecycle (10e)
- **UI-only:** Pause/Resume/Delete buttons + Paused badge state (amber).
- **Block:** pause/resume THẬT ngăn/mở forward = backend relay. Local-only pause chỉ đổi flag, không ảnh hưởng mail thật tới khi có relay.
- **Gate:** cùng RelayFeature với 6.1.

### 6.5 Background accept-detection push + auto-Nudge (10f/12c)
- **Có sẵn (Phase 5):** manual Check Now.
- **Block:** background detect CKShare acceptanceStatus → local/push notification "X accepted" (memory approval-share-accept-detection: bug hiện tại chỉ detect qua profile poll). Cần background refresh + CKShare acceptanceStatus read fix.
- **Gate:** fix acceptanceStatus (plan 260708-2151) trước.

### 6.6 Extra Protection crypto scope (10c)
- **Có sẵn (Phase 4):** UI setup polish (Level2SettingsView).
- **Block:** per-field key derivation riêng, "không recover kể cả Emergency Kit", tương tác sync/share các field protected → **cần ADR crypto** (key không nằm trong Vault Key escrow → ảnh hưởng envelope/sync/share model).
- **Gate:** ADR trước khi đổi crypto behavior. Phase 4 chỉ UI, KHÔNG đổi crypto.

## Requirements
- Mỗi mục: viết ADR (docs/ hoặc plan riêng) trước impl. Không build phần block khi chưa có service/ADR.
- Feature-flag gate mọi phần phụ thuộc backend (RelayFeature, key-transfer).

## Related code files (khi unblock)
- `Vaultify/Features/Personas/AliasDetailScreen.swift`, `PersonaAliasesScreen.swift`, `AliasEditorSheet.swift`
- `Vaultify/Features/ItemDetail/ItemDetailScreen.swift`, `ItemEditor/ItemEditorScreen.swift`, `VaultifyAutoFill/AutoFillView.swift`
- `Vaultify/Features/Settings/SyncSettingsView.swift`, `PairDeviceSheet.swift`, `Onboarding/JoinVaultFlow.swift`
- `Vaultify/Features/Settings/Level2SettingsView.swift`
- VaultifyCore: relay service, key-transfer crypto, EmailAlias, envelope key

## Todo (gated — không start khi chưa unblock)
- [ ] ADR: key-transfer protocol (6.2) — CRITICAL cho multi-device
- [ ] ADR: Extra Protection crypto scope (6.6)
- [ ] Decision: RelayFeature bật/tắt → 6.1/6.4
- [ ] Fix acceptanceStatus → 6.5
- [ ] User confirm: Auto-Dark brightness giữ/cắt (6.3, default cắt)
- [ ] Private Email UI (sau khi relay/flag rõ)

## Success criteria
- Không ship UI hứa hẹn service không tồn tại (vd "Forwarding active" khi không có relay).
- Mọi phần backend gated sau feature-flag, fail-closed.

## Risk assessment
- **[Cao]** Ship UI giả (forward/verified/key-transfer) → mất niềm tin + false security. Mitigation: flag-gate + ADR bắt buộc.
- **[Cao]** Key-transfer crypto sai → lộ Vault Key. Mitigation: ADR + review crypto trước impl.

## Next
- Cần user/lead quyết: bật RelayFeature? viết ADR key-transfer? Ưu tiên 6.2 (multi-device thực sự dùng được) nếu roadmap cần sync.
