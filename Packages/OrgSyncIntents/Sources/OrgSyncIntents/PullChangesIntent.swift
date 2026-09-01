import AppIntents

/// The app-owned operation behind ``PullChangesIntent``. Keeping the intent in
/// a shared package lets WidgetKit discover the exact same intent type in the
/// app and widget, while the execution target ensures only the app performs it.
@MainActor
public final class PullChangesPerformer {
    public enum Outcome: Sendable {
        case success
        case notConnected
        case failure(String)
    }

    private let operation: @MainActor @Sendable () async -> Outcome

    public init(operation: @escaping @MainActor @Sendable () async -> Outcome) {
        self.operation = operation
    }

    public func pull() async -> Outcome {
        await operation()
    }
}

/// Pulls remote repository changes without bringing OrgSync to the foreground.
public struct PullChangesIntent: AppIntent {
    public static let title: LocalizedStringResource = "Pull Changes"
    public static let description = IntentDescription("Fetch and apply remote Git changes without pushing local edits.")
    public static let supportedModes: IntentModes = .background
    public static var allowedExecutionTargets: ExecutionTargets { .main }

    @Dependency private var performer: PullChangesPerformer

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await performer.pull() {
        case .success:
            return .result(dialog: "Pulled the latest changes.")
        case .notConnected:
            return .result(dialog: "Connect a GitHub repository in Settings first.")
        case .failure(let message):
            return .result(dialog: "Pull failed: \(message)")
        }
    }
}

/// Registers intents that live outside the containing app and widget targets.
public struct OrgSyncIntentsPackage: AppIntentsPackage {
    public init() {}
}
