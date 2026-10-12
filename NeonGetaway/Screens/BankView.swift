import SwiftUI
import GameCore

/// Harbor Savings: park cash, earn 1% a day compounded, and see what it grows to.
struct BankView: View {
    @Environment(Router.self) private var router
    @Environment(AppModel.self) private var model
    @State private var amount = 500
    @State private var message: String?

    var body: some View {
        let p = model.progress
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Harbor Savings") { router.back() }
                HStack {
                    Fact(label: "Cash", value: "\(p.credits)")
                    Spacer()
                    Fact(label: "Saved", value: "\(p.bank.balance)")
                    Spacer()
                    Fact(label: "Interest earned", value: "\(p.bank.interestEarned)")
                }
                .padding(14)
                .background(Palette.ink.opacity(0.6))
                .overlay(Rectangle().strokeBorder(Palette.cream.opacity(0.6), lineWidth: 2))

                VStack(alignment: .leading, spacing: 10) {
                    Stepper(value: $amount, in: 100...50_000, step: 100) {
                        Text("Amount \(amount) cr").pixelLabel(.callout)
                    }
                    .accessibilityIdentifier("bank.amount")
                    HStack(spacing: 10) {
                        Button("Deposit") { message = text(model.deposit(amount), done: "Saved \(amount) cr.") }
                            .buttonStyle(.neon(Palette.teal))
                            .accessibilityIdentifier("bank.deposit")
                        Button("Withdraw") { message = text(model.withdraw(amount), done: "Took out \(amount) cr.") }
                            .buttonStyle(.neon(Palette.sunset))
                            .accessibilityIdentifier("bank.withdraw")
                    }
                    if p.credits > 0 {
                        Button("Save all my cash (\(p.credits))") {
                            let all = model.progress.credits
                            message = text(model.deposit(all), done: "Saved \(all) cr.")
                        }
                        .buttonStyle(.neon(Palette.cream))
                    }
                    if let message {
                        Text(message).pixelLabel(.footnote, color: Palette.sunset)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("What your savings grow to").pixelLabel(.headline, color: Palette.magenta)
                        .accessibilityAddTraits(.isHeader)
                    ForEach([7, 30, 90], id: \.self) { days in
                        HStack {
                            Text("In \(days) days").pixelLabel(.callout, color: Palette.cream.opacity(0.8))
                            Spacer()
                            Text("\(Bank.projected(p.bank.balance, days: days))").pixelLabel(.callout, color: Palette.teal)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text("1% a day, paid every day you've got money in, on up to \(Bank.interestCap). Interest earns interest too: that's compounding. Cash in your pocket earns nothing and pays any tickets first.")
                        .font(.pixel(.footnote, weight: .medium))
                        .foregroundStyle(Palette.cream.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Real savings accounts pay far less than 1% a day, but the maths works the same way.")
                        .font(.pixel(.footnote, weight: .medium))
                        .foregroundStyle(Palette.cream.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(Palette.ink.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.asphalt.ignoresSafeArea())
        .onAppear { model.refreshEconomy() }
    }

    private func text(_ refusal: Bank.Refusal?, done: String) -> String {
        switch refusal {
        case nil: done
        case .badAmount: "Pick an amount first."
        case .notEnoughCash(let needed): "You're \(needed) cr short in cash."
        case .notEnoughSaved(let needed): "You've only got \(model.progress.bank.balance) saved (\(needed) short)."
        }
    }
}
