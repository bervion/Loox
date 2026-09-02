import DeviceCheck

/// A vanished Enclave key is not always reported as `invalidKey`: asserting with
/// an id whose key no longer exists comes back as `invalidInput`, which fell
/// straight through the recovery below. The device then repeated the same
/// doomed call forever, and reinstalling could not help — the id lives in the
/// Keychain and outlives the install. Both codes mean the same thing here: this
/// key is unusable, and retrying it unchanged cannot help. The one-retry budget
/// still caps how many keys a single request can mint.
nonisolated func appAttestKeyIsDead(_ error: DCError) -> Bool {
    error.code == .invalidKey || error.code == .invalidInput
}
