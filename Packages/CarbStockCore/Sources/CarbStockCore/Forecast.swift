import Foundation

// Bedarf und Prognose (Spec 4.3, 7.2). Alles in g Carbs; "heute" wird immer übergeben.

public enum DemandCalculator {
    /// Priority: session override > user value for the type > built-in default (5.5).
    public static func carbsPerHour(type: SessionType, sessionOverride: Int? = nil,
                                    userRates: [SessionType: Int] = [:]) -> Int {
        sessionOverride ?? userRates[type] ?? CarbRate.builtIn(type).defaultPerHour
    }

    /// Duration in hours x g/h (TV-1: 240 min x 80 g/h = 320 g).
    public static func sessionDemandG(durationMinutes: Int, carbsPerHour: Int) -> Double {
        Double(durationMinutes) / 60 * Double(carbsPerHour)
    }

    public static func sessionDemandG(_ s: PlannedSession, userRates: [SessionType: Int] = [:]) -> Double {
        sessionDemandG(durationMinutes: s.durationMinutes,
                       carbsPerHour: carbsPerHour(type: s.type, sessionOverride: s.carbsPerHourOverride, userRates: userRates))
    }
}

/// Daily demand from `start` on; `dailyG` holds only the days with known demand (7.2.1/7.2.5).
public struct DemandSeries: Hashable, Sendable {
    public let start: CalendarDay
    public let dailyG: [Double]
    /// True if the series is cut at `maxDays` although demand is still known beyond it.
    public let reachedCap: Bool

    public init(start: CalendarDay, dailyG: [Double], reachedCap: Bool = false) {
        self.start = start
        self.dailyG = dailyG
        self.reachedCap = reachedCap
    }

    public var knownDays: Int { dailyG.count }
    /// Last day with known demand ("mindestens bis", AC-P5).
    public var knownThrough: CalendarDay? { dailyG.isEmpty ? nil : start.adding(days: dailyG.count - 1) }
    public var totalG: Double { dailyG.reduce(0, +) }
    /// Demand of the first `n` days (only known days contribute).
    public func demandG(firstDays n: Int) -> Double { dailyG.prefix(max(0, n)).reduce(0, +) }
    /// Demand for `n` days is fully known.
    public func isKnown(forDays n: Int) -> Bool { knownDays >= n || reachedCap }
    func truncated(to n: Int) -> DemandSeries {
        DemandSeries(start: start, dailyG: Array(dailyG.prefix(max(0, n))), reachedCap: reachedCap || knownDays > n)
    }

    /// Builds the series (7.2.1). Per day:
    /// 1. explicit sessions of the day win over the weekly template; `skipped` sessions count 0
    ///    (Annahme: a day that only has skipped sessions is a known rest day, the template does not apply;
    ///    `done` and `planned` both count, as 4.3 only excludes skipped);
    /// 2. else the weekly template if any of its entries is valid on that day (a weekday without entry = rest day);
    /// 3. else, Annahme (4.3 "mindestens bis [letzte geplante Session]"): days up to the last explicit session
    ///    are known rest days;
    /// 4. else the demand is unknown and the series ends.
    public static func build(from today: CalendarDay, maxDays: Int, sessions: [PlannedSession],
                             template: [WeeklyTemplateEntry] = [], userRates: [SessionType: Int] = [:]) -> DemandSeries {
        var explicit: [Int: [PlannedSession]] = [:]
        for s in sessions { explicit[s.day.ordinal, default: []].append(s) }
        let lastExplicit = sessions.map(\.day.ordinal).max()
        var out: [Double] = []
        for i in 0..<max(0, maxDays) {
            let day = today.adding(days: i)
            if let list = explicit[day.ordinal] {
                out.append(list.filter { $0.status != .skipped }.reduce(0) { $0 + DemandCalculator.sessionDemandG($1, userRates: userRates) })
                continue
            }
            let valid = template.filter { $0.validFrom <= day && ($0.validUntil.map { day <= $0 } ?? true) }
            if !valid.isEmpty {
                out.append(valid.filter { $0.weekdayIndex == day.isoWeekdayIndex }.reduce(0) {
                    $0 + DemandCalculator.sessionDemandG(durationMinutes: $1.durationMinutes,
                        carbsPerHour: DemandCalculator.carbsPerHour(type: $1.type, sessionOverride: $1.carbsPerHourOverride, userRates: userRates))
                })
            } else if let last = lastExplicit, day.ordinal <= last {
                out.append(0)
            } else {
                return DemandSeries(start: today, dailyG: out)
            }
        }
        return DemandSeries(start: today, dailyG: out, reachedCap: maxDays > 0)
    }
}

/// Remaining stock of one batch as the simulation sees it.
public struct StockLot: Hashable, Sendable {
    public var batchID: UUID
    public var productID: UUID
    public var expiry: CalendarDay?
    public var carbsG: Double
    public var unitCarbsG: Double
    public var useDespiteExpiry: Bool
    public var glucoseFructoseRatio: Double?

    public init(batchID: UUID, productID: UUID, expiry: CalendarDay?, carbsG: Double, unitCarbsG: Double,
                useDespiteExpiry: Bool = false, glucoseFructoseRatio: Double? = nil) {
        self.batchID = batchID
        self.productID = productID
        self.expiry = expiry
        self.carbsG = carbsG
        self.unitCarbsG = unitCarbsG
        self.useDespiteExpiry = useDespiteExpiry
        self.glucoseFructoseRatio = glucoseFructoseRatio
    }

    /// Lots with stock > 0 from non-archived batches (negative stock is not usable). Expired lots are
    /// kept; the simulation decides (7.2.2), so the supply gap can see them.
    public static func lots(products: [ProductInfo], batches: [BatchInfo], ledger: Ledger) -> [StockLot] {
        let byID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        return batches.sorted(by: BatchInfo.fefoPrecedes).compactMap { b in
            guard !b.isArchived, let p = byID[b.productID] else { return nil }
            let q = ledger.quantity(ofBatch: b.id)
            guard q > 0 else { return nil }
            return StockLot(batchID: b.id, productID: p.id, expiry: b.expiryDate, carbsG: Double(q) * p.carbsPerBaseUnit,
                            unitCarbsG: p.carbsPerBaseUnit, useDespiteExpiry: b.useDespiteExpiry,
                            glucoseFructoseRatio: p.glucoseFructoseRatio)
        }
    }

    func isUsable(on day: CalendarDay) -> Bool { useDespiteExpiry || !(expiry.map { $0 < day } ?? false) }

    static func fefoPrecedes(_ a: StockLot, _ b: StockLot) -> Bool {
        switch (a.expiry, b.expiry) {
        case let (x?, y?) where x != y: return x < y
        case (nil, .some): return false
        case (.some, nil): return true
        default: return a.batchID.uuidString < b.batchID.uuidString
        }
    }
}

/// Carbs of a batch that expire unconsumed within the known demand period (4.3 Verfallsrisiko, TV-6).
public struct BatchLoss: Hashable, Sendable {
    public let batchID: UUID
    public let lostCarbsG: Double
    /// Whole base units (rounded to the nearest unit; carbs / carbs per unit).
    public let lostQuantity: Int
    public let expiry: CalendarDay
}

/// First day the usable stock no longer covers the next 7 days of demand although stock has expired (4.3.2, AC-P7).
public struct SupplyGap: Hashable, Sendable {
    public let day: CalendarDay
    public let usableCarbsG: Double
    public let demandNext7DaysG: Double
}

public enum RunwayEnd: String, Sendable {
    /// Stock runs out on a day with known demand: "reicht bis".
    case stockExhausted
    /// Stock is still left when known demand ends: "mindestens bis" (AC-P5).
    case demandEnded
    /// Stock is still left at the simulation cap: "mindestens bis".
    case horizonReached
    /// No known demand (or demand 0): no runway statement (AC-P4).
    case noDemandData
}

public struct SimulationResult: Sendable {
    public let start: CalendarDay
    /// Fully covered days plus the covered fraction of the day the stock ran out on.
    public let coveredDaysExact: Double
    /// Fully covered days (rounded down).
    public let coveredDays: Int
    /// Weeks = coveredDaysExact / 7, rounded DOWN to one decimal (7.1). TV-2: 14 000 g at 900 g/week = 15.5.
    /// Nil without runway statement.
    public let weeks: Double?
    /// First day without full cover = `start + coveredDays` (AC-P3: "bis heute + 108 Tage").
    public let reachDate: CalendarDay?
    /// Last day that is fully covered.
    public let lastFullyCoveredDay: CalendarDay?
    public let end: RunwayEnd
    public let consumedG: Double
    public let losses: [BatchLoss]
    public let supplyGap: SupplyGap?
    public var totalLossG: Double { losses.reduce(0) { $0 + $1.lostCarbsG } }
}

public enum Forecast {
    static let eps = 1e-9

    /// Floors to one decimal (conservative display, 7.1).
    static func floorToTenth(_ x: Double) -> Double { (x * 10 + 1e-7).rounded(.down) / 10 }

    /// Day-by-day simulation with FEFO and expiry (7.2.3). Annahme: lots expire at the end of their
    /// best-before day; a lot is lost only if it expires inside the known demand period (plus the day after,
    /// as the last known day is still consumed from it).
    public static func simulate(lots input: [StockLot], series: DemandSeries, today: CalendarDay) -> SimulationResult {
        var lots = input.filter { $0.carbsG > eps }.sorted(by: StockLot.fefoPrecedes)
        var losses: [BatchLoss] = []
        var expiredG = 0.0
        var gap: SupplyGap?
        var consumed = 0.0
        var covered = 0.0
        var exhausted = false

        func sweep(_ day: CalendarDay) {
            lots.removeAll { lot in
                guard !lot.isUsable(on: day), let e = lot.expiry else { return false }
                expiredG += lot.carbsG
                if e >= today {
                    losses.append(BatchLoss(batchID: lot.batchID, lostCarbsG: lot.carbsG,
                                            lostQuantity: Int((lot.carbsG / lot.unitCarbsG).rounded()), expiry: e))
                }
                return true
            }
        }

        let hasDemand = series.totalG > eps
        if hasDemand {
            for (i, need) in series.dailyG.enumerated() {
                let day = today.adding(days: i)
                sweep(day)
                let usable = lots.reduce(0) { $0 + $1.carbsG }
                if gap == nil, expiredG > eps {
                    let next7 = series.dailyG[i..<min(i + 7, series.knownDays)].reduce(0, +)
                    if next7 > eps, usable + eps < next7 {
                        gap = SupplyGap(day: day, usableCarbsG: usable, demandNext7DaysG: next7)
                    }
                }
                if need <= eps { covered += 1; continue }
                if usable + eps < need {
                    covered += usable / need
                    consumed += usable
                    lots.removeAll()
                    exhausted = true
                    break
                }
                var open = need
                for k in lots.indices where open > eps {
                    let take = min(lots[k].carbsG, open)
                    lots[k].carbsG -= take
                    open -= take
                }
                lots.removeAll { $0.carbsG <= eps }
                consumed += need
                covered += 1
            }
            if !exhausted { sweep(today.adding(days: series.knownDays)) }
        }

        let end: RunwayEnd = !hasDemand ? .noDemandData : exhausted ? .stockExhausted : (series.reachedCap ? .horizonReached : .demandEnded)
        let days = Int((covered + 1e-9).rounded(.down))
        let hasRunway = end != .noDemandData
        return SimulationResult(start: today, coveredDaysExact: covered, coveredDays: days,
                                weeks: hasRunway ? floorToTenth(covered / 7) : nil,
                                reachDate: hasRunway ? today.adding(days: days) : nil,
                                lastFullyCoveredDay: hasRunway && days > 0 ? today.adding(days: days - 1) : nil,
                                end: end, consumedG: consumed, losses: losses, supplyGap: gap)
    }
}

public enum Ampel: String, Sendable { case enough, tight, shortage }

public struct ForecastWindow: Sendable {
    public let days: Int
    public let demandG: Double
    /// Usable stock for this window: stock now minus what expires unconsumed inside the window.
    public let usableStockG: Double
    /// usableStock - demand (negative = Fehlmenge).
    public let differenceG: Double
    /// Demand for all `days` is known; otherwise `ampel` is nil.
    public let isDemandComplete: Bool
    public let coverage: Double?
    public let ampel: Ampel?
    public var shortfallG: Double { max(0, -differenceG) }
}

extension Forecast {
    /// Annahme (4.3, "knapp" is not defined by the spec): coverage = usable stock / demand.
    /// shortage < 100 %, tight 100 % ..< 110 %, enough >= 110 %. Demand 0 = enough.
    public static let tightCoverage = 1.10

    public static func ampel(usableG: Double, demandG: Double) -> Ampel {
        guard demandG > eps else { return .enough }
        let c = usableG / demandG
        return c + eps < 1 ? .shortage : c + eps < tightCoverage ? .tight : .enough
    }

    public static func window(days: Int, lots: [StockLot], series: DemandSeries, today: CalendarDay) -> ForecastWindow {
        let part = series.truncated(to: days)
        let sim = simulate(lots: lots, series: part, today: today)
        let usable = lots.filter { $0.isUsable(on: today) }.reduce(0) { $0 + $1.carbsG } - sim.totalLossG
        let demand = part.totalG
        let complete = series.isKnown(forDays: days)
        return ForecastWindow(days: days, demandG: demand, usableStockG: usable, differenceG: usable - demand,
                              isDemandComplete: complete,
                              coverage: demand > eps ? usable / demand : nil,
                              ampel: complete ? ampel(usableG: usable, demandG: demand) : nil)
    }
}

public struct ForecastReport: Sendable {
    public let series: DemandSeries
    public let windows: [ForecastWindow]
    public let simulation: SimulationResult
}

extension Forecast {
    /// Full forecast: windows (default 7/28/84 days) plus the runway simulation over the whole known series.
    public static func run(today: CalendarDay, products: [ProductInfo], batches: [BatchInfo], ledger: Ledger,
                           sessions: [PlannedSession], template: [WeeklyTemplateEntry] = [],
                           userRates: [SessionType: Int] = [:], windows: [Int] = [7, 28, 84],
                           maxDays: Int = 730) -> ForecastReport {
        let series = DemandSeries.build(from: today, maxDays: maxDays, sessions: sessions, template: template, userRates: userRates)
        let lots = StockLot.lots(products: products, batches: batches, ledger: ledger)
        return ForecastReport(series: series,
                              windows: windows.map { window(days: $0, lots: lots, series: series, today: today) },
                              simulation: simulate(lots: lots, series: series, today: today))
    }
}
