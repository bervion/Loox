#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" != "4" ]]; then
  echo "usage: $0 <test-target> <simulator-udid> <derived-data> <result-bundle>" >&2
  exit 64
fi

TEST_TARGET="$1"
SIMULATOR_UDID="$2"
DERIVED_DATA="$3"
RESULT_BUNDLE="$4"

case "$TEST_TARGET" in
  VaultifyTests) TEST_SCHEME="Vaultify-UnitTests" ;;
  VaultifySnapshotTests|VaultifyUITests) TEST_SCHEME="Vaultify-Quality" ;;
  *)
    echo "Unsupported test target: $TEST_TARGET" >&2
    exit 64
    ;;
esac

# CI restores only package source directories here. Xcode still resolves the
# pinned graph and compiles this candidate; no compiled products are restored.
XCODE_ARGUMENTS=(
  -workspace Vaultify.xcworkspace
  -scheme "$TEST_SCHEME"
  -configuration Debug
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID"
  -derivedDataPath "$DERIVED_DATA"
)
if [[ -n "${VAULTIFY_SOURCE_PACKAGES_DIR:-}" ]]; then
  XCODE_ARGUMENTS+=(
    -clonedSourcePackagesDirPath "$VAULTIFY_SOURCE_PACKAGES_DIR"
    -onlyUsePackageVersionsFromResolvedFile
  )
fi
TEST_ARGUMENTS=()
if [[ "$TEST_TARGET" == "VaultifyTests" ]]; then
  # Basic unit results remain in xcresult. Verbose simulator diagnostics can
  # add several minutes after the test host has already finished.
  TEST_ARGUMENTS+=(-collect-test-diagnostics never)
fi

# Persistent-runner hygiene: a cancelled run leaves its result bundle behind in
# RUNNER_TEMP, and xcodebuild refuses to write over an existing one.
rm -rf "$RESULT_BUNDLE" "$RESULT_BUNDLE.summary.json"

# Boot the simulator while the suite compiles. `bootstatus -b` boots a device
# that is shut down and returns once it is fully up; for one the caller already
# booted it returns at once. Its output stays out of the compile log.
BOOT_LOG="$(mktemp)"
xcrun simctl bootstatus "$SIMULATOR_UDID" -b > "$BOOT_LOG" 2>&1 &
BOOT_PID=$!
# If compilation fails, stop the half-booted device so cleanup can delete it.
trap '[[ -n "$BOOT_PID" ]] && kill "$BOOT_PID" 2>/dev/null && xcrun simctl shutdown "$SIMULATOR_UDID" >/dev/null 2>&1; rm -f "$BOOT_LOG"' EXIT

# Ad-hoc signing, the same flags release-local.sh tests with. It needs no
# certificate or secret, but it embeds the app's entitlements: an unsigned
# build has none, so every data-protection Keychain call fails with
# errSecMissingEntitlement (-34018) and the Keychain-backed suites
# (AppAttestKeyStoreTests) cannot pass. The index store only serves Xcode's
# editor features, so CI skips writing it.
set +e
xcodebuild \
  "${XCODE_ARGUMENTS[@]}" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build-for-testing
TEST_STATUS=$?
set -e

if [[ "$TEST_STATUS" == "0" ]]; then
  BOOT_STATUS=0
  wait "$BOOT_PID" || BOOT_STATUS=$?
  BOOT_PID=""  # reaped: the EXIT trap must not signal a reused PID
  if [[ "$BOOT_STATUS" != "0" ]]; then
    echo "Simulator $SIMULATOR_UDID did not finish booting:" >&2
    cat "$BOOT_LOG" >&2
    exit 1
  fi
  set +e
  xcodebuild \
    "${XCODE_ARGUMENTS[@]}" \
    ${TEST_ARGUMENTS[@]+"${TEST_ARGUMENTS[@]}"} \
    -resultBundlePath "$RESULT_BUNDLE" \
    -only-testing:"$TEST_TARGET" \
    test-without-building
  TEST_STATUS=$?
  set -e
fi

if [[ -d "$RESULT_BUNDLE" ]]; then
  xcrun xcresulttool get test-results summary \
    --path "$RESULT_BUNDLE" \
    --format json > "$RESULT_BUNDLE.summary.json"
fi

exit "$TEST_STATUS"
