# Audit UI/UX + smoke: extension redesign production readiness

Phạm vi: các surface đổi trong đợt extension-brand-alignment (UnlockGate, AutoFill picker, Safari popup, inline menu) + smoke toàn repo. Bar: `docs/design-dna-standard.md` (10 rules + adversarial protocol + acceptance matrix).

## Adversarial protocol per surface

**UnlockGate (AutoFill, iOS + macOS twin)**
1. Protagonist: "mở kho" — symbol thở + spinner/form, không gì cạnh tranh. PASS
2. Text: không string mới; string cũ đã EN/VI/JA trong xcstrings. PASS
3. Controls: Unlock = borderedProminent controlSize(.large); Face ID retry = bordered large; đủ 44pt. PASS
4. Shape/space: extension không link DS tokens (pattern có sẵn, comment trong file); literal 24/12/96/84 nhất quán file. PASS (exemption)
5. States: biometric-wait (symbol 96 + spinner), password form (symbol 84 + wordmark compact), content. PASS
- FIX trong audit: lockup được gom 1 VoiceOver element label "Loox" (trước đó wordmark image đọc tên asset "BrandLogo").
- RM: LooxLogoBreatheView tự collapse (phase=0). Reduce Transparency: không material mới. Dark: symbol full-color + wordmark có variant. PASS

**AutoFill picker rows**
- Avatar 36pt monogram = đúng initials + hue của Home (MonogramAvatar single source); tap = full row; sealed/shared labels giữ nguyên; empty title → key tile (SF trong extension = pattern có sẵn faceid/lock.fill, không có Polaris assets trong appex). PASS
- Radius tile 26% proportional = documented exemption. PASS

**Safari popup**
- Brand: symbol 6 vòng SVG inline trace từ LooxAnimationGeometry + breathe 4s, RM-gated; lockup thứ tự symbol→wordmark như BrandLockup. PASS
- Rows: monogram (hue parity Swift↔JS verified 4/4), identity/card glyph duotone đúng VaultColors.category cả light+dark. PASS
- Action hierarchy rule 7: mỗi row tối đa 1 filled (Điền) + 1 quiet (Sao chép). PASS
- Corner scale: row 10 / control-in-row 8 / standalone 12 (bù circular-vs-continuous), press states. PASS
- Widths: 400 + 320 (min-width) VI — không tràn, không vỡ; 320 identity title ellipsis sớm (chấp nhận: popup thực tế ≥375, ellipsis là hành vi đúng). PASS w/ note
- Bug thật sửa trong đợt: `[hidden]` bị author display đè → mọi state section chồng nhau. Fixed + verified.

**Inline menu**
- Glyph category + flex layout, buttons ≥44, RM-gated rise, focus-visible outline giữ, isTrusted gate giữ, no-innerHTML giữ (createElementNS). PASS
- Footer rows (Open Loox / Hide) không icon — phân biệt action vs item có chủ đích. PASS

## Smoke matrix

| Gate | Kết quả |
| --- | --- |
| Unit suite `VaultifyTests` (iPhone 17 Pro, iOS 26.5) | **1358 pass / 0 fail / 1 skip** |
| 4 node harness Safari (classifier/fill/inline/signup) | pass |
| `make check` (app + AutoFill appex iOS) | pass |
| Target `VaultifyAutoFillMac` (build riêng target) | **BUILD SUCCEEDED** |
| Scheme VaultifyAutoFillMac (kéo theo app macOS) | FAIL vì pre-existing `ItemTypePickerSheet.swift:127` iOS-only API (chip đã treo từ 260806, không thuộc đợt này) |
| Popup light/dark/VI 400px + VI 320px | pass |
| Inline menu light (focus thật) | pass |
| Hue parity monogram Swift↔JS | 4/4 trùng |
| ja locale web | strings đủ (audit 260804 đã verify catalog EN/VI/JA); chưa eyeball render ja web đợt này |

## Verdict

**Extension surfaces: SẴN SÀNG production** ở mức pre-signed verification — mọi gate tự động xanh, DNA checklist pass từng mục, 1 finding VoiceOver đã sửa ngay trong audit. Hai việc chỉ làm được trên máy thật/TestFlight (nằm ngoài khả năng môi trường này): UnlockGate runtime trong host Credential Provider thật, và bridge Safari↔native E2E. Cùng giới hạn đã ghi ở audit release-readiness 260804.

## Unresolved

- macOS APP slice vẫn gãy pre-existing (`ItemTypePickerSheet`) — chặn scheme mac, không chặn iOS release. Chip "Fix macOS slice" vẫn treo.
- ja web layer chưa eyeball render (strings verified đủ từ 260804).
- Đề nghị: sau merge, một lần build scheme VaultifySafari trong Xcode để chắc web bundle resources copy (ngoài phạm vi make check).
