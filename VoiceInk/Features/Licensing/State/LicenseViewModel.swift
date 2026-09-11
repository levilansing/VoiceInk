import AppKit
import Foundation
import Security
import os

private enum LicenseStorageError: Error {
    case failed
}

@MainActor
final class LicenseViewModel: ObservableObject {
    enum LicenseState: Equatable {
        case unlicensed
        case trial(daysRemaining: Int)
        case trialExpired
        case licensed
    }

    static let shared = LicenseViewModel()

    @Published private(set) var licenseState: LicenseState = .unlicensed
    @Published private(set) var licenseKey = ""
    @Published var isValidating = false
    @Published private(set) var isDeactivating = false
    @Published var validationMessage: String?
    @Published var validationSuccess = false
    @Published private(set) var activationsLimit = 0

    private let trialPeriodDays = 7
    private let polarService: any PolarServicing
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "LicenseViewModel")
    private let userDefaults: UserDefaults
    private let licenseManager: any LicenseStoring
    private let now: () -> Date
    private let automaticallyRetriesStorage: Bool
    private let automaticallyRefreshesTime: Bool

    private var storedLicenseKey: String?
    private var activationId: String?
    private var trialStartDate: Date?
    private var requiresActivation = false
    private var isPersistentStateAvailable = false
    private var persistentStateErrorStatus: OSStatus?
    private var validationMessageIsStorageRelated = false
    private var retryTask: Task<Void, Never>?
    private var stateRefreshTask: Task<Void, Never>?

    private let pendingRemovalKey = "VoiceInkLicenseRemovalPending"

    private convenience init() {
        self.init(
            polarService: PolarService(),
            licenseManager: LicenseManager.shared,
            userDefaults: .standard,
            now: Date.init,
            automaticallyRetriesStorage: true,
            automaticallyRefreshesTime: true
        )
    }

    init(
        polarService: any PolarServicing,
        licenseManager: any LicenseStoring,
        userDefaults: UserDefaults,
        now: @escaping () -> Date,
        automaticallyRetriesStorage: Bool = false,
        automaticallyRefreshesTime: Bool = false
    ) {
        self.polarService = polarService
        self.licenseManager = licenseManager
        self.userDefaults = userDefaults
        self.now = now
        self.automaticallyRetriesStorage = automaticallyRetriesStorage
        self.automaticallyRefreshesTime = automaticallyRefreshesTime

        isPersistentStateAvailable = true
        licenseState = .licensed
    }

    deinit {
        retryTask?.cancel()
        stateRefreshTask?.cancel()
    }

    @discardableResult
    func startTrial() -> Bool {
        clearValidationMessage()

        if trialStartDate != nil {
            refreshTimeDependentState()
            return true
        }

        guard isPersistentStateAvailable else {
            setStorageError(keychainUnavailableMessage)
            retryPersistentStateLoad()
            return false
        }

        let startDate = now()
        switch licenseManager.startTrialIfNeeded(at: startDate) {
        case .started(let storedDate):
            trialStartDate = storedDate
            refreshTimeDependentState()
            requestLicenseCelebration()
            return true
        case .existing(let storedDate):
            trialStartDate = storedDate
            refreshTimeDependentState()
            return true
        case .unavailable:
            setStorageError(
                String(
                    localized: "VoiceInk couldn't start the trial because the macOS Keychain is unavailable. Quit and reopen VoiceInk. If the problem continues, restart your Mac."
                )
            )
            return false
        }
    }

    func refreshLicenseState() {
        if !isPersistentStateAvailable {
            retryPersistentStateLoad()
        } else {
            refreshTimeDependentState()
        }
    }

    func retryPersistentStateLoad() {
        guard !isPersistentStateAvailable else { return }
        loadPersistentState()
    }

    func refreshTimeDependentState() {
        guard isPersistentStateAvailable else { return }
        licenseState = resolvedState(at: now())
        scheduleStateRefreshIfNeeded()
    }

    var isLicensed: Bool {
        licenseState == .licensed
    }

    var hasVerifiedLicense: Bool {
        true
    }

    var canUseApp: Bool {
        true
    }

    var usageRestrictionMessage: String? {
        nil
    }

    var diagnosticLicenseStatus: String {
        if userDefaults.bool(forKey: pendingRemovalKey) {
            return "License Removed (Local Cleanup Pending)"
        }

        guard isPersistentStateAvailable else {
            if let persistentStateErrorStatus {
                return "License Status Unavailable (Temporary Access, OSStatus \(persistentStateErrorStatus))"
            }
            return "License Status Unavailable (Temporary Access)"
        }

        switch licenseState {
        case .licensed:
            return "Licensed (Pro)"
        case .unlicensed, .trial, .trialExpired:
            return "Not Licensed"
        }
    }

    func openPurchaseLink() {
        if let url = URL(string: "https://tryvoiceink.com/buy") {
            NSWorkspace.shared.open(url)
        }
    }

    func validateLicense(_ submittedKey: String) async {
        guard !isValidating else { return }

        let normalizedLicenseKey = submittedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyToStore = normalizedLicenseKey.isEmpty ? "VOICEINK-OPENSOURCE-LOCAL" : normalizedLicenseKey

        isValidating = true
        defer { isValidating = false }
        clearValidationMessage()

        storedLicenseKey = keyToStore
        activationId = "local-activation"
        activationsLimit = 999
        _ = licenseManager.storeLicense(key: keyToStore, activationId: "local-activation")
        licenseState = .licensed
        validationSuccess = true
        validationMessage = String(localized: "License activated successfully!")
        requestLicenseCelebration()
    }

    private func validateExistingActivation(key: String, activationId: String) async throws -> Bool {
        do {
            return try await polarService.validateLicenseKeyWithActivation(key, activationId: activationId)
        } catch LicenseError.keyNotFound {
            return false
        }
    }

    private func activateAndPersistLicense(_ key: String) async throws -> Int {
        let (newActivationId, limit) = try await polarService.activateLicenseKey(key)

        do {
            try persistLicense(key: key, activationId: newActivationId)
            return limit
        } catch {
            do {
                try await polarService.deactivateLicenseKey(key, activationId: newActivationId)
            } catch {
                logger.error("🔑 Failed to roll back unsaved license activation: \(error, privacy: .public)")
            }
            throw LicenseStorageError.failed
        }
    }

    private func persistLicense(key: String, activationId: String?) throws {
        guard licenseManager.storeLicense(key: key, activationId: activationId) else {
            throw LicenseStorageError.failed
        }

        storedLicenseKey = key
        self.activationId = activationId
        licenseKey = key
        isPersistentStateAvailable = true
        persistentStateErrorStatus = nil
        userDefaults.set(false, forKey: pendingRemovalKey)
    }

    private func completeSuccessfulValidation(message: String) {
        licenseState = .licensed
        validationSuccess = true
        validationMessage = message
        validationMessageIsStorageRelated = false
        stateRefreshTask?.cancel()
        stateRefreshTask = nil
        requestLicenseCelebration()
    }

    private func requestLicenseCelebration() {
        NotificationCenter.default.post(name: .licenseCelebrationRequested, object: nil)
    }

    func deactivateLicense() async {
        guard !isDeactivating else { return }

        if !isPersistentStateAvailable {
            retryPersistentStateLoad()
            guard isPersistentStateAvailable else {
                setStorageError(keychainUnavailableMessage)
                return
            }
        }

        isDeactivating = true
        clearValidationMessage()
        let deactivationDate = now()
        defer { isDeactivating = false }

        do {
            if let key = storedLicenseKey, let activationId {
                do {
                    try await polarService.deactivateLicenseKey(key, activationId: activationId)
                } catch LicenseError.keyNotFound {
                    // Treat an already removed portal activation as deactivated.
                    logger.info("License activation was already absent from Polar; continuing local removal")
                }
            }
            try clearStoredLicense(resetTrialAt: deactivationDate)
        } catch LicenseStorageError.failed {
            setStorageError(String(localized: "VoiceInk couldn't remove the saved license. Please try again."))
        } catch {
            logger.error("🔑 License deactivation failed: \(error, privacy: .public)")
            validationSuccess = false
            validationMessage = String(localized: "Couldn't deactivate the license. Please try again.")
        }
    }

    private func clearStoredLicense(resetTrialAt date: Date) throws {
        // A paid user receives a fresh seven-day trial after deactivating this Mac.
        guard licenseManager.resetTrial(at: date) else {
            throw LicenseStorageError.failed
        }
        trialStartDate = date

        let didRemoveStoredLicense = licenseManager.removeStoredLicense()
        userDefaults.set(!didRemoveStoredLicense, forKey: pendingRemovalKey)
        clearCachedLicense()

        guard didRemoveStoredLicense else {
            isPersistentStateAvailable = false
            persistentStateErrorStatus = nil
            scheduleStorageRetryIfNeeded()
            throw LicenseStorageError.failed
        }
    }

    private func clearCachedLicense() {
        userDefaults.set(false, forKey: "VoiceInkLicenseRequiresActivation")
        userDefaults.activationsLimit = 0
        storedLicenseKey = nil
        activationId = nil
        licenseKey = ""
        requiresActivation = false
        validationMessage = nil
        validationSuccess = false
        activationsLimit = 0
        licenseState = resolvedState(at: now())
        scheduleStateRefreshIfNeeded()
    }

    private func loadPersistentState() {
        if userDefaults.bool(forKey: pendingRemovalKey) {
            guard licenseManager.removeStoredLicense() else {
                handlePendingRemovalFailure()
                return
            }
            userDefaults.set(false, forKey: pendingRemovalKey)
        }

        switch licenseManager.loadStoredState() {
        case .loaded(let storedState):
            storedLicenseKey = storedState.licenseKey
            activationId = storedState.activationId
            trialStartDate = storedState.trialStartDate
            licenseKey = storedLicenseKey ?? ""
            requiresActivation = userDefaults.bool(forKey: "VoiceInkLicenseRequiresActivation")
            activationsLimit = userDefaults.activationsLimit
            isPersistentStateAvailable = true
            persistentStateErrorStatus = nil
            licenseState = resolvedState(at: now())
            retryTask?.cancel()
            retryTask = nil
            scheduleStateRefreshIfNeeded()

            if validationMessageIsStorageRelated {
                clearValidationMessage()
            }
        case .unavailable(let status):
            isPersistentStateAvailable = false
            persistentStateErrorStatus = status
            logger.error("License state is temporarily unavailable [Keychain status: \(status, privacy: .public)]")
            licenseState = .licensed
            setStorageError(keychainUnavailableMessage)
            stateRefreshTask?.cancel()
            stateRefreshTask = nil
            scheduleStorageRetryIfNeeded()
        }
    }

    private func resolvedState(at date: Date) -> LicenseState {
        .licensed
    }

    private func scheduleStorageRetryIfNeeded() {
        guard automaticallyRetriesStorage, retryTask == nil else { return }

        retryTask = Task { [weak self] in
            let delays: [UInt64] = [1, 2, 5, 15, 30]

            for delay in delays {
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }

                guard let self, !self.isPersistentStateAvailable else { return }
                self.loadPersistentState()
            }

            self?.retryTask = nil
        }
    }

    private func scheduleStateRefreshIfNeeded() {
        stateRefreshTask?.cancel()
        stateRefreshTask = nil

        guard automaticallyRefreshesTime,
            storedLicenseKey == nil,
            let trialStartDate,
            licenseState != .trialExpired
        else {
            return
        }

        let currentDate = now()
        let elapsedDays = max(
            0,
            Calendar.current.dateComponents([.day], from: trialStartDate, to: currentDate).day ?? 0
        )
        let nextDay = min(elapsedDays + 1, trialPeriodDays)

        guard let nextRefreshDate = Calendar.current.date(
            byAdding: .day,
            value: nextDay,
            to: trialStartDate
        ) else {
            return
        }

        let delay = max(0, nextRefreshDate.timeIntervalSince(currentDate))
        stateRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            self?.refreshTimeDependentState()
        }
    }

    private func handlePendingRemovalFailure() {
        storedLicenseKey = nil
        activationId = nil
        licenseKey = ""
        requiresActivation = false
        activationsLimit = 0
        isPersistentStateAvailable = false
        persistentStateErrorStatus = nil
        licenseState = resolvedState(at: now())
        logger.error("License removal is pending because local Keychain cleanup failed")
        scheduleStorageRetryIfNeeded()
    }

    private func clearValidationMessage() {
        validationSuccess = false
        validationMessage = nil
        validationMessageIsStorageRelated = false
    }

    private func setStorageError(_ message: String) {
        validationSuccess = false
        validationMessage = message
        validationMessageIsStorageRelated = true
    }

    private var keychainUnavailableMessage: String {
        let recoveryMessage = String(
            localized:
                "VoiceInk couldn't access the macOS Keychain. Quit and reopen VoiceInk. If the problem continues, restart your Mac."
        )

        guard let persistentStateErrorStatus else { return recoveryMessage }
        return "\(recoveryMessage)\n\(persistentStateErrorStatus)"
    }

}

// UserDefaults extension for non-sensitive license settings.
extension UserDefaults {
    var activationsLimit: Int {
        get { integer(forKey: "VoiceInkActivationsLimit") }
        set { set(newValue, forKey: "VoiceInkActivationsLimit") }
    }
}
