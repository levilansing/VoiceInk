//
//  VoiceInkTests.swift
//  VoiceInkTests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import Testing
import AppKit
import Carbon.HIToolbox
@testable import VoiceInk

struct VoiceInkTests {

    @Test func testCapsLockShortcutCreationAndDisplay() throws {
        let shortcut = Shortcut.modifierOnly(keyCode: UInt16(kVK_CapsLock), modifierFlags: [.capsLock])
        #expect(shortcut.isCapsLock)
        #expect(shortcut.isModifierOnly)
        #expect(shortcut.displayString == "Caps Lock")
        #expect(shortcut.displayTokens == ["Caps Lock"])
    }

    @Test func testCapsLockShortcutMatching() throws {
        let shortcut = Shortcut.modifierOnly(keyCode: UInt16(kVK_CapsLock), modifierFlags: [.capsLock])
        #expect(shortcut.matchesModifierEvent(keyCode: UInt16(kVK_CapsLock), modifierFlags: [.capsLock]))
        #expect(shortcut.shouldReleaseModifierEvent(keyCode: UInt16(kVK_CapsLock), modifierFlags: []))
        #expect(!shortcut.matchesModifierEvent(keyCode: UInt16(kVK_Shift), modifierFlags: [.shift]))
    }

    @Test func testCapsLockCodableRoundtrip() throws {
        let original = Shortcut.modifierOnly(keyCode: UInt16(kVK_CapsLock), modifierFlags: [.capsLock])
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Shortcut.self, from: encoded)
        #expect(decoded == original)
        #expect(decoded.isCapsLock)
        #expect(decoded.displayString == "Caps Lock")
    }

    @Test func testCapsLockShortcutValidation() throws {
        let shortcut = Shortcut.modifierOnly(keyCode: UInt16(kVK_CapsLock), modifierFlags: [.capsLock])
        let error = ShortcutValidator.validationError(for: shortcut, action: .primaryRecording)
        #expect(error == nil)
    }

    @Test func testLicenseBypassAlwaysLicensed() throws {
        let vm = LicenseViewModel.shared
        #expect(vm.isLicensed)
        #expect(vm.hasVerifiedLicense)
        #expect(vm.canUseApp)
        #expect(vm.usageRestrictionMessage == nil)
        #expect(vm.licenseState == .licensed)
    }

    @Test func testPolarServiceIsCompletelyOffline() async throws {
        let service = PolarService()
        let checkResult = try await service.checkLicenseRequiresActivation("ANY-KEY")
        #expect(checkResult.isValid == true)
        #expect(checkResult.requiresActivation == false)

        let activationResult = try await service.activateLicenseKey("ANY-KEY")
        #expect(activationResult.activationId == "local-activation")

        let validated = try await service.validateLicenseKeyWithActivation("ANY-KEY", activationId: "local-activation")
        #expect(validated == true)
    }

    @Test func testGitHubCLIStarServiceIsDisabled() async {
        let state = await GitHubCLIStarService.checkRemoteStarState()
        #expect(state == .unavailable)

        let starResult = await GitHubCLIStarService.star()
        #expect(starResult == false)
    }

    @Test func testMeaningfulTranscriptionCheck() throws {
        // Empty or whitespace or punctuation should NOT be meaningful
        #expect(!LastTranscriptionService.isMeaningful(""))
        #expect(!LastTranscriptionService.isMeaningful("   "))
        #expect(!LastTranscriptionService.isMeaningful("."))
        #expect(!LastTranscriptionService.isMeaningful("..."))
        #expect(!LastTranscriptionService.isMeaningful("ok"))

        // Meaningful sentences or words should be recognized
        #expect(LastTranscriptionService.isMeaningful("Hello world"))
        #expect(LastTranscriptionService.isMeaningful("This is a long dictation that should be preserved."))
    }
}
