# Strings manifest — Phase 11 (Sharing owner/approval/recipient)

Only ONE string changed wording this phase (button-hierarchy rework moved "Check Now" off the
button row into the toolbar overflow menu, so the exhausted-poll hint can no longer tell the
owner to "tap Check Now"). Every other touched string reuses an existing catalog key verbatim
(no new key). Orchestrator: append-only merge by key.

| key (EN, also the lookup key) | EN | VI | context |
|---|---|---|---|
| `Still waiting. You can close this screen and finish later, or check again from the menu above.` | Still waiting. You can close this screen and finish later, or check again from the menu above. | Vẫn đang chờ. Bạn có thể đóng màn hình này và hoàn tất sau, hoặc kiểm tra lại từ menu phía trên. | `ShareAccessSheet.waitingView` — replaces the old "…or tap Check Now." hint now that Check Now lives in the toolbar `•••` menu, not a button on this row. |

## Reused, unchanged keys (no manifest action needed)
- `Check Now` — reused as the toolbar-menu label in both `ShareAccessSheet` (new) and
  `ShareResumeStepperSheet` (unchanged, already existed as a button label).
- `Cancel Invite` — reused as the toolbar-menu label in `ShareResumeStepperSheet` (unchanged,
  already existed as a button label + confirmation-dialog action).
- `Done`, `Nudge via Messages`, `Share Invite Link`, `Reject`, `Approve with Face ID` — unchanged,
  only their button style/rank moved.
