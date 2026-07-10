# Phase 10 findings — Personas + Profile (persisted by orchestrator; agent's write was hook-blocked)

8 fixed (5 medium, 3 low), 5 surfaces clean pass. Compile green. 5 new strings EN+VI (merged to catalog).

Medium fixed:
1. PersonaSwitcherScreen: swipe-delete persona ZERO confirmation dù deletePersona cascade tombstone alias (verified VaultRepository+PersonaManagement.swift:102-128) → confirmationDialog + copy nói thật hậu quả + Haptics.error trên confirm.
2. ForwardingInboxScreen: delete inbox (contextMenu + swipe) zero confirmation → confirmationDialog (deleteInbox tự no-op nếu đang dùng — gap UX, không phải data-loss).
3. Cả cluster Personas có 0 call Haptics → thêm Haptics.error tại 8 error/destructive sites (3 file), Haptics.tap cho 2 confirm "Pause forwarding". Activate/Confirm email/Check verification để nguyên (chưa có precedent — chờ P15 chốt convention).
4. AliasDetailScreen: 3× "—" placeholder → appString("None") (key có sẵn).
5. ProfileAvatarView: camera badge 30×30 < 44 → contentShape inset -7 (hit-test only).

Low fixed: a11y label "Change photo"; cornerRadius 9→Radius.xs ×2; ProfileScreen 44pt frame + radius 10 → Metric.controlMedium/Radius.sm.

Pass: avatarShape size*0.2 (proportional exemption), ProfileSectionCard lineLimit, AliasDomainPicker/AliasEditorSheet/AffectedAccountsScreen/PersonaKindStyle clean cả 5 câu protocol + 6 grep.
Action census: không có button wall — sheet/dialog đều 2-action toolbar hoặc 1-action confirm; AliasDetail management list = Settings-style rows, không phải CTA stack.
Security: không đụng persona-isolation logic; confirm dialogs là pure UI state.

QA note (device): flow xoá persona có ≥2 alias + xoá manual inbox chưa dùng — confirm step là UI mới.
