#!/bin/sh
set -eu

cd "$CI_PRIMARY_REPOSITORY_PATH"

if [ -z "${REVENUECAT_API_KEY_LIVE:-}" ]; then
  echo "error: REVENUECAT_API_KEY_LIVE is not set in the Xcode Cloud workflow environment." >&2
  exit 1
fi

{
  echo "REVENUECAT_API_KEY_LIVE=$REVENUECAT_API_KEY_LIVE"
  if [ -n "${REVENUECAT_API_KEY_TEST:-}" ]; then
    echo "REVENUECAT_API_KEY_TEST=$REVENUECAT_API_KEY_TEST"
  fi
} > .env
