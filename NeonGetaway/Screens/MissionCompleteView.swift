import SwiftUI
import GameCore

/// Results after a job: outcome, how it went, what it paid, and what to do next.
struct MissionCompleteView: View {
    @Environment(AppModel.self) private var model
    let def: MissionDef
    let result: MissionResult
    let update: ProgressionRules.Update?
    /// Street Challenge only: medal, Nova gap, weekly best.
    var challenge: StreetChallenge.Outcome? = nil
    let onRetry: () -> Void
    let onReturn: () -> Void

    var body: some View {
        let success = result.outcome.isSuccess
        let payout = update?.payout ?? Payout()
        OverlayBackdrop {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(success ? Palette.teal : Palette.sunset)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline).pixelLabel(.largeTitle, color: success ? Palette.teal : Palette.sunset)
                            .accessibilityAddTraits(.isHeader)
                        Text(def.title).pixelLabel(.callout, color: Palette.cream.opacity(0.7))
                    }
                }

                HStack(spacing: 20) {
                    Fact(label: "Time", value: String(format: "%.1f s", result.elapsed))
                    Fact(label: "Hits", value: "\(result.hits)")
                    Fact(label: "Drift", value: "\(Int(result.driftScore))")
                }
                if let challenge, success {
                    ChallengeMedalCard(outcome: challenge, time: result.elapsed)
                } else if update?.newBestTime == true && success {
                    Badge(text: "New best time")
                }

                if success {
                    VStack(spacing: 6) {
                        PayLine(label: "Base pay", value: "+\(payout.base)")
                        PayLine(label: "Speed bonus", value: "+\(payout.timeBonus)")
                        PayLine(label: "Drift bonus", value: "+\(payout.driftBonus)")
                        if payout.damagePenalty > 0 {
                            PayLine(label: "Damage", value: "−\(payout.damagePenalty)")
                        }
                        Rectangle().fill(Palette.cream.opacity(0.3)).frame(height: 1)
                        PayLine(label: "Credits", value: "\(payout.credits)", strong: true)
                        PayLine(label: "Reputation", value: "+\(payout.repXP) XP")
                        PayLine(label: "Score", value: "\(payout.score)")
                    }
                    .padding(14)
                    .overlay(Rectangle().strokeBorder(Palette.teal.opacity(0.6), lineWidth: 2))
                    if let level = update?.leveledUpTo {
                        Badge(text: "Rep level \(level) reached")
                    }
                    ForEach(update?.unlockedJobs ?? [], id: \.self) { id in
                        if let job = MissionDef.with(id) {
                            Badge(text: "New job on the map: \(job.title)", icon: "lock.open.fill")
                        }
                    }
                    if update?.newBestScore == true {
                        Badge(text: "New best score")
                    }
                    if let report = model.lastMarketReport {
                        let sold = report.lines.reduce(0) { $0 + $1.sold }
                        Badge(text: "Your designs sold \(sold) · +\(report.net) cr after fees", icon: "paintbrush.fill")
                    }
                    if let daily = model.lastDaily {
                        if let bonus = daily.streakBonus {
                            Badge(text: "Day \(daily.streak) streak · +\(bonus) cr", icon: "flame.fill")
                        }
                        if let bonus = daily.featuredBonus {
                            Badge(text: "Job of the day · +\(bonus) cr", icon: "calendar")
                        }
                        if daily.earnedShield {
                            Badge(text: "Streak shield earned: covers one missed day", icon: "shield.fill")
                        }
                    }
                    let league = model.progress.league
                    Badge(text: "This week: \(league.earnings) cr · #\(League.rank(model.progress)) in \(league.division.name)",
                          icon: "trophy.fill")
                } else {
                    Text(failureLine)
                        .font(.pixel(.callout, weight: .medium))
                        .foregroundStyle(Palette.cream)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Retry", action: onRetry).buttonStyle(.neon(Palette.magenta))
                    .padding(.top, 4)
                Button("Return to city", action: onReturn).buttonStyle(.neon(Palette.sunset))
            }
        }
    }

    private var icon: String {
        switch result.outcome {
        case .success: "checkmark.seal.fill"
        case .timeUp: "clock.badge.xmark"
        case .busted: "hand.raised.fill"
        case .wrecked: "exclamationmark.triangle.fill"
        case .quit: "xmark.circle"
        case .knockedOut: "bandage.fill"
        }
    }

    private var headline: String {
        switch result.outcome {
        case .success:
            switch def.kind {
            case .escape, .double: "Clean getaway"
            case .pickupRun: "Sweep done"
            case .timedDelivery: def.id == .streetChallenge ? "Finished" : "Delivered"
            }
        case .timeUp: "Time's up"
        case .busted: "Busted"
        case .wrecked: "Wrecked"
        case .quit: "Job dropped"
        case .knockedOut: "Knocked out"
        }
    }

    private var failureLine: String {
        switch result.outcome {
        case .timeUp where def.id == .streetChallenge:
            "The clock ran out before the last checkpoint. Follow Nova's magenta ghost to learn the route, then try again."
        case .timeUp:
            switch def.kind {
            case .pickupRun: "The night market closed before the envelopes got home. No pay this time."
            case .double: "The buyer's boat left before you made the drop. No pay this time."
            default: "The ice melted before the delivery arrived, so this one pays nothing. Retry to take another run at it."
            }
        case .busted: "Harbor Patrol boxed you in. The job's off and nothing pays. Keep moving when they close in."
        case .wrecked: "The car's hull gave out. No pay, and the Garage can add hull points."
        case .knockedOut: "You took one knock too many on foot. No pay this time. A car is safer than your legs."
        default: "No pay this time."
        }
    }
}

/// The Street Challenge result: the medal, how you did against Nova, and your weekly best.
struct ChallengeMedalCard: View {
    let outcome: StreetChallenge.Outcome
    let time: Double

    private var colour: Color {
        switch outcome.medal {
        case .gold: Color(hex: 0xFFD24A)
        case .silver: Color(hex: 0xC9CED8)
        case .bronze: Color(hex: 0xD38A4E)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(colour.opacity(0.22))
                Circle().strokeBorder(colour, lineWidth: 3)
                Image(systemName: "medal.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(colour)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(outcome.medal.label) medal").pixelLabel(.title3, color: colour)
                Text(gapLine).pixelLabel(.callout, color: Palette.cream)
                if outcome.newBest {
                    Text(outcome.previousBest.map { String(format: "New weekly best (was %.1f s)", $0) }
                         ?? "First time on this week's route")
                        .pixelLabel(.caption, color: Palette.teal)
                }
                if outcome.bonus > 0 {
                    Text("Medal bonus +\(outcome.bonus) cr").pixelLabel(.caption, color: Palette.sunset)
                }
            }
        }
        .padding(12)
        .overlay(Rectangle().strokeBorder(colour.opacity(0.6), lineWidth: 2))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("challenge.medal")
    }

    private var gapLine: String {
        let gap = abs(outcome.gapToRival)
        return outcome.gapToRival <= 0
            ? String(format: "You beat %@ by %.1f s", StreetChallenge.rivalName, gap)
            : String(format: "%@ was %.1f s faster", StreetChallenge.rivalName, gap)
    }
}

struct PayLine: View {
    let label: String
    let value: String
    var strong = false

    var body: some View {
        HStack {
            Text(label).pixelLabel(strong ? .headline : .callout, color: Palette.cream.opacity(strong ? 1 : 0.75))
            Spacer()
            Text(value).pixelLabel(strong ? .title3 : .callout, color: strong ? Palette.sunset : Palette.cream)
        }
        .accessibilityElement(children: .combine)
    }
}

struct Badge: View {
    let text: String
    var icon = "star.fill"

    var body: some View {
        Label(text, systemImage: icon)
            .font(.pixel(.footnote))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Palette.sunset)
    }
}
