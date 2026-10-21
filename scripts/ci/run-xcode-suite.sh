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
XCODE_ARGUMENTS=(-workspace Vaultify.xcworkspace)
if [[ "$TEST_TARGET" == "VaultifyTests" ]]; then
  # Basic unit results remain in xcresult. Verbose simulator diagnostics can
  # add several minutes after the test host has already finished.
  XCODE_ARGUMENTS+=(-collect-test-diagnostics never)
fi
if [[ -n "${VAULTIFY_SOURCE_PACKAGES_DIR:-}" ]]; then
  XCODE_ARGUMENTS+=(
    -clonedSourcePackagesDirPath "$VAULTIFY_SOURCE_PACKAGES_DIR"
    -onlyUsePackageVersionsFromResolvedFile
  )
fi

# Persistent-runner hygiene: a cancelled run leaves its result bundle behind in
# RUNNER_TEMP, and xcodebuild refuses to write over an existing one.
rm -rf "$RESULT_BUNDLE" "$RESULT_BUNDLE.summary.json"

# Ad-hoc signing, the same flags release-local.sh tests with. It needs no
# certificate or secret, but it embeds the app's entitlements: an unsigned
# build has none, so every data-protection Keychain call fails with
# errSecMissingEntitlement (-34018) and the Keychain-backed suites
# (AppAttestKeyStoreTests) cannot pass. The index store only serves Xcode's
# editor features, so test runs skip writing it.
set +e
xcodebuild \
  "${XCODE_ARGUMENTS[@]}" \
  -scheme "$TEST_SCHEME" \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -only-testing:"$TEST_TARGET" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  COMPILER_INDEX_STORE_ENABLE=NO \
  test
TEST_STATUS=$?
set -e

if [[ -d "$RESULT_BUNDLE" ]]; then
  xcrun xcresulttool get test-results summary \
    --path "$RESULT_BUNDLE" \
    --format json > "$RESULT_BUNDLE.summary.json"
fi

exit "$TEST_STATUS"
