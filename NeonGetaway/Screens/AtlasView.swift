import SwiftUI
import GameCore

/// Chat with Atlas. Suggested questions sit above the text field so a tap is enough.
struct AtlasPanel: View {
    @Environment(AppModel.self) private var model
    /// What the player is doing, when asked from inside a drive.
    var context: AtlasContext?
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        let atlas = model.atlas
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Atlas.name).pixelLabel(.title3, color: Palette.teal).accessibilityAddTraits(.isHeader)
                    Text(atlas.engineLabel).pixelLabel(.caption2, color: Palette.cream.opacity(0.55))
                }
                Spacer()
                if !atlas.messages.isEmpty {
                    Button("Clear") { atlas.clear(); atlas.greet(model.progress.profile?.name) }
                        .font(.pixel(.caption))
                        .foregroundStyle(Palette.cream.opacity(0.7))
                        .accessibilityIdentifier("atlas.clear")
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(atlas.messages) { message in
                            Bubble(message: message).id(message.id)
                        }
                        if atlas.thinking {
                            HStack { ProgressView().tint(Palette.teal); Spacer() }
                                .accessibilityLabel("Atlas is thinking")
                        }
                    }
                }
                .frame(minHeight: 60, maxHeight: .infinity)
                .onChange(of: atlas.messages.count) { _, _ in
                    if let last = atlas.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(Atlas.suggestions.enumerated()), id: \.offset) { i, s in
                        Button(s) { send(s) }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.cream)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(Palette.teal.opacity(0.22), in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.teal.opacity(0.6), lineWidth: 1))
                            .accessibilityIdentifier("atlas.suggest.\(i)")
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Ask Atlas…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Palette.cream)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(Palette.ink.opacity(0.8))
                    .overlay(Rectangle().strokeBorder(Palette.teal.opacity(0.5), lineWidth: 1))
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit { send(draft) }
                    .accessibilityIdentifier("atlas.field")
                Button { send(draft) } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundStyle(Palette.teal)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || atlas.thinking)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("atlas.send")
            }
            Text("Atlas only knows Neon Getaway and your progress in it.")
                .pixelLabel(.caption2, color: Palette.cream.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .onAppear { atlas.greet(model.progress.profile?.name) }
    }

    private func send(_ text: String) {
        let q = text
        draft = ""
        typing = false
        Task { await model.atlas.ask(q, progress: model.progress, context: context) }
    }
}

private struct Bubble: View {
    let message: AtlasService.Message

    var body: some View {
        HStack {
            if message.fromPlayer { Spacer(minLength: 40) }
            Text(message.text)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(message.fromPlayer ? Palette.ink : Palette.cream)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(message.fromPlayer ? Palette.teal : Palette.ink.opacity(0.85),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    if !message.fromPlayer {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.teal.opacity(0.4), lineWidth: 1)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !message.fromPlayer { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((message.fromPlayer ? "You: " : "Atlas: ") + message.text)
    }
}

/// Atlas as a full screen from the menu phone.
struct AtlasScreen: View {
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenHeader(title: "Atlas") { router.back() }
            AtlasPanel()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(Palette.asphalt.ignoresSafeArea())
    }
}
