import AppKit
import Foundation

/// A minimal pull-based announcements fetcher that shows one-time in-app banners.
final class AnnouncementsService {
    static let shared = AnnouncementsService()

    private init() {}

    // MARK: - Configuration

    // Hosted via GitHub Pages for this repo
    private let announcementsURL = URL(string: "https://beingpax.github.io/VoiceInk/announcements.json")!

    // Fetch every 4 hours
    private let refreshInterval: TimeInterval = 4 * 60 * 60

    private let dismissedKey = "dismissedAnnouncementIds"
    private let maxDismissedToKeep = 2
    private var timer: Timer?

    // MARK: - Public API
    // Announcements fetching is completely disabled to prevent calling home / remote polling.

    func start() {
        // Disabled: no background network polling
    }

    func stop() {
        // No-op
    }

    // MARK: - Core Logic

    private func fetchAndMaybeShow() {
        // Disabled: no remote network requests
    }

    private func isDismissed(_ id: String) -> Bool {
        let set = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
        return set.contains(id)
    }

    private func markDismissed(_ id: String) {
        var ids = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
        if !ids.contains(id) {
            ids.append(id)
        }
        // Keep only the most recent N ids
        if ids.count > maxDismissedToKeep {
            let overflow = ids.count - maxDismissedToKeep
            ids.removeFirst(overflow)
        }
        UserDefaults.standard.set(ids, forKey: dismissedKey)
    }
}

// MARK: - Models

private struct RemoteAnnouncement: Decodable {
    let id: String
    let title: String
    let description: String?
    let url: String?
    let startAt: String?
    let endAt: String?

    func isActive(at date: Date) -> Bool {
        let formatter = ISO8601DateFormatter()
        if let startAt = startAt, let start = formatter.date(from: startAt), date < start { return false }
        if let endAt = endAt, let end = formatter.date(from: endAt), date > end { return false }
        return true
    }

}
