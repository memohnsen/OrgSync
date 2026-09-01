#!/bin/bash

set -euo pipefail

: "${IOS_SIMULATOR_ID:?IOS_SIMULATOR_ID is required}"

xcodebuild \
  -project OrgSync.xcodeproj \
  -scheme OrgSync-CI \
  -destination "platform=iOS Simulator,id=${IOS_SIMULATOR_ID}" \
  -skip-testing:OrgSyncTests/LiveGitHubIntegrationTests \
  -resultBundlePath "${TEST_RESULT_BUNDLE_PATH:-TestResults}" \
  -showBuildTimingSummary \
  test
