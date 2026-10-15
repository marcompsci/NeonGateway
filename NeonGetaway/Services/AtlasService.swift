import Foundation
import Observation
import GameCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Atlas, the phone's assistant. On phones with Apple Intelligence it asks Apple's on-device
/// model (no server, nothing leaves the phone), fenced in by `Atlas.instructions` and given only
/// the game's facts and the player's state. Everywhere else it answers from the same facts with
/// `Atlas.answer`.
@MainActor
@Observable
final class AtlasService {
    struct Message: Identifiable, Equatable {
        let id = UUID()
        let fromPlayer: Bool
        var text: String
    }

    private(set) var messages: [Message] = []
    private(set) var thinking = false

    /// True when Apple Intelligence is ready on this phone.
    var usesAppleIntelligence: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), !DebugLaunch.offline {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    var engineLabel: String { usesAppleIntelligence ? "Apple Intelligence · on this phone" : "Built-in answers" }

    func greet(_ name: String?) {
        guard messages.isEmpty else { return }
        let hello = name.map { "Hey \($0). " } ?? "Hey. "
        messages.append(Message(fromPlayer: false, text: hello + "I'm Atlas. Ask me about your businesses, your money, your jobs, or where you're headed."))
    }

    func ask(_ question: String, progress: PlayerProgress, context: AtlasContext?) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !thinking else { return }
        messages.append(Message(fromPlayer: true, text: String(q.prefix(300))))
        thinking = true
        defer { thinking = false }
        let reply = await answer(q, progress: progress, context: context)
        messages.append(Message(fromPlayer: false, text: reply))
    }

    func clear() { messages.removeAll() }

    private func answer(_ q: String, progress: PlayerProgress, context: AtlasContext?) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), usesAppleIntelligence {
            do {
                // A fresh session per question: Atlas only ever sees this prompt's facts and state.
                let session = LanguageModelSession(instructions: Atlas.instructions)
                let prompt = Atlas.prompt(q, progress: progress, context: context)
                let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.3))
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            } catch {
                // Guardrails or a busy model: fall through to the built-in answer.
            }
        }
        #endif
        return Atlas.answer(q, progress: progress, context: context)
    }
}
