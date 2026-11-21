import CarbStockCore
import SwiftData
import SwiftUI

extension Ampel {
    var title: String {
        switch self {
        case .enough: "Reicht"
        case .tight: "Knapp"
        case .shortage: "Engpass"
        }
    }
    var symbol: String {
        switch self {
        case .enough: "checkmark.circle.fill"
        case .tight: "exclamationmark.triangle.fill"
        case .shortage: "xmark.octagon.fill"
        }
    }
    var color: Color {
        switch self {
        case .enough: .green
        case .tight: .orange
        case .shortage: .red
        }
    }
}

/// Texte der Reichweite (Spec 4.3, AC-P3/P4/P5), getrennt von der Ansicht, damit sie testbar sind.
enum RunwayText {
    static func headline(_ s: RunwayStatement) -> String {
        switch s {
        case .unknown: "Bedarf unbekannt"
        case .reaches(let weeks, _): "Reicht ≈ \(Fmt.weeks(weeks)) Wochen"
        case .atLeast: "Reicht mindestens bis \(Fmt.date(untilOf(s)!))"
        }
    }

    static func detail(_ s: RunwayStatement, today: CalendarDay) -> String {
        switch s {
        case .unknown:
            "Bitte trag Sessions oder eine Wochenvorlage ein. Ohne Bedarf kann die App keine Reichweite nennen."
        case .reaches(_, let until):
            "Bis \(Fmt.date(until)) (heute + \(today.days(until: until)) Tage)."
        case .atLeast:
            "Danach ist kein Bedarf eingetragen, darüber hinaus gibt es keine belastbare Aussage."
        }
    }

    private static func untilOf(_ s: RunwayStatement) -> CalendarDay? {
        switch s {
        case .reaches(_, let d), .atLeast(let d): d
        case .unknown: nil
        }
    }
}

struct DemandView: View {
    @Environment(\.modelContext) private var context
    // Observed so the forecast refreshes after every booking, session or rate change.
    @Query private var products: [Product]
    @Query private var movements: [StockMovement]
    @Query private var sessions: [TrainingSession]
    @Query private var templates: [WeeklyTemplateRecord]
    @Query private var rates: [CarbRateOverride]
    @State private var router = AppRouter.shared

    private var service: TrainingService { TrainingService(context: context) }

    var body: some View {
        let today = Fmt.today()
        let report = service.report()
        let statement = RunwayStatement(simulation: report.simulation, series: report.series)
        NavigationStack {
            List {
                if statement == .unknown {
                    Section {
                        ContentUnavailableView {
                            Label("Bedarf unbekannt", systemImage: "questionmark.circle")
                        } description: {
                            Text("Bitte trag Sessions oder eine Wochenvorlage ein. Ohne Bedarf nennt die App keine Reichweite.")
                        } actions: {
                            Button("Zum Training") { router.selectedTab = .training }.buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    runwaySection(statement, today: today, report: report)
                }
                windowsSection(report)
                if !report.simulation.losses.isEmpty { lossSection(report.simulation) }
                if let gap = report.simulation.supplyGap { gapSection(gap) }
                categorySection()
                Section {
                    Text("Der Bedarf wird aus Sessions und Wochenvorlage berechnet. Nur Gesamt-Carbs, keine Aussage über Verträglichkeit oder Ernährung.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Bedarf")
        }
    }

    // MARK: Sections

    private func runwaySection(_ s: RunwayStatement, today: CalendarDay, report: ForecastReport) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(RunwayText.headline(s)).font(.title2.bold())
                Text(RunwayText.detail(s, today: today)).font(.subheadline).foregroundStyle(.secondary)
                if case .atLeast = s, report.series.reachedCap {
                    Text("Berechnet über maximal \(report.series.knownDays) Tage.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private func windowsSection(_ report: ForecastReport) -> some View {
        Section {
            ForEach(report.windows, id: \.days) { w in WindowRow(window: w) }
        } header: { Text("Bedarf und nutzbarer Bestand") } footer: {
            Text("Nutzbar = Bestand jetzt, abzüglich dem, was im Zeitraum vor dem MHD nicht mehr verbraucht wird. Knapp: Bestand 100 bis unter 110 % des Bedarfs.")
        }
    }

    private func lossSection(_ sim: SimulationResult) -> some View {
        let names = batchNames()
        return Section {
            ForEach(sim.losses, id: \.batchID) { loss in
                VStack(alignment: .leading, spacing: 2) {
                    Text(names[loss.batchID] ?? "Charge").font(.body)
                    Text("\(loss.lostQuantity) Stück · \(Fmt.grams(loss.lostCarbsG)) Carbs laufen am \(Fmt.date(loss.expiry)) unverbraucht ab")
                        .font(.footnote).foregroundStyle(.orange)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Label("Verfallsrisiko", systemImage: "hourglass.bottomhalf.filled")
        } footer: {
            Text("Diese Menge wird bis zum MHD voraussichtlich nicht mehr verbraucht, wenn immer die früher ablaufende Ware zuerst drankommt. Tipp: früher einplanen oder weitergeben.")
        }
    }

    private func gapSection(_ gap: SupplyGap) -> some View {
        Section {
            Label {
                Text("Ab \(Fmt.date(gap.day)) deckt der nutzbare Bestand (\(Fmt.grams(gap.usableCarbsG))) den Bedarf der nächsten 7 Tage (\(Fmt.grams(gap.demandNext7DaysG))) nicht mehr, weil Ware abgelaufen ist.")
            } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red) }
        } header: { Text("Versorgungslücke") }
    }

    @ViewBuilder
    private func categorySection() -> some View {
        let shares = service.stockBreakdown()
        let total = shares.reduce(0) { $0 + $1.carbsG }
        if total > 0 {
            Section("Bestand nach Kategorie") {
                ForEach(shares, id: \.category) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(s.category.title, systemImage: s.category.symbol)
                            Spacer()
                            Text(Fmt.grams(s.carbsG)).monospacedDigit()
                        }
                        ProgressView(value: s.carbsG, total: total).accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func batchNames() -> [UUID: String] {
        var out: [UUID: String] = [:]
        for p in products { for b in p.batches ?? [] { out[b.id] = p.name } }
        return out
    }
}

struct WindowRow: View {
    let window: ForecastWindow

    private var title: String { window.days % 7 == 0 ? (window.days == 7 ? "1 Woche" : "\(window.days / 7) Wochen") : "\(window.days) Tage" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let ampel = window.ampel {
                    Label(ampel.title, systemImage: ampel.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(ampel.color)
                } else {
                    Label("Bedarf unvollständig", systemImage: "questionmark.circle").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            LabeledContent("Bedarf", value: Fmt.grams(window.demandG) + (window.isDemandComplete ? "" : " (bisher bekannt)"))
            LabeledContent("Nutzbarer Bestand", value: Fmt.grams(window.usableStockG))
            if window.isDemandComplete || window.differenceG < 0 {
                LabeledContent(window.differenceG < 0 ? "Fehlmenge" : "Überschuss", value: Fmt.grams(abs(window.differenceG)))
                    .foregroundStyle(window.differenceG < 0 ? .red : .primary)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
