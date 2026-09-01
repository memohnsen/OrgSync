#!/bin/bash

set -euo pipefail

: "${ASC_TESTFLIGHT_GROUP:?ASC_TESTFLIGHT_GROUP is required}"

app_id="${ASC_APP_ID:-6792388512}"
artifacts_directory=".asc/artifacts"
archive_path="${artifacts_directory}/OrgSync.xcarchive"
ipa_path="${artifacts_directory}/OrgSync.ipa"

asc xcode archive \
  --project OrgSync.xcodeproj \
  --scheme OrgSync \
  --archive-path "$archive_path" \
  --clean \
  --overwrite

asc xcode export \
  --archive-path "$archive_path" \
  --ipa-path "$ipa_path" \
  --overwrite

asc publish testflight \
  --app "$app_id" \
  --ipa "$ipa_path" \
  --group "$ASC_TESTFLIGHT_GROUP" \
  --wait
