#!/bin/bash

set -euo pipefail

environment_file="$SRCROOT/.env"
plist_path="$TARGET_BUILD_DIR/$INFOPLIST_PATH"

if [[ "$CONFIGURATION" == "Release" ]]; then
  variable_name="REVENUECAT_API_KEY_LIVE"
else
  variable_name="REVENUECAT_API_KEY_TEST"
fi

key="${!variable_name:-}"
if [[ -z "$key" && -f "$environment_file" ]]; then
  key="$(grep -E "^${variable_name}=" "$environment_file" | tail -1 | cut -d= -f2- || true)"
fi

# Preserve compatibility with local environments that use the legacy name.
if [[ -z "$key" ]]; then
  key="${REVENUECAT_API_KEY:-}"
fi
if [[ -z "$key" && -f "$environment_file" ]]; then
  key="$(grep -E '^REVENUECAT_API_KEY=' "$environment_file" | tail -1 | cut -d= -f2- || true)"
fi

if [[ "$CONFIGURATION" == "Release" && -z "$key" ]]; then
  echo "error: REVENUECAT_API_KEY_LIVE missing from the environment and .env; refusing to archive without the live RevenueCat key."
  exit 1
fi

if [[ -n "$key" && -f "$plist_path" ]]; then
  /usr/libexec/PlistBuddy -c "Set :RevenueCatAPIKey $key" "$plist_path"
fi
