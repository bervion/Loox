---
name: vaultify-loox-ui-ux-redesign-plan
description: Plan hoàn thiện UI/UX flow app Loox theo bộ design 13 đợt; 7 phase, flow-polish trên màn có sẵn + defer infra
metadata:
  type: project
---

# Loox UI/UX flow completion plan (260710-2135)

Plan dir: `plans/260710-2135-loox-ui-ux-redesign/` (plan.md + phase-00..06 + research/ 7 report).

**Bối cảnh:** bộ design 13 đợt (mockup HTML) → gap analysis vs ~70 màn hiện có. Design = tham khảo FLOW, KHÔNG port pixel.

**Why:** ưu tiên cải thiện flow/UX hơn giao diện; phần lớn màn đã tồn tại chỉ cần polish copy/state/affordance.

**How to apply:**
- Ràng buộc cứng user: GIỮ native TabView icon-only + Home header hiện tại; không custom glass shell; không gate Approval-Mode theo iCloudSyncEnabled; localize EN+VI; iOS 17.6.
- Phase 0 = shared primitives (VaultInfoBanner/VaultStatusBadge/ColorizedSecretText + TotpRingView.nearExpiry) — blocker cho 1-5, file ownership riêng ở DesignSystem/Components.
- Phase 1 Home+Search, 2 Item screens, 3 Onboarding/Lock/Personas, 4 Settings/Import-Export/About-Us(new) — độc lập file, song song sau P0.
- Phase 5 Sharing pending-persistence (fix "owner stuck on Waiting") — rủi ro cao, SEQUENCE sau P1/P2 vì đụng HomeScreen+ItemDetailScreen.
- Phase 6 DEFERRED/ADR: Private Email relay UI, device key-provisioning (Vault Key never syncs — CRITICAL), Extra-Protection crypto, auto-dark brightness (cắt), background accept-detection.

**Path fix đã verify:** FolderEditorSheet/ManageFoldersScreen ở `Features/Folders/` (không phải Vault/). Chưa có InfoBanner dùng chung (chỉ CapabilityBannerView). Reuse: ThemedCard/CategoryBadge/FilterChip/PasswordStrengthMeter/TotpRingView/WatchtowerScoreRing/CopyToastOverlay.

**Cần user quyết:** score-band thang (giữ hiện tại), About Us content+team thật (không ship placeholder), cipher wording verify (Argon2id/AES-GCM vs ChaCha20), RelayFeature bật/tắt, ADR key-transfer + Extra-Protection crypto.

Liên quan: [[vaultify-persona-space-partition-plan]], [[vaultify-relay-destination-alias-mgmt-plan]], [[vaultify-p3-alias-model-plan]].
