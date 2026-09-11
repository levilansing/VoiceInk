import Foundation
import SwiftData

class LastTranscriptionService: ObservableObject {

    static func isMeaningful(_ text: String?) -> Bool {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return false
        }
        let alphanumeric = text.filter { $0.isLetter || $0.isNumber }
        return alphanumeric.count >= 3
    }

    static func getLastTranscription(from modelContext: ModelContext) -> Transcription? {
        getLastMeaningfulTranscription(from: modelContext)
    }

    static func getLastMeaningfulTranscription(from modelContext: ModelContext?) -> Transcription? {
        guard let modelContext else { return nil }
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 20

        do {
            let transcriptions = try modelContext.fetch(descriptor)
            // Prioritize the most recent completed transcription with meaningful text
            for item in transcriptions where item.transcriptionStatus == TranscriptionStatus.completed.rawValue {
                let candidateText = item.enhancedText?.isEmpty == false ? item.enhancedText! : item.text
                if isMeaningful(candidateText) {
                    return item
                }
            }
            // Fallback to any completed transcription
            return transcriptions.first(where: { $0.transcriptionStatus == TranscriptionStatus.completed.rawValue })
        } catch {
            print("Error fetching last transcription: \(error)")
            return nil
        }
    }

    static func getRecentTranscriptions(from modelContext: ModelContext?, limit: Int = 8) -> [Transcription] {
        guard let modelContext else { return [] }
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit * 2

        do {
            let transcriptions = try modelContext.fetch(descriptor)
            let completed = transcriptions.filter { $0.transcriptionStatus == TranscriptionStatus.completed.rawValue }
            return Array(completed.prefix(limit))
        } catch {
            print("Error fetching recent transcriptions: \(error)")
            return []
        }
    }

    @discardableResult
    static func copyLastTranscription(from modelContext: ModelContext?) -> Bool {
        guard let lastTranscription = getLastMeaningfulTranscription(from: modelContext) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: String(localized: "No transcription available"),
                    type: .error
                )
            }
            return false
        }

        // Prefer enhanced text; fallback to original text
        let textToCopy: String = {
            if let enhancedText = lastTranscription.enhancedText, !enhancedText.isEmpty {
                return enhancedText
            } else {
                return lastTranscription.text
            }
        }()

        let success = ClipboardManager.copyToClipboard(textToCopy)

        Task { @MainActor in
            if success {
                NotificationManager.shared.showNotification(
                    title: String(localized: "Last dictation copied"),
                    type: .success
                )
            } else {
                NotificationManager.shared.showNotification(
                    title: String(localized: "Failed to copy transcription"),
                    type: .error
                )
            }
        }
        return success
    }

    static func pasteLastTranscription(from modelContext: ModelContext) {
        guard let lastTranscription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: String(localized: "No transcription available"),
                    type: .error
                )
            }
            return
        }

        let textToPaste = lastTranscription.text

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CursorPaster.pasteAtCursor(textToPaste)
        }
    }

    static func pasteLastEnhancement(from modelContext: ModelContext) {
        guard let lastTranscription = getLastTranscription(from: modelContext) else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: String(localized: "No transcription available"),
                    type: .error
                )
            }
            return
        }

        // Prefer enhanced text; if unavailable, fallback to original text (which may contain an error message)
        let textToPaste: String = {
            if let enhancedText = lastTranscription.enhancedText, !enhancedText.isEmpty {
                return enhancedText
            } else {
                return lastTranscription.text
            }
        }()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CursorPaster.pasteAtCursor(textToPaste)
        }
    }

    static func retryLastTranscription(
        from modelContext: ModelContext, transcriptionModelManager: TranscriptionModelManager,
        serviceRegistry: TranscriptionServiceRegistry, enhancementService: AIEnhancementService?
    ) {
        Task { @MainActor in
            guard let lastTranscription = getLastTranscription(from: modelContext),
                let audioURLString = lastTranscription.audioFileURL,
                let audioURL = URL(string: audioURLString),
                FileManager.default.fileExists(atPath: audioURL.path)
            else {
                NotificationManager.shared.showNotification(
                    title: String(localized: "Cannot retry: Audio file not found"),
                    type: .error
                )
                return
            }

            guard
                let transcriptionConfiguration = ModeRuntimeResolver.transcriptionConfiguration(
                    transcriptionModelManager: transcriptionModelManager
                )
            else {
                NotificationManager.shared.showNotification(
                    title: String(localized: "No transcription model selected"),
                    type: .error
                )
                return
            }

            let transcriptionService = AudioTranscriptionService(
                modelContext: modelContext,
                serviceRegistry: serviceRegistry,
                enhancementService: enhancementService
            )
            do {
                let result = try await transcriptionService.retranscribeAudio(
                    from: audioURL,
                    using: transcriptionConfiguration.model
                )
                let newTranscription = result.transcription

                let textToCopy =
                    result.enhancementFailure == nil && newTranscription.enhancedText?.isEmpty == false
                    ? newTranscription.enhancedText! : newTranscription.text
                _ = ClipboardManager.copyToClipboard(textToCopy)

                if let enhancementFailure = result.enhancementFailure {
                    NotificationManager.shared.showNotification(
                        title: EnhancementFailureFormatter.transcriptionSavedMessage(
                            description: enhancementFailure
                        ),
                        type: .warning
                    )
                } else {
                    NotificationManager.shared.showNotification(
                        title: String(localized: "Copied to clipboard"),
                        type: .success
                    )
                }
            } catch {
                NotificationManager.shared.showNotification(
                    title: String(format: String(localized: "Retry failed: %@"), error.localizedDescription),
                    type: .error
                )
            }
        }
    }
}
