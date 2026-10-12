import SwiftUI
import GameCore

/// Trophies with progress bars and a reward to claim, plus the completion percentage.
struct TrophiesView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.progress
        let ordered = Achievements.all.sorted { rank($0, p) < rank($1, p) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Trophies") { router.back() }
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Int(Achievements.completion(p) * 100))% complete").pixelLabel(.title3, color: Palette.sunset)
                    ProgressBar(fraction: Achievements.completion(p), color: Palette.sunset)
                    Text("\(Achievements.all.filter { $0.isDone(p) }.count) of \(Achievements.all.count) trophies")
                        .pixelLabel(.caption, color: Palette.cream.opacity(0.7))
                }
                ForEach(ordered) { trophy in
                    TrophyRow(trophy: trophy)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
    }

    /// Claimable first, then in progress, then done.
    private func rank(_ a: Achievement, _ p: PlayerProgress) -> Int {
        if a.isDone(p) { return Achievements.isClaimed(a.id, p) ? 2 : 0 }
        return 1
    }
}

private struct TrophyRow: View {
    @Environment(AppModel.self) private var model
    let trophy: Achievement

    var body: some View {
        let p = model.progress
        let done = trophy.isDone(p)
        let claimed = Achievements.isClaimed(trophy.id, p)
        HStack(spacing: 12) {
            Image(systemName: done ? "rosette" : "lock.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(done ? Palette.sunset : Palette.cream.opacity(0.35))
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(trophy.title).pixelLabel(.callout, color: done ? Palette.cream : Palette.cream.opacity(0.75))
                Text(trophy.detail).pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                if !done {
                    ProgressBar(fraction: Double(trophy.progress(p)) / Double(max(1, trophy.goal)), color: Palette.teal)
                    Text("\(trophy.progress(p)) / \(trophy.goal)").pixelLabel(.caption2, color: Palette.cream.opacity(0.5))
                }
            }
            Spacer()
            if done && !claimed {
                Button("+\(trophy.reward)") { _ = model.claimTrophy(trophy.id) }
                    .font(.pixel(.callout))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(Palette.sunset)
                    .accessibilityLabel("Claim \(trophy.reward) credits")
                    .accessibilityIdentifier("trophy.claim.\(trophy.id)")
            } else {
                Text(claimed ? "Claimed" : "\(trophy.reward) cr")
                    .pixelLabel(.caption, color: claimed ? Palette.teal : Palette.cream.opacity(0.5))
            }
        }
        .padding(10)
        .background(Palette.ink.opacity(done && !claimed ? 0.8 : 0.45))
        .overlay(Rectangle().strokeBorder(done && !claimed ? Palette.sunset : Palette.cream.opacity(0.15), lineWidth: 2))
        .accessibilityElement(children: .contain)
    }
}

/// A flat pixel progress bar.
struct ProgressBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Palette.cream.opacity(0.12))
                Rectangle().fill(color).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// Skill levels, what each one does, and how to train it.
struct SkillsView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.progress
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Skills") { router.back() }
                Text("Skills grow by doing. Each level is a small edge, never a wall.")
                    .pixelLabel(.caption, color: Palette.cream.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Skill.allCases) { skill in
                    let xp = p.skills.xp(skill)
                    let level = p.skills.level(skill)
                    let base = Skills.thresholds[level]
                    let toNext = Skills.xpToNext(xp)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(skill.name).pixelLabel(.headline, color: Palette.teal)
                            Spacer()
                            Text("Level \(level) / \(Skills.maxLevel)").pixelLabel(.callout, color: Palette.sunset)
                        }
                        ProgressBar(fraction: toNext.map { Double(xp - base) / Double(xp - base + $0) } ?? 1,
                                    color: Palette.teal)
                        Text(toNext.map { "\($0) XP to level \(level + 1)" } ?? "Maxed out")
                            .pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
                        Text("\(skill.effect). \(skill.howToTrain)")
                            .pixelLabel(.caption, color: Palette.cream.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(Palette.ink.opacity(0.55))
                    .accessibilityElement(children: .combine)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Career").pixelLabel(.headline, color: Palette.magenta)
                    Text("Driven \(Int(p.career.driven / DriveScene.pointsPerMetre / 1_000)) km · ran \(Int(p.career.run / DriveScene.pointsPerMetre)) m · \(p.career.hitsLanded) hits · \(p.career.tickets) tickets")
                        .pixelLabel(.caption, color: Palette.cream.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
    }
}
