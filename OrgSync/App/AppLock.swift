import LocalAuthentication
import SwiftUI

enum AppLockCopy {
    static func requireLockTitleKey(biometryType: LABiometryType) -> String {
        switch biometryType {
        case .touchID:
            return "Require Touch ID"
        case .opticID:
            return "Require Optic ID"
        case .faceID:
            return "Require Face ID"
        default:
            return "Lock with Device Passcode"
        }
    }

    static func requireLockHintKey(biometryType: LABiometryType) -> String {
        switch biometryType {
        case .touchID:
            return "When enabled, OrgSync requires Touch ID or your device passcode to open the app."
        case .opticID:
            return "When enabled, OrgSync requires Optic ID or your device passcode to open the app."
        case .faceID:
            return "When enabled, OrgSync requires Face ID or your device passcode to open the app."
        default:
            return "When enabled, OrgSync requires your device passcode to open the app."
        }
    }

    static func lockSymbolName(biometryType: LABiometryType) -> String {
        switch biometryType {
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .faceID:
            return "faceid"
        default:
            return "lock.fill"
        }
    }
}

enum AppLockAuthentication {
    static func biometryType(context: LAContext = LAContext()) -> LABiometryType {
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        return context.biometryType
    }

    static func evaluateDeviceOwner() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "Unlock OrgSync")
            )
        } catch {
            return false
        }
    }
}

@MainActor
@Observable
final class AppLockController {
    private(set) var phase: AppLockPhase
    private(set) var isEnabled: Bool
    private let authenticate: @MainActor () async -> Bool
    private var inFlight: Task<Void, Never>?
    private var enableGeneration = 0

    var coversContent: Bool { isEnabled && phase != .unlocked }

    init(
        isEnabled: Bool,
        authenticate: @escaping @MainActor () async -> Bool = {
            await AppLockAuthentication.evaluateDeviceOwner()
        }
    ) {
        self.isEnabled = isEnabled
        self.authenticate = authenticate
        self.phase = AppLockPolicy.initialPhase(isEnabled: isEnabled)
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) async -> Bool {
        enableGeneration += 1
        let generation = enableGeneration
        if !enabled {
            inFlight?.cancel()
            inFlight = nil
            apply(.enabledChanged(false))
            return true
        }
        let succeeded = await authenticate()
        guard generation == enableGeneration else { return true }
        if succeeded {
            apply(.enabledChanged(true))
            return true
        }
        return false
    }

    func handle(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            apply(.lifecycle(.active))
        case .inactive:
            apply(.lifecycle(.inactive))
        case .background:
            apply(.lifecycle(.background))
        @unknown default:
            apply(.lifecycle(.inactive))
        }
    }

    func retry() {
        apply(.retryRequested)
    }

    private func apply(_ event: AppLockEvent) {
        let decision = AppLockPolicy.reduce(phase: phase, isEnabled: isEnabled, event: event)
        phase = decision.phase
        isEnabled = decision.isEnabled
        if decision.effect == .authenticate {
            startAuthentication()
        }
    }

    private func startAuthentication() {
        guard inFlight == nil else { return }
        inFlight = Task { [weak self] in
            guard let self else { return }
            let succeeded = await self.authenticate()
            self.inFlight = nil
            guard !Task.isCancelled else { return }
            self.apply(succeeded ? .authenticationSucceeded : .authenticationFailed)
        }
    }
}

struct AppLockOverlay: View {
    let biometryType: LABiometryType
    let isAuthenticating: Bool
    let retry: () -> Void

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: AppLockCopy.lockSymbolName(biometryType: biometryType))
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)

                Text("OrgSync is Locked")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .disabled(isAuthenticating)
                    .accessibilityIdentifier("appLock.retry")
            }
        }
        .accessibilityIdentifier("appLock.screen")
    }
}
