// The AutoFill extension shares VaultifyCore with the app, and the CloudKit
// paths there are `#if VAULTIFY_ICLOUD`-gated. Compiled without the flag the
// extension still builds and still runs — it just fails closed everywhere that
// matters: `SharedGrantLiveCheck.verify` returns `.unavailable`, so no shared
// item can be filled at all, and `PasskeyApprovalTransport.submitRequest`
// throws `.notConfigured` before reaching the network. The ceremony then
// reports a failure the user cannot act on, for a round trip that never left
// the device.
//
// That is a silent, shipped-blocker class of failure, so assert it at compile
// time rather than waiting for a device to prove it. The matching entitlement
// lives in VaultifyAutoFill.entitlements; the flag is set per-target in
// Project.swift (target settings do not inherit from the app target).
#if !VAULTIFY_ICLOUD
#error("""
VaultifyAutoFill must compile with VAULTIFY_ICLOUD. Add it to the target's \
SWIFT_ACTIVE_COMPILATION_CONDITIONS in Project.swift, then run `tuist generate`. \
Without it every shared-item fill and every ask-each-time passkey fails closed.
""")
#endif
