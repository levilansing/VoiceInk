import AppKit
import SwiftData
import SwiftUI

struct RecorderHistoryButton: View {
    let modelContext: ModelContext?
    var buttonSize: CGFloat = 21

    @State private var isPopoverPresented = false
    @State private var justCopied = false

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(Color(red: 0.25, green: 0.25, blue: 0.27))
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                    )

                if justCopied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Dictation History & Copy (Click to view history or copy last session)")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            RecorderHistoryPopover(
                modelContext: modelContext,
                onCopied: {
                    triggerCopiedFeedback()
                }
            )
        }
    }

    private func triggerCopiedFeedback() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
            justCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.2)) {
                justCopied = false
            }
        }
    }
}

struct RecorderHistoryPopover: View {
    let modelContext: ModelContext?
    let onCopied: () -> Void

    @State private var items: [Transcription] = []
    @State private var copiedItemId: PersistentIdentifier?
    @State private var justCopiedLast = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.12))
            contentList
            Divider().background(Color.white.opacity(0.12))
            footer
        }
        .frame(width: 300)
        .frame(maxHeight: 360)
        .background(Color(red: 0.13, green: 0.13, blue: 0.15))
        .onAppear {
            loadItems()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            Text("Dictation History")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Button {
                copyLastDictation()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: justCopiedLast ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                    Text(justCopiedLast ? "Copied!" : "Copy Last")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(justCopiedLast ? .green : .white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(justCopiedLast ? Color.green.opacity(0.18) : Color.white.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .disabled(items.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var contentList: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No recent dictations")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .padding()
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        ForEach(items) { item in
                            historyRow(for: item)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func historyRow(for item: Transcription) -> some View {
        let isCopied = copiedItemId == item.id
        let text = item.enhancedText?.isEmpty == false ? item.enhancedText! : item.text
        let wordCount = text.split(whereSeparator: \.isWhitespace).count

        return Button {
            copyText(text, for: item.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.timestamp, format: .dateTime.hour().minute())
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))

                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.3))

                    Text("\(wordCount) words")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.45))

                    Spacer()

                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(isCopied ? .green : .white.opacity(0.5))
                }

                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isCopied ? Color.green.opacity(0.12) : Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Text("Dictations are automatically copied to your clipboard.")
                .font(.system(size: 9.5))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func loadItems() {
        items = LastTranscriptionService.getRecentTranscriptions(from: modelContext, limit: 8)
    }

    private func copyLastDictation() {
        if LastTranscriptionService.copyLastTranscription(from: modelContext) {
            withAnimation(.easeInOut(duration: 0.15)) {
                justCopiedLast = true
            }
            onCopied()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    justCopiedLast = false
                }
            }
        }
    }

    private func copyText(_ text: String, for id: PersistentIdentifier) {
        if ClipboardManager.copyToClipboard(text) {
            withAnimation(.easeInOut(duration: 0.15)) {
                copiedItemId = id
            }
            onCopied()
            NotificationManager.shared.showNotification(
                title: String(localized: "Dictation copied to clipboard"),
                type: .success
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedItemId == id {
                    withAnimation {
                        copiedItemId = nil
                    }
                }
            }
        }
    }
}
