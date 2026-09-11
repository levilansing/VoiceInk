import Foundation
import os

protocol PolarServicing {
    func checkLicenseRequiresActivation(_ key: String) async throws -> (
        isValid: Bool, requiresActivation: Bool, activationsLimit: Int?
    )
    func activateLicenseKey(_ key: String) async throws -> (activationId: String, activationsLimit: Int)
    func deactivateLicenseKey(_ key: String, activationId: String) async throws
    func validateLicenseKeyWithActivation(_ key: String, activationId: String) async throws -> Bool
}

final class PolarService: PolarServicing {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "PolarService")

    // Check if a license key requires activation (offline: always valid, no activation required)
    func checkLicenseRequiresActivation(_ key: String) async throws -> (
        isValid: Bool, requiresActivation: Bool, activationsLimit: Int?
    ) {
        logger.notice("🔑 Offline license verification: granted")
        return (isValid: true, requiresActivation: false, activationsLimit: 999)
    }

    // Activate a license key on this device (offline)
    func activateLicenseKey(_ key: String) async throws -> (activationId: String, activationsLimit: Int) {
        logger.notice("🔑 Offline license activation: local-activation")
        return (activationId: "local-activation", activationsLimit: 999)
    }

    // Deactivate a license key (offline: no-op)
    func deactivateLicenseKey(_ key: String, activationId: String) async throws {
        logger.notice("🔑 Offline license deactivation completed")
    }

    // Validate a license key with an activation ID (offline: always valid)
    func validateLicenseKeyWithActivation(_ key: String, activationId: String) async throws -> Bool {
        return true
    }
}

enum LicenseError: Error {
    case keyNotFound  // 404 - key doesn't exist in this org
    case activationLimitReached  // 403 - device limit hit
    case serverError(Int)  // unexpected HTTP status
}
