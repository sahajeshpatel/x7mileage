import Foundation
import SwiftData

// MARK: - Contract settings

struct ContractSettings: Codable, Equatable {
    var startDate: Date
    var termMonths: Int
    var annualAllowanceMiles: Double
    var startOdometer: Double
    var excessPencePerMile: Double

    static let standard = ContractSettings(
        startDate: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 11)) ?? Date(),
        termMonths: 48,
        annualAllowanceMiles: 23_000,
        startOdometer: 26,
        excessPencePerMile: 15.75
    )

    /// Total miles permitted across the whole contract.
    var totalAllowanceMiles: Double {
        annualAllowanceMiles * Double(termMonths) / 12.0
    }

    var endDate: Date {
        Calendar.current.date(byAdding: .month, value: termMonths, to: startDate) ?? startDate
    }

    /// Length of the contract in days (never zero, so it is safe to divide by).
    var totalContractDays: Double {
        max(1, endDate.timeIntervalSince(startDate) / 86_400)
    }

    var excessRatePerMile: Double {
        excessPencePerMile / 100.0
    }
}

// MARK: - A single monthly odometer reading

struct MileageEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var odometer: Double
    var note: String = ""
}

// MARK: - Everything the dashboard needs, derived for one point in time

struct MileageSnapshot {
    var date: Date
    var odometer: Double

    /// Miles covered since the contract started.
    var milesDriven: Double
    /// Miles you were "allowed" to have driven by this date, pro-rata.
    var expectedMiles: Double
    /// Positive = over, negative = under.
    var excessMiles: Double
    /// Cost of the excess so far. Zero when under allowance.
    var excessCost: Double
    /// Positive = % over expected, negative = % under expected.
    var percentVsExpected: Double

    /// 0.0 at contract start, 1.0 at contract end.
    var elapsedFraction: Double
    var daysRemaining: Double

    /// Where you land at the end of the contract at the current rate.
    var projectedTotalMiles: Double
    var projectedExcessMiles: Double
    var projectedExcessCost: Double

    /// Miles left in the full contract allowance.
    var allowanceRemaining: Double
    /// Miles per month you can do from now on and still finish on allowance.
    var sustainableMilesPerMonth: Double

    var isOver: Bool { excessMiles > 0 }
}

// MARK: - SwiftData records (synced with CloudKit)
//
// CloudKit requires every attribute to have a default value and doesn't support
// unique constraints, so uniqueness is handled by MileageStore instead.

@Model
final class StoredEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var odometer: Double = 0
    var note: String = ""

    init(_ entry: MileageEntry) {
        id = entry.id
        date = entry.date
        odometer = entry.odometer
        note = entry.note
    }

    var entry: MileageEntry {
        MileageEntry(id: id, date: date, odometer: odometer, note: note)
    }

    func update(from entry: MileageEntry) {
        date = entry.date
        odometer = entry.odometer
        note = entry.note
    }
}

@Model
final class StoredSettings {
    var startDate: Date = ContractSettings.standard.startDate
    var termMonths: Int = ContractSettings.standard.termMonths
    var annualAllowanceMiles: Double = ContractSettings.standard.annualAllowanceMiles
    var startOdometer: Double = ContractSettings.standard.startOdometer
    var excessPencePerMile: Double = ContractSettings.standard.excessPencePerMile
    /// Used to pick a winner if more than one device created a settings record.
    var modifiedAt: Date = Date()

    init(_ settings: ContractSettings, modifiedAt: Date = Date()) {
        update(from: settings)
        self.modifiedAt = modifiedAt
    }

    var settings: ContractSettings {
        ContractSettings(startDate: startDate,
                         termMonths: termMonths,
                         annualAllowanceMiles: annualAllowanceMiles,
                         startOdometer: startOdometer,
                         excessPencePerMile: excessPencePerMile)
    }

    func update(from settings: ContractSettings) {
        startDate = settings.startDate
        termMonths = settings.termMonths
        annualAllowanceMiles = settings.annualAllowanceMiles
        startOdometer = settings.startOdometer
        excessPencePerMile = settings.excessPencePerMile
        modifiedAt = Date()
    }
}
