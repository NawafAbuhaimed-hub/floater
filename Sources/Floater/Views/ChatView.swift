import FloaterCore
import SwiftUI

/// The Chat tab: describe work in plain language, review what it proposes,
/// apply or discard.
struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var inputFocused: Bool
    @State private var keyDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            if model.hasAPIKey {
                transcript
                if !model.pendingActions.isEmpty { proposalCard }
                if let error = model.chatError { errorRow(error) }
                composer
            } else {
                setup
            }
        }
        .onAppear { model.prepareChat() }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if model.chatMessages.isEmpty { placeholder }
                    ForEach(model.chatMessages, id: \.id) { message in
                        bubble(message).id(message.id)
                    }
                    if model.isSendingChat || model.isGenerating { thinkingRow.id("thinking") }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: .infinity)
            .onChange(of: model.chatMessages.count) { _, _ in
                if let last = model.chatMessages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tell me what you're working on.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            ForEach([
                "call omar about the lease, then draft the Q3 deck — the deck is blocked on legal",
                "start 45 min on the deck",
                "what's blocked?",
            ], id: \.self) { example in
                Text("\u{201C}\(example)\u{201D}")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    private func bubble(_ message: ChatMessageRecord) -> some View {
        HStack(alignment: .bottom) {
            if message.isUser { Spacer(minLength: 28) }
            Text(message.text)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(message.isUser ? Theme.accent.opacity(0.18) : Color.primary.opacity(0.07))
                )
            if !message.isUser {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Copy")
                Spacer(minLength: 10)
            }
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small).scaleEffect(0.7)
            Text(model.isGenerating ? "Writing…" : "Thinking…")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.leading, 2)
    }

    // MARK: - Proposals

    private var proposalCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Proposed changes")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(model.pendingActions) { proposal in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: proposal.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(proposal.isDestructive
                                         ? AnyShapeStyle(Theme.color(for: .blocked))
                                         : AnyShapeStyle(Theme.accent))
                        .frame(width: 13)
                        .padding(.top, 1)
                    Text(proposal.summary)
                        .font(.system(size: 11.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 6) {
                Button("Apply") { Task { await model.applyProposals() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.accent.opacity(0.24)))
                Button("Discard") { model.discardProposals() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.accent.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.28), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.color(for: .blocked))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 7) {
            TextField("Describe what you're working on…", text: $model.chatDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit { Task { await model.sendChat() } }
            Button { Task { await model.sendChat() } } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(canSend ? Color.white : Color.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(canSend ? Theme.accent : Color.primary.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .padding(.trailing, 14) // clear of the resize grip
        .background(Color.primary.opacity(0.04))
    }

    private var canSend: Bool {
        !model.isSendingChat && !model.chatDraft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - First-run setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Connect Claude")
                .font(.system(size: 13, weight: .semibold))
            Text("Paste an Anthropic API key. It is stored in your macOS Keychain and sent only to api.anthropic.com.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("sk-ant-…", text: $keyDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .onSubmit { save() }
            HStack {
                Button("Save key") { save() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.accent.opacity(0.24)))
                Spacer()
                Text("Uses \(AnthropicClient.defaultModel)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func save() {
        model.saveAPIKey(keyDraft)
        keyDraft = ""
    }
}
