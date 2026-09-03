import Foundation

nonisolated enum AppLockPhase: Equatable, Sendable {
    case unlocked
    case locked
    case authenticating
}

nonisolated enum AppLockLifecycle: Equatable, Sendable {
    case inactive
    case background
    case active
}

nonisolated enum AppLockEvent: Equatable, Sendable {
    case enabledChanged(Bool)
    case lifecycle(AppLockLifecycle)
    case authenticationSucceeded
    case authenticationFailed
    case retryRequested
}

nonisolated enum AppLockEffect: Equatable, Sendable {
    case none
    case authenticate
}

nonisolated struct AppLockDecision: Equatable, Sendable {
    var phase: AppLockPhase
    var isEnabled: Bool
    var effect: AppLockEffect
}

nonisolated enum AppLockPolicy {
    static func initialPhase(isEnabled: Bool) -> AppLockPhase {
        isEnabled ? .locked : .unlocked
    }

    static func reduce(
        phase: AppLockPhase,
        isEnabled: Bool,
        event: AppLockEvent
    ) -> AppLockDecision {
        switch event {
        case .enabledChanged(let enabled):
            if !enabled {
                return AppLockDecision(phase: .unlocked, isEnabled: false, effect: .none)
            }
            return AppLockDecision(phase: phase, isEnabled: true, effect: .none)

        case .lifecycle(.inactive), .lifecycle(.background):
            guard isEnabled else {
                return AppLockDecision(phase: .unlocked, isEnabled: false, effect: .none)
            }
            if phase == .authenticating {
                return AppLockDecision(phase: .authenticating, isEnabled: true, effect: .none)
            }
            return AppLockDecision(phase: .locked, isEnabled: true, effect: .none)

        case .lifecycle(.active):
            guard isEnabled else {
                return AppLockDecision(phase: .unlocked, isEnabled: false, effect: .none)
            }
            switch phase {
            case .unlocked:
                return AppLockDecision(phase: .unlocked, isEnabled: true, effect: .none)
            case .locked:
                return AppLockDecision(phase: .authenticating, isEnabled: true, effect: .authenticate)
            case .authenticating:
                return AppLockDecision(phase: .authenticating, isEnabled: true, effect: .none)
            }

        case .authenticationSucceeded:
            return AppLockDecision(phase: .unlocked, isEnabled: isEnabled, effect: .none)

        case .authenticationFailed:
            guard isEnabled else {
                return AppLockDecision(phase: .unlocked, isEnabled: false, effect: .none)
            }
            return AppLockDecision(phase: .locked, isEnabled: true, effect: .none)

        case .retryRequested:
            guard isEnabled else {
                return AppLockDecision(phase: .unlocked, isEnabled: false, effect: .none)
            }
            return AppLockDecision(phase: .authenticating, isEnabled: true, effect: .authenticate)
        }
    }
}
