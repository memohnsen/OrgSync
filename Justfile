project := "OrgSync.xcodeproj"
scheme := "OrgSync"
app_id := "6792388512"
simulator := env_var_or_default("IOS_SIMULATOR_ID", "E4A6738D-A7CA-4CF9-A37F-2BB9839A4AF5")
destination := "platform=iOS Simulator,id=" + simulator

# Compile the app for the configured iOS Simulator.
build:
    xcodebuild -project {{project}} -scheme {{scheme}} -destination '{{destination}}' build

# Run the app in the configured simulator (builds and installs first).
run: build
    xcrun simctl boot {{simulator}} || true
    xcrun simctl bootstatus {{simulator}} -b
    xcrun simctl install {{simulator}} "$(xcodebuild -project {{project}} -scheme {{scheme}} -destination '{{destination}}' -showBuildSettings | awk -F ' = ' '/TARGET_BUILD_DIR/ {dir=$2} /WRAPPER_NAME/ {name=$2} END {print dir "/" name}')"
    xcrun simctl launch {{simulator}} com.memohnsen.OrgSync

# Execute the complete unit and UI test suite.
# Exercise GitHub authentication, clone, and pull against the ignored local
# reviewer repository credentials. This never writes to the remote branch.
test:
    xcodebuild -project {{project}} -scheme {{scheme}} -destination '{{destination}}' test
    @touch .orgsync-live-git-enabled; xcodebuild -project {{project}} -scheme {{scheme}} -destination '{{destination}}' -only-testing:OrgSyncTests/LiveGitHubIntegrationTests test; status=$?; rm -f .orgsync-live-git-enabled; exit $status

# Archive the app and upload the build to App Store Connect.
publish:
    asc xcode archive \
        --project {{project}} \
        --scheme {{scheme}} \
        --archive-path .asc/artifacts/OrgSync.xcarchive \
        --clean --overwrite
    asc xcode export \
        --archive-path .asc/artifacts/OrgSync.xcarchive \
        --ipa-path .asc/artifacts/OrgSync.ipa \
        --overwrite
    asc publish appstore \
        --app {{app_id}} \
        --ipa .asc/artifacts/OrgSync.ipa \
        --wait
