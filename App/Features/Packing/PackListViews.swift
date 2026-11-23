import CarbStockCore
import SwiftData
import SwiftUI

extension PackService.Failure {
    var message: String {
        switch self {
        case .invalid: "Bitte prüfe Name, Ziel und Reserve."
        case .listFinished: "Diese Packliste ist fertig und kann nicht mehr geändert werden. Korrekturen laufen über normale Buchungen im Bestand."
        case .batchMissing: "Die Charge dieses Postens gibt es nicht mehr."
        case .insufficientStock(let n): "Von dieser Charge fehlen \(n) Einheiten. Bitte Bestand prüfen oder die Liste neu berechnen."
        case .nothingToReturn: "Es ist nichts zum Zurücklegen da."
        case .returnTooMuch: "So viel wurde nicht gepackt."
        case .hasPackedItems: "Bitte erst die Haken entfernen, sonst bleibt der Bestand abgebucht."
        }
    }
}

/// Liste aller Packlisten (Training-Tab → Packlisten).
struct PackListsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PackList.createdAt, order: .reverse) private var lists: [PackList]
    @State private var adding = false
    @State private var errorText: String?

    private var service: PackService { PackService(context: context) }

    var body: some View {
        List {
            if lists.isEmpty {
                ContentUnavailableView {
                    Label("Keine Packlisten", systemImage: "checklist")
                } description: {
                    Text("Aus einer Session oder einem freien Ziel (z. B. 300 g Carbs) berechnet die App, was du einpackst.")
                } actions: {
                    Button("Packliste anlegen") { adding = true }.buttonStyle(.borderedProminent)
                }
            }
            ForEach(lists) { list in
                NavigationLink { PackListDetailView(list: list) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(list.title)
                        Text("\(stateTitle(list.stateRaw)) · Ziel \(Fmt.grams(list.targetCarbsG))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .swipeActions {
                    Button("Löschen", systemImage: "trash", role: .destructive) {
                        do { try service.delete(list) } catch let e as PackService.Failure { errorText = e.message } catch { errorText = "Löschen hat nicht geklappt." }
                    }
                }
            }
        }
        .navigationTitle("Packlisten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Packliste anlegen", systemImage: "plus") { adding = true } } }
        .sheet(isPresented: $adding) { PackListFormView() }
        .alert("Aktion nicht möglich", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }
}

func stateTitle(_ raw: String) -> String {
    switch raw {
    case "packing": "Beim Packen"
    case "done": "Fertig"
    default: "Entwurf"
    }
}

struct PackListFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TrainingSession.day) private var sessions: [TrainingSession]
    @Query private var products: [Product]
    @Query private var movements: [StockMovement]

    @State private var draft = PackListDraft()
    @State private var fromSession = true
    @State private var chosen: UUID?
    @State private var freeTarget = 300
    @State private var errorText: String?

    private var service: PackService { PackService(context: context) }

    private var upcoming: [PlannedSession] {
        let today = Fmt.today()
        return sessions.compactMap(\.info).filter { $0.day >= today && $0.status == .planned }.sorted { $0.day < $1.day }
    }

    var body: some View {
        let userRates = TrainingService(context: context).userRates()
        let current = resolved(userRates)
        let plan = service.plan(for: current)
        let names = Dictionary(products.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        NavigationStack {
            Form {
                Section {
                    Picker("Quelle", selection: $fromSession) {
                        Text("Session").tag(true)
                        Text("Freies Ziel").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if fromSession {
                        if upcoming.isEmpty {
                            Text("Keine geplante Session in der Zukunft. Lege eine an oder wähle „Freies Ziel“.").font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Picker("Session", selection: $chosen) {
                                ForEach(upcoming) { s in
                                    Text("\(Fmt.weekdayDate(s.day)) · \(s.type.title) · \(Fmt.grams(DemandCalculator.sessionDemandG(s, userRates: userRates)))")
                                        .tag(Optional(s.id))
                                }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }
                    } else {
                        Stepper(value: $freeTarget, in: 50...3000, step: 50) {
                            LabeledContent("Ziel", value: Fmt.grams(Double(freeTarget)))
                        }
                    }
                    TextField("Name der Packliste", text: $draft.title)
                }
                Section {
                    Stepper(value: $draft.reservePercent, in: 0...50, step: 5) {
                        LabeledContent("Reserve", value: "\(draft.reservePercent) %")
                    }
                    LabeledContent("Ziel inkl. Reserve", value: Fmt.grams(current.targetG)).fontWeight(.semibold)
                } header: { Text("Menge") } footer: {
                    Text("Die Reserve ist ein Puffer obendrauf, kein Rat zur Ernährung. 0 % ist möglich.")
                }
                Section {
                    Toggle("Nach Kategorien aufteilen", isOn: $draft.useShares)
                    if draft.useShares {
                        ForEach([ProductCategory.gel, .drink, .bar, .jelly], id: \.self) { c in
                            Stepper(value: shareBinding(c), in: 0...100, step: 10) {
                                LabeledContent(c.title, value: "\(draft.sharesPercent[c] ?? 0) %")
                            }
                        }
                    }
                } footer: {
                    Text(draft.useShares ? "Die Anteile werden auf 100 % hochgerechnet." : "Ohne Anteile nimmt die App, was als Nächstes abläuft (zuerst aufbrauchen).")
                }
                Section("Vorschau") {
                    if plan.items.isEmpty {
                        Text("Kein nutzbarer Bestand für diese Menge.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(plan.items.enumerated()), id: \.offset) { _, i in
                        LabeledContent("\(i.units) × \(names[i.productID] ?? "Produkt")", value: Fmt.grams(i.carbsG))
                    }
                    if !plan.items.isEmpty { LabeledContent("Summe", value: Fmt.grams(plan.totalCarbsG)).fontWeight(.semibold) }
                    if plan.shortfallG > 0 {
                        Label("Es fehlen ≈ \(Fmt.grams(plan.shortfallG)) Carbs im Bestand.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                if let errorText { Section { Text(errorText).foregroundStyle(.red) } }
            }
            .navigationTitle("Neue Packliste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Anlegen") { save(current) }.disabled(!current.problems.isEmpty) }
            }
            .onAppear {
                if chosen == nil { chosen = upcoming.first?.id }
                if upcoming.isEmpty { fromSession = false }
                if draft.sharesPercent.isEmpty { draft.sharesPercent = [.gel: 50, .drink: 30, .bar: 20] }
            }
        }
    }

    /// The draft with demand and session link filled in from the current choice.
    private func resolved(_ userRates: [SessionType: Int]) -> PackListDraft {
        var d = draft
        if fromSession, let s = upcoming.first(where: { $0.id == chosen }) {
            d.sessionID = s.id
            d.demandG = DemandCalculator.sessionDemandG(s, userRates: userRates)
            if d.title.isEmpty { d.title = "\(Fmt.weekdayDate(s.day)) \(sessions.first { $0.id == s.id }?.title ?? s.type.title)" }
        } else {
            d.sessionID = nil
            d.demandG = Double(freeTarget)
            if d.title.isEmpty { d.title = "Ziel \(Fmt.grams(Double(freeTarget)))" }
        }
        return d
    }

    private func shareBinding(_ c: ProductCategory) -> Binding<Int> {
        Binding(get: { draft.sharesPercent[c] ?? 0 }, set: { draft.sharesPercent[c] = $0 })
    }

    private func save(_ d: PackListDraft) {
        do { try service.create(d); dismiss() } catch let e as PackService.Failure { errorText = e.message } catch { errorText = "Anlegen hat nicht geklappt." }
    }
}

struct PackListDetailView: View {
    let list: PackList
    @Environment(\.modelContext) private var context
    // Observed: ticks and put-backs are movements, the list must follow them.
    @Query private var movements: [StockMovement]
    @Query private var products: [Product]
    @State private var puttingBack: PackListItem?
    @State private var errorText: String?
    @State private var confirmFinish = false

    private var service: PackService { PackService(context: context) }
    private var finished: Bool { list.stateRaw == "done" }

    var body: some View {
        let ledger = InventoryService(context: context).ledger()
        let items = service.items(of: list)
        let names = Dictionary(products.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        let expiries = Dictionary(products.flatMap { $0.batches ?? [] }.map { ($0.id, $0.expiryDay) }, uniquingKeysWith: { a, _ in a })
        let shortfall = service.shortfallG(of: list)
        List {
            Section {
                LabeledContent("Status", value: stateTitle(list.stateRaw))
                LabeledContent("Ziel inkl. Reserve", value: Fmt.grams(list.targetCarbsG))
                LabeledContent("Geplant", value: Fmt.grams(items.reduce(0) { $0 + $1.plannedCarbsG }))
                if shortfall > 0 {
                    Label("Es fehlen ≈ \(Fmt.grams(shortfall)) Carbs im Bestand.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            Section {
                if items.isEmpty { Text("Kein nutzbarer Bestand für diese Liste.").foregroundStyle(.secondary) }
                ForEach(items) { item in
                    let s = service.state(of: item, ledger: ledger)
                    let expiry = item.batchID.flatMap { expiries[$0] ?? nil }.flatMap(CalendarDay.init(isoString:))
                    HStack(spacing: 12) {
                        Button { toggle(item, !s.isPacked) } label: {
                            Image(systemName: s.isPacked ? "checkmark.circle.fill" : "circle").font(.title2)
                                .foregroundStyle(s.isPacked ? Color.green : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .disabled(finished)
                        .accessibilityLabel(s.isPacked ? "Gepackt, Haken entfernen" : "Als gepackt abhaken")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.productID.flatMap { names[$0] } ?? "Produkt")
                            Text("\(item.plannedQuantity.formatted()) · \(Fmt.grams(item.plannedCarbsG))" + (expiry.map { " · MHD \(Fmt.date($0))" } ?? ""))
                                .font(.footnote).foregroundStyle(.secondary)
                            if s.returnedQuantity > 0 {
                                Text("\(s.returnedQuantity) zurückgelegt · verbraucht \(s.netConsumed)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .accessibilityElement(children: .contain)
                    .swipeActions {
                        if !finished && s.returnable > 0 { Button("Zurücklegen", systemImage: "arrow.uturn.backward") { puttingBack = item }.tint(.blue) }
                    }
                }
            } header: { Text("Einpacken") } footer: {
                Text("Der Haken bucht den Posten aus dem Bestand ab. Entfernst du ihn, wird genau diese Buchung zurückgenommen. Nach der Fahrt: nach links wischen, um Reste zurückzulegen.")
            }
        }
        .navigationTitle(list.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if list.stateRaw == "draft" { Button("Neu berechnen", systemImage: "arrow.clockwise", action: recalc) }
                    if !finished { Button("Fertig", systemImage: "checkmark.seal") { confirmFinish = true } }
                } label: { Image(systemName: "ellipsis.circle") }
                .disabled(finished)
            }
        }
        .sheet(item: $puttingBack) { PutBackSheet(item: $0, name: $0.productID.flatMap { names[$0] } ?? "Produkt") }
        .confirmationDialog("Packliste abschließen?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Fertig") { run { try service.finish(list) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Eine fertige Packliste lässt sich nicht mehr ändern.") }
        .alert("Aktion nicht möglich", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func toggle(_ item: PackListItem, _ on: Bool) { run { try service.setPacked(on, item: item) } }

    private func recalc() {
        let demand = list.targetCarbsG / (1 + Double(list.reservePercent) / 100)
        run { try service.recalculate(list, demandG: demand) }
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch let e as PackService.Failure { errorText = e.message } catch { errorText = "Das hat nicht geklappt." }
    }
}

struct PutBackSheet: View {
    let item: PackListItem
    let name: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = 1
    @State private var errorText: String?

    var body: some View {
        let s = PackService(context: context).state(of: item)
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $quantity, in: 1...max(1, s.returnable)) {
                        LabeledContent("Zurücklegen", value: "\(quantity)")
                    }
                } header: { Text(name) } footer: {
                    Text("Gepackt: \(s.packedQuantity). Es kommen bis zu \(s.returnable) in den Bestand zurück; der Verbrauch wird netto gerechnet.")
                }
                if let errorText { Section { Text(errorText).foregroundStyle(.red) } }
            }
            .navigationTitle("Rest zurücklegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zurücklegen") {
                        do { try PackService(context: context).putBack(quantity, item: item); dismiss() }
                        catch let e as PackService.Failure { errorText = e.message } catch { errorText = "Das hat nicht geklappt." }
                    }.disabled(s.returnable == 0)
                }
            }
            .onAppear { quantity = max(1, min(quantity, s.returnable)) }
        }
        .presentationDetents([.medium])
    }
}
