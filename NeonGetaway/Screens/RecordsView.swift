import SwiftUI
import GameCore

struct RecordsView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.progress
        ScrollView {
            VStack(spacing: 24) {
                ScreenHeader(title: "Records") { router.back() }
                VStack(spacing: 0) {
                    RecordRow(label: "Credits", value: "\(p.credits)")
                    RecordRow(label: "Rep level", value: "\(model.repLevel)")
                    RecordRow(label: "Reputation XP", value: "\(p.reputationXP)")
                    RecordRow(label: "Jobs completed", value: "\(p.completedJobs)")
                    RecordRow(label: "Best escape streak", value: "\(p.bestEscapeStreak)")
                }
                .overlay(Rectangle().strokeBorder(Palette.teal.opacity(0.6), lineWidth: 2))
                .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Jobs").pixelLabel(.headline, color: Palette.magenta)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(MissionDef.all) { def in
                        let best = p.missionBests[def.id.rawValue]
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(def.title).pixelLabel(.callout)
                                Spacer()
                                Text(def.kind.label).pixelLabel(.caption2, color: Palette.teal)
                            }
                            if let best {
                                HStack(spacing: 18) {
                                    Fact(label: "Best time",
                                         value: best.bestTime.map { String(format: "%.1f s", $0) } ?? "—")
                                    Fact(label: "Best score", value: "\(best.bestScore)")
                                    Fact(label: "Done", value: "\(best.timesCompleted)×")
                                }
                            } else if !ProgressionRules.isUnlocked(def, progress: p) {
                                Label("Unlocks at rep level \(def.requiredRepLevel)", systemImage: "lock.fill")
                                    .font(.pixel(.caption))
                                    .foregroundStyle(Palette.sunset)
                            } else {
                                Text("Not completed yet").pixelLabel(.caption, color: Palette.cream.opacity(0.5))
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(Rectangle().strokeBorder(Palette.magenta.opacity(0.5), lineWidth: 2))
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
        .background(Palette.asphalt.ignoresSafeArea())
    }
}

struct RecordRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).pixelLabel(.callout, color: Palette.cream.opacity(0.8))
            Spacer()
            Text(value).pixelLabel(.title3, color: Palette.teal)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}
