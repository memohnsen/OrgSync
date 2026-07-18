project := "OrgSync.xcodeproj"
scheme := "OrgSync"
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
test:
    xcodebuild -project {{project}} -scheme {{scheme}} -destination '{{destination}}' test

# Exercise GitHub authentication, clone, and pull against the ignored local
# reviewer repository credentials. This never writes to the remote branch.
test-live-git:
    @touch .orgsync-live-git-enabled; xcodebuild -project {{project}} -scheme {{scheme}} -destination '{{destination}}' -only-testing:OrgSyncTests/LiveGitHubIntegrationTests test; status=$?; rm -f .orgsync-live-git-enabled; exit $status
