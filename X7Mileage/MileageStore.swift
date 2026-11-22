import Foundation
import Combine
import CoreData
import SwiftData

final class MileageStore: ObservableObject {

    @Published var settings: ContractSettings { didSet { if !isReloading { persistSettings() } } }
    @Published var entries: [MileageEntry] { didSet { if !isReloading { persistEntries() } } }

    // MARK: - Persistence

    /// SwiftData container mirrored to the user's private CloudKit database, so
    /// readings and settings sync between iPhone, iPad and Mac.
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    /// Set while copying records into the published properties, so that the
    /// `didSet` observers don't write the same values straight back.
    private var isReloading = false
    private var remoteChangeTask: Task<Void, Never>?

    /// The JSON file used before CloudKit sync existed. Imported once, then renamed.
    private static var legacyFileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("x7-mileage.json")
    }

    private struct LegacyPayload: Codable {
        var settings: ContractSettings
        var entries: [MileageEntry]
    }

    init() {
        let schema = Schema([StoredEntry.self, StoredSettings.self])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Fall back to a local-only store rather than refusing to launch.
            let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            container = try! ModelContainer(for: schema, configurations: [local])
        }

        settings = .standard
        entries = []

        migrateLegacyFileIfNeeded()
        reloadFromStore()
        observeRemoteChanges()
    }

    deinit {
        remoteChangeTask?.cancel()
    }

    /// Re-reads everything from SwiftData, e.g. after CloudKit imports changes
    /// made on another device.
    private func reloadFromStore() {
        let storedEntries = (try? context.fetch(FetchDescriptor<StoredEntry>())) ?? []
        let storedSettings = (try? context.fetch(
            FetchDescriptor<StoredSettings>(sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
        )) ?? []

        // CloudKit can't enforce uniqueness, so two devices may each have created
        // a copy of the same record. Keep one and remove the rest.
        var seen = Set<UUID>()
        var uniqueEntries: [MileageEntry] = []
        for record in storedEntries {
            if seen.insert(record.id).inserted {
                uniqueEntries.append(record.entry)
            } else {
                context.delete(record)
            }
        }
        for duplicate in storedSettings.dropFirst() {
            context.delete(duplicate)
        }
        if context.hasChanges { try? context.save() }

        isReloading = true
        let newSettings = storedSettings.first?.settings ?? .standard
        if newSettings != settings { settings = newSettings }
        let sortedNew = uniqueEntries.sorted { $0.date < $1.date }
        if sortedNew != sortedEntries { entries = sortedNew }
        isReloading = false
    }

    private func observeRemoteChanges() {
        remoteChangeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                self?.reloadFromStore()
            }
        }
    }

    private func persistSettings() {
        let stored = (try? context.fetch(
            FetchDescriptor<StoredSettings>(sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
        )) ?? []
        if let record = stored.first {
            record.update(from: settings)
        } else {
            context.insert(StoredSettings(settings))
        }
        try? context.save()
    }

    /// Applies the difference between `entries` and the stored records.
    private func persistEntries() {
        let stored = (try? context.fetch(FetchDescriptor<StoredEntry>())) ?? []
        let current = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var existing = Set<UUID>()

        for record in stored {
            if let entry = current[record.id] {
                existing.insert(record.id)
                if record.entry != entry { record.update(from: entry) }
            } else {
                context.delete(record)
            }
        }
        for entry in current.values where !existing.contains(entry.id) {
            context.insert(StoredEntry(entry))
        }
        try? context.save()
    }

    /// Copies data from the old on-device JSON file into SwiftData the first time
    /// this version runs, then renames the file so it isn't imported again.
    private func migrateLegacyFileIfNeeded() {
        let url = Self.legacyFileURL
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(LegacyPayload.self, from: data) else { return }

        // Use an old timestamp so settings edited on any device take priority.
        context.insert(StoredSettings(payload.settings, modifiedAt: .distantPast))
        for entry in payload.entries {
            context.insert(StoredEntry(entry))
        }
        do {
            try context.save()
            try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("migrated"))
        } catch {
            // Leave the file in place; duplicates are removed on reload if it's imported again.
        }
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
    /// SwiftData models so the backup format stays stable even if the storage
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
