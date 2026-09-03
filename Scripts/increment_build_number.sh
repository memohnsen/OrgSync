#!/bin/zsh

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
next=$((current + 1))

NEXT_BUILD_NUMBER="$next" /usr/bin/perl -pi -e \
    's/(CURRENT_PROJECT_VERSION = )\d+;/$1 . $ENV{NEXT_BUILD_NUMBER} . q{;}/ge' \
    "$project_file"

print "Updated all build numbers: $current → $next"
