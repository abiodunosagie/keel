#!/bin/zsh
# Run the unit tests. They use a fake charge backend and never touch powerd or the SMC.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build
xcodegen generate --quiet

xcodebuild test \
  -project Keel.xcodeproj \
  -scheme Keel \
  -derivedDataPath build/DerivedData \
  -destination 'platform=macOS' \
  -allowProvisioningUpdates > build/test.log 2>&1 && result=0 || result=$?

grep -E "error:|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)|' failed" build/test.log | sort -u | head -40 || true
exit $result
