import SwiftUI

struct TranscriptionDetailView: View {
    let transcription: Transcription
    var onInfoTap: (() -> Void)?

    private var hasAudioFile: Bool {
        if let urlString = transcription.audioFileURL,
            let url = URL(string: urlString),
            FileManager.default.fileExists(atPath: url.path)
        {
            return true
        }
        return false
    }

    @State private var didCopyBannerText = false

    private var copyTargetText: String {
        transcription.enhancedText ?? transcription.text
    }

    private var canceledBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "slash.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.Status.warningStrong)

            VStack(alignment: .leading, spacing: 2) {
                Text("Canceled Transcription")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.Text.primary)
                Text("This transcription was canceled and was not copied or pasted.")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.Text.secondary)
            }

            Spacer()

            Button {
                let success = ClipboardManager.copyToClipboard(copyTargetText)
                if success {
                    withAnimation { didCopyBannerText = true }
                    NotificationManager.shared.showNotification(
                        title: String(localized: "Transcription copied to clipboard"),
                        type: .success
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { didCopyBannerText = false }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: didCopyBannerText ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                    Text(didCopyBannerText ? "Copied" : "Copy")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(didCopyBannerText ? AppTheme.Status.positive : AppTheme.Text.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(AppTheme.Surface.card)
                )
            }
            .buttonStyle(.plain)
            .help("Copy transcription to clipboard")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(AppTheme.Status.warningStrong.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .strokeBorder(AppTheme.Status.warningStrong.opacity(0.22), lineWidth: 1)
                }
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 16) {
                    if transcription.isCanceled {
                        canceledBanner
                    }

                    MessageBubble(
                        label: "Original",
                        text: transcription.text,
                        isEnhanced: false
                    )

                    if let enhancedText = transcription.enhancedText {
                        MessageBubble(
                            label: "Enhanced",
                            text: enhancedText,
                            isEnhanced: true
                        )
                    }
                }
                .padding(16)
            }

            if hasAudioFile, let urlString = transcription.audioFileURL,
                let url = URL(string: urlString)
            {
                VStack(spacing: 0) {
                    Divider()

                    AudioPlayerView(url: url, transcription: transcription, onInfoTap: onInfoTap)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                .fill(AppTheme.Surface.materialCard)
                                .overlay {
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                        .strokeBorder(AppTheme.Border.card, lineWidth: 1)
                                }
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, 12)
    }
}

private struct MessageBubble: View {
    let label: LocalizedStringKey
    let text: String
    let isEnhanced: Bool

    var body: some View {
        HStack(alignment: .bottom) {
            if isEnhanced { Spacer(minLength: 60) }

            VStack(alignment: isEnhanced ? .leading : .trailing, spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(AppTheme.Text.muted)
                    .padding(.horizontal, 12)

                ScrollView {
                    MarkdownContentView(
                        text,
                        fontSize: 14,
                        foregroundColor: AppTheme.Text.primary,
                        alignment: isEnhanced ? .leading : .trailing
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 350)
                .background {
                    if isEnhanced {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .fill(AppTheme.Surface.subtle)
                            .overlay {
                                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                    .strokeBorder(AppTheme.Border.tint, lineWidth: 1)
                            }
                    } else {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .fill(AppTheme.Surface.materialCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                    .strokeBorder(AppTheme.Border.subtle, lineWidth: 1)
                            )
                    }
                }
                .hoverCopyButton(textToCopy: text)
            }

            if !isEnhanced { Spacer(minLength: 60) }
        }
    }

}
