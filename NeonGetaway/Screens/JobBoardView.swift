import SwiftUI
import GameCore

/// A Solara freight depot's job board: courier runs to scenic stops, city-to-city deliveries,
/// and long freight hauls in a diesel rig. Take one and the street carries on.
struct JobBoardView: View {
    let depot: ZoneID
    let jobs: [StateJob]
    let onTake: (StateJob) -> Void
    let onClose: () -> Void

    private var city: StateCity? { SolaraState.city(for: depot) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(city?.name ?? "Freight") Depot").pixelLabel(.title2, color: Palette.sunset)
                            .accessibilityAddTraits(.isHeader)
                        Text(city?.tagline ?? "").pixelLabel(.caption, color: Palette.cream.opacity(0.65))
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.title3.weight(.bold)).foregroundStyle(Palette.cream)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close the job board")
                    .accessibilityIdentifier("board.close")
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                            JobRow(job: job) { onTake(job) }
                                .accessibilityIdentifier("board.job.\(index)")
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                Label("Freight lends you a diesel rig. At the other end a car and a bike wait in the yard: take either and drive anywhere.",
                      systemImage: "info.circle")
                    .pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: 620)
            .background(Palette.ink.opacity(0.96))
            .overlay(Rectangle().strokeBorder(Palette.sunset.opacity(0.7), lineWidth: 2))
            .padding(.vertical, 12)
        }
    }
}

private struct JobRow: View {
    let job: StateJob
    let onTake: () -> Void

    private var icon: String {
        switch job.kind {
        case .courier: "shippingbox.fill"
        case .intercity: "car.fill"
        case .freight: "truck.box.fill"
        }
    }

    private var colour: Color {
        switch job.kind {
        case .courier: Palette.teal
        case .intercity: Palette.magenta
        case .freight: Palette.sunset
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(colour)
                .frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.kind.label.uppercased()).pixelLabel(.caption2, color: colour)
                Text("\(job.cargo) → \(job.destinationName(in: SolaraState.district))")
                    .pixelLabel(.callout, color: Palette.cream)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text(String(format: "%.1f km", job.kilometres))
                    if let limit = job.timeLimit {
                        Text("\(Int(limit / 60)):\(String(format: "%02d", Int(limit) % 60)) clock")
                    } else {
                        Text("No clock")
                    }
                    if let reward = job.reward.label { Text("+ \(reward)") }
                }
                .pixelLabel(.caption2, color: Palette.cream.opacity(0.65))
            }
            Spacer(minLength: 6)
            VStack(spacing: 4) {
                Text("\(job.pay) cr").pixelLabel(.headline, color: Palette.sunset)
                Button("Take", action: onTake)
                    .buttonStyle(.neon(colour))
                    .frame(width: 96)
            }
        }
        .padding(10)
        .background(Palette.ink.opacity(0.7))
        .overlay(Rectangle().strokeBorder(colour.opacity(0.4), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Take this job", onTake)
    }
}

/// Solara on the job map: what it is and the way in.
struct SolaraCard: View {
    let onGo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Solara State", systemImage: "map.fill").pixelLabel(.headline, color: Palette.sunset)
                Spacer()
                Text("\(SolaraState.cities.count) cities · \(Set(SolaraState.landmarks.map(\.zone)).count) landmarks")
                    .pixelLabel(.caption2, color: Palette.cream.opacity(0.6))
            }
            Text("Leave Port Aurora behind: drive the highways between six cities, past redwood giants, a granite dome, desert arches and a geyser. Depots pay for courier runs, city-to-city drops and long freight hauls in a diesel rig.")
                .pixelLabel(.caption, color: Palette.cream.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Button("Road trip", action: onGo)
                .buttonStyle(.neon(Palette.sunset))
                .accessibilityHint("Open the big Solara State map with freight jobs")
                .accessibilityIdentifier("map.state")
        }
        .padding(14)
        .background(Palette.ink.opacity(0.6))
        .overlay(Rectangle().strokeBorder(Palette.sunset.opacity(0.7), lineWidth: 2))
    }
}
