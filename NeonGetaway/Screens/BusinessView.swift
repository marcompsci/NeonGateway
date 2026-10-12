import SwiftUI
import GameCore

/// The player's books, like a small business keeps them: money in, money out, profit, what
/// they own, and short lessons that unlock as they play.
struct BusinessView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.progress
        let books = p.books
        let assets = GarageRules.assetValue(p)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: "Business") { router.back() }

                section("This is your business") {
                    VStack(spacing: 0) {
                        RecordRow(label: "Money in", value: "\(books.income)")
                        RecordRow(label: "Money out", value: "\(books.expenses)")
                        RecordRow(label: "Profit", value: "\(books.profit)")
                        RecordRow(label: "Margin", value: books.margin.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    }
                    .overlay(Rectangle().strokeBorder(Palette.teal.opacity(0.6), lineWidth: 2))
                    Text("Profit is what you keep after costs. Margin is the share of each credit earned that you keep.")
                        .font(.pixel(.footnote, weight: .medium))
                        .foregroundStyle(Palette.cream.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }

                section("What you're worth") {
                    VStack(spacing: 0) {
                        RecordRow(label: "Cash (credits)", value: "\(p.credits)")
                        RecordRow(label: "Cars (\(p.garage.count))", value: "\(assets)")
                        RecordRow(label: "Net worth", value: "\(p.credits + assets)")
                    }
                    .overlay(Rectangle().strokeBorder(Palette.sunset.opacity(0.6), lineWidth: 2))
                }

                section("Where the money went") {
                    VStack(spacing: 6) {
                        ForEach(LedgerCategory.allCases, id: \.self) { category in
                            let total = books.total(category)
                            if total != 0 {
                                PayLine(label: category.label, value: total > 0 ? "+\(total)" : "−\(-total)")
                            }
                        }
                        if books.entries.isEmpty {
                            Text("Nothing yet. Finish a job to make your first sale.")
                                .pixelLabel(.caption, color: Palette.cream.opacity(0.55))
                        }
                    }
                }

                section("Money lessons") {
                    VStack(spacing: 10) {
                        ForEach(Lesson.all) { lesson in
                            LessonCard(lesson: lesson, unlocked: lesson.isUnlocked(p))
                        }
                    }
                }

                if !books.entries.isEmpty {
                    section("Ledger") {
                        VStack(spacing: 6) {
                            ForEach(books.entries.suffix(25).reversed()) { entry in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(entry.note).pixelLabel(.caption, color: Palette.cream.opacity(0.85))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(entry.amount > 0 ? "+\(entry.amount)" : "−\(-entry.amount)")
                                        .pixelLabel(.caption, color: entry.amount > 0 ? Palette.teal : Palette.sunset)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).pixelLabel(.headline, color: Palette.magenta)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

struct LessonCard: View {
    let lesson: Lesson
    let unlocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: unlocked ? "lightbulb.fill" : "lock.fill")
                    .foregroundStyle(unlocked ? Palette.sunset : Palette.cream.opacity(0.4))
                    .accessibilityHidden(true)
                Text(unlocked ? lesson.title : "Locked lesson")
                    .pixelLabel(.callout, color: unlocked ? Palette.cream : Palette.cream.opacity(0.5))
            }
            if unlocked {
                Text(lesson.body)
                    .font(.pixel(.footnote, weight: .medium))
                    .foregroundStyle(Palette.cream.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Keep playing to unlock it.").pixelLabel(.caption2, color: Palette.cream.opacity(0.45))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.ink.opacity(0.5))
        .overlay(Rectangle().strokeBorder(unlocked ? Palette.sunset.opacity(0.6) : Palette.cream.opacity(0.2),
                                          lineWidth: 2))
        .accessibilityElement(children: .combine)
    }
}
