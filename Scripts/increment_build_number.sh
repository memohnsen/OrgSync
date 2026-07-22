#!/bin/zsh
# Increment every CURRENT_PROJECT_VERSION in the Xcode project. This script is
# invoked by the OrgSync scheme immediately before an Archive build, not during
# ordinary builds, runs, or tests. CI may set CI_BUILD_NUMBER to use a specific
# build number; this prevents a fresh CI checkout from repeatedly uploading the
# same incremented build number.

set -euo pipefail

script_dir="${0:A:h}"
project_file="${PROJECT_FILE:-${script_dir:h}/OrgSync.xcodeproj/project.pbxproj}"

if [[ ! -f "$project_file" ]]; then
    print -u2 "Build-number script could not find: $project_file"
    exit 1
fi

current_versions=("${(@f)$(/usr/bin/grep -E 'CURRENT_PROJECT_VERSION = [0-9]+;' "$project_file" | /usr/bin/sed -E 's/.*= ([0-9]+);/\1/' | /usr/bin/sort -nu)}")
if (( ${#current_versions[@]} == 0 )); then
    print -u2 "No CURRENT_PROJECT_VERSION values found in $project_file"
    exit 1
fi

current="${current_versions[-1]}"

if [[ -n "${CI_BUILD_NUMBER:-}" ]]; then
    if [[ ! "$CI_BUILD_NUMBER" =~ '^[1-9][0-9]*$' ]]; then
        print -u2 "CI_BUILD_NUMBER must be a positive integer; got: $CI_BUILD_NUMBER"
        exit 1
    fi
    if (( CI_BUILD_NUMBER <= current )); then
        print -u2 "CI_BUILD_NUMBER ($CI_BUILD_NUMBER) must be greater than the current build number ($current)"
        exit 1
    fi
    next="$CI_BUILD_NUMBER"
else
    next=$((current + 1))
fi

NEXT_BUILD_NUMBER="$next" /usr/bin/perl -pi -e \
    's/(CURRENT_PROJECT_VERSION = )\d+;/$1 . $ENV{NEXT_BUILD_NUMBER} . q{;}/ge' \
    "$project_file"

print "Updated all build numbers: $current → $next"
