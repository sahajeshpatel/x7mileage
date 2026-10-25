import Foundation
import Combine

final class MileageStore: ObservableObject {

    @Published var settings: ContractSettings { didSet { save() } }
    @Published var entries: [MileageEntry] { didSet { save() } }

    // MARK: - Persistence

    private struct Payload: Codable {
        var settings: ContractSettings
        var entries: [MileageEntry]
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("x7-mileage.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            self.settings = payload.settings
            self.entries = payload.entries
        } else {
            self.settings = .standard
            self.entries = []
        }
    }

    private func save() {
        let payload = Payload(settings: settings, entries: entries)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    // MARK: - Entry management

    var sortedEntries: [MileageEntry] {
        entries.sorted { $0.date < $1.date }
    }

    var latestEntry: MileageEntry? {
        sortedEntries.last
    }

    func addOrUpdate(_ entry: MileageEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    func delete(at offsets: IndexSet) {
        let doomed = offsets.map { sortedEntries[$0].id }
        entries.removeAll { doomed.contains($0.id) }
    }

    func delete(_ entry: MileageEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    /// Miles covered in the month leading up to this entry.
    func milesThisPeriod(for entry: MileageEntry) -> Double {
        let previous = sortedEntries.last { $0.date < entry.date }
        let base = previous?.odometer ?? settings.startOdometer
        return max(0, entry.odometer - base)
    }

    // MARK: - Core maths

    /// How far through the contract we are, 0...1 (uncapped version used for projections).
    func rawElapsedFraction(at date: Date) -> Double {
        let days = date.timeIntervalSince(settings.startDate) / 86_400
        return max(0, days) / settings.totalContractDays
    }

    /// Allowance accrued by a given date, pro-rata across the contract.
    func expectedMiles(at date: Date) -> Double {
        let fraction = min(1.0, rawElapsedFraction(at: date))
        return settings.totalAllowanceMiles * fraction
    }

    func snapshot(for entry: MileageEntry) -> MileageSnapshot {
        let milesDriven = max(0, entry.odometer - settings.startOdometer)
        let expected = expectedMiles(at: entry.date)
        let excessMiles = milesDriven - expected
        let excessCost = max(0, excessMiles) * settings.excessRatePerMile

        let percent: Double
        if expected > 0 {
            percent = (milesDriven - expected) / expected * 100.0
        } else {
            percent = 0
        }

        let rawFraction = rawElapsedFraction(at: entry.date)
        let safeFraction = max(0.001, rawFraction)
        let projectedTotal = milesDriven / safeFraction
        let projectedExcessMiles = projectedTotal - settings.totalAllowanceMiles
        let projectedExcessCost = max(0, projectedExcessMiles) * settings.excessRatePerMile

        let daysRemaining = max(0, settings.endDate.timeIntervalSince(entry.date) / 86_400)
        let monthsRemaining = daysRemaining / 30.44
        let allowanceRemaining = settings.totalAllowanceMiles - milesDriven
        let sustainable = monthsRemaining > 0.01
            ? allowanceRemaining / monthsRemaining
            : allowanceRemaining

        return MileageSnapshot(
            date: entry.date,
            odometer: entry.odometer,
            milesDriven: milesDriven,
            expectedMiles: expected,
            excessMiles: excessMiles,
            excessCost: excessCost,
            percentVsExpected: percent,
            elapsedFraction: min(1.0, rawFraction),
            daysRemaining: daysRemaining,
            projectedTotalMiles: projectedTotal,
            projectedExcessMiles: projectedExcessMiles,
            projectedExcessCost: projectedExcessCost,
            allowanceRemaining: allowanceRemaining,
            sustainableMilesPerMonth: sustainable
        )
    }

    var latestSnapshot: MileageSnapshot? {
        guard let latest = latestEntry else { return nil }
        return snapshot(for: latest)
    }

    // MARK: - Backup

    /// A portable snapshot of everything the app holds. Kept separate from the
    /// on-disk Payload so the backup format stays stable even if the storage
    /// layer changes later.
    struct Backup: Codable {
        var formatVersion: Int = 1
        var exportedAt: Date = Date()
        var settings: ContractSettings
        var entries: [MileageEntry]
    }

    private static func backupEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func backupDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func exportData() throws -> Data {
        let backup = Backup(settings: settings, entries: sortedEntries)
        return try Self.backupEncoder().encode(backup)
    }

    /// Replaces the contract settings and every reading with the backup's contents.
    @discardableResult
    func replaceAll(withBackupData data: Data) throws -> Int {
        let backup = try Self.backupDecoder().decode(Backup.self, from: data)
        settings = backup.settings
        entries = backup.entries
        return backup.entries.count
    }

    var suggestedBackupFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "X7Mileage-\(formatter.string(from: Date()))"
    }
}
