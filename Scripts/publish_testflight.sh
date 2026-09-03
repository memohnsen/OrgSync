#!/bin/bash

set -euo pipefail

app_id="${ASC_APP_ID:-6792388512}"
testflight_group="internal"
artifacts_directory=".asc/artifacts"
archive_path="${artifacts_directory}/OrgSync.xcarchive"
ipa_path="${artifacts_directory}/OrgSync.ipa"

if [[ -z "${CI:-}" && -z "${GITHUB_ACTIONS:-}" && -z "${CI_BUILD_NUMBER:-}" ]]; then
  git fetch origin
  if [[ "$(git rev-list --count HEAD.."@{u}")" -gt 0 ]]; then
    git pull --rebase --autostash
  fi
fi

if [[ -n "${CI_BUILD_NUMBER:-}" ]]; then
  build_number="$CI_BUILD_NUMBER"
else
  build_number="$(
    asc builds next-build-number \
      --app "$app_id" \
      --platform IOS \
      --output json \
      | python3 -c 'import json, sys; print(json.load(sys.stdin)["nextBuildNumber"])'
  )"
fi

if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "Refusing to archive with invalid build number: $build_number" >&2
  exit 1
fi

echo "Publishing build ${build_number} to TestFlight group ${testflight_group}"

asc xcode archive \
  --project OrgSync.xcodeproj \
  --scheme OrgSync \
  --archive-path "$archive_path" \
  --clean \
  --overwrite \
  --xcodebuild-flag "-destination" \
  --xcodebuild-flag "generic/platform=iOS" \
  --xcodebuild-flag "CURRENT_PROJECT_VERSION=${build_number}"

asc xcode export \
  --archive-path "$archive_path" \
  --ipa-path "$ipa_path" \
  --overwrite

asc publish testflight \
  --app "$app_id" \
  --ipa "$ipa_path" \
  --group "$testflight_group" \
  --wait
