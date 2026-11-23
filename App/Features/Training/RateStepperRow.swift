import CarbStockCore
import SwiftUI

/// Zeile „Art, Wert g/h“ mit Stepper (Ersteinrichtung und Training › Carbs pro Stunde).
/// Passt alles in eine Zeile, steht es nebeneinander; bei großer Schrift rutscht der Wert mit dem Stepper unter den Namen,
/// damit weder der Name gekürzt noch der Wert umgebrochen wird.
struct RateStepperRow: View {
    let type: SessionType
    @Binding var value: Int

    private var name: some View {
        HStack(spacing: 8) {
            Image(systemName: type.symbol).foregroundStyle(.tint).accessibilityHidden(true)
            Text(type.title)
        }
        .accessibilityHidden(true)
    }
    private var amount: some View {
        Text("\(value) g/h").monospacedDigit().lineLimit(1).fixedSize().accessibilityHidden(true)
    }
    private var stepper: some View {
        // Der ausgeblendete Titel bleibt die Ansage für VoiceOver: „Art, Wert g/h“.
        Stepper("\(type.title), \(value) g/h", value: $value, in: TrainingLimits.carbsPerHour)
            .labelsHidden()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                name.lineLimit(1).fixedSize()
                Spacer(minLength: 8)
                amount
                stepper
            }
            VStack(alignment: .leading, spacing: 8) {
                name.fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    amount
                    Spacer(minLength: 8)
                    stepper
                }
            }
        }
    }
}
