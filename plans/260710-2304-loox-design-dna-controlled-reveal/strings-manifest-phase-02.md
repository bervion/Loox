# Strings Manifest — Phase 2 (Item Detail)

New or changed user-facing strings introduced by Phase 2. `Localizable.xcstrings` is owned by
another agent (P1); the two em-dash renames below were done directly in the catalog by this
phase per the coordinator's explicit exception (P1 had already finished its sweep and would not
re-sync). Everything else in this file is still pending for P1 to append.

## Resolved directly in Localizable.xcstrings (exception granted by coordinator)

| Old key (removed) | New key / EN | VI |
|---|---|---|
| Shared with you — you can use what's listed here, but not edit it. | Shared with you. You can use what's listed here, but not edit it. | Được chia sẻ với bạn. Bạn có thể dùng những gì liệt kê ở đây, nhưng không chỉnh sửa được. |
| Protected — tap to reveal *(ProtectedFieldRow.swift — outside this phase's normal file ownership, edited under the same explicit exception)* | Protected. Tap to reveal | Đã bảo vệ. Chạm để hiện |

## Still pending — P1 to append

| Key / EN | VI |
|---|---|
| Copy Password *(NEW — label on the T3 bottom floating cluster, login items only)* | Sao chép mật khẩu |
| Created %@ · Modified %@ *(NEW — single-line item metadata; replaces two separate lines "Created …" / "Modified …", each already localized; %@ = locale-formatted date/time)* | Đã tạo %@ · Sửa lần cuối %@ |

## Already covered by P1 (no action needed)

- `Copied · clears in %llds` — P1 already added this key (EN implicit via key, VI "Đã sao chép · tự xoá sau %llds"); `DetailFieldRow.swift`'s `copiedFeedbackText` interpolates `\(seconds)s` which matches this exact key format (confirmed against the existing `"New window in %llds"` pattern already in the catalog).
