#!/bin/bash

set -euo pipefail

archive_path="${ARCHIVE_PATH:-.ci-artifacts/OrgSync.xcarchive}"

xcodebuild \
  -project OrgSync.xcodeproj \
  -scheme OrgSync \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  archive

test -d "$archive_path"
