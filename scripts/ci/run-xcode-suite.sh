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
  VaultifyTests|VaultifySnapshotTests|VaultifyUITests) ;;
  *)
    echo "Unsupported test target: $TEST_TARGET" >&2
    exit 64
    ;;
esac

set +e
xcodebuild \
  -workspace Vaultify.xcworkspace \
  -scheme Vaultify-Quality \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -only-testing:"$TEST_TARGET" \
  CODE_SIGNING_ALLOWED=NO \
  test
TEST_STATUS=$?
set -e

if [[ -d "$RESULT_BUNDLE" ]]; then
  xcrun xcresulttool get test-results summary \
    --path "$RESULT_BUNDLE" \
    --format json > "$RESULT_BUNDLE.summary.json"
fi

exit "$TEST_STATUS"

