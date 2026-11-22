import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: MileageStore
    @State private var showingResetAlert = false
    @FocusState private var numberFieldFocused: Bool

    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingRestoreConfirm = false
    @State private var exportDocument = JSONDocument(data: Data())
    @State private var pendingRestoreURL: URL?
    @State private var resultTitle = ""
    @State private var resultMessage = ""
    @State private var showingResult = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Contract") {
                    DatePicker("Start date",
                               selection: $store.settings.startDate,
                               displayedComponents: .date)

                    Stepper(value: $store.settings.termMonths, in: 6...72, step: 1) {
                        LabeledContent("Term", value: "\(store.settings.termMonths) months")
                    }

                    LabeledContent("Ends") {
                        Text(store.settings.endDate.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Mileage") {
                    numberField("Annual allowance",
                                value: $store.settings.annualAllowanceMiles,
                                suffix: "mi")
                    numberField("Mileage at start",
                                value: $store.settings.startOdometer,
                                suffix: "mi")
                    LabeledContent("Total allowance") {
                        Text("\(Int(store.settings.totalAllowanceMiles.rounded())) mi")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Excess charge") {
                    numberField("Rate",
                                value: $store.settings.excessPencePerMile,
                                suffix: "p / mile",
                                format: .number.precision(.fractionLength(0...2)))
                }

                Section {
                    Button {
                        exportBackup()
                    } label: {
                        Label("Export backup", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Restore from backup", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Export writes a JSON file you can save anywhere, including iCloud Drive. Restoring replaces everything currently in the app.")
                }

                Section {
                    Button("Reset all data", role: .destructive) {
                        showingResetAlert = true
                    }
                } footer: {
                    Text("Your data is stored in your private iCloud account and syncs across your devices.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        numberFieldFocused = false
                    }
                }
                #endif
            }
            .alert("Reset all data?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    store.entries = []
                    store.settings = .standard
                }
            } message: {
                Text("This deletes every reading and restores the default contract settings.")
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: store.suggestedBackupFilename
            ) { result in
                switch result {
                case .success:
                    present("Backup saved", "Your contract settings and readings were exported.")
                case .failure(let error):
                    present("Export failed", error.localizedDescription)
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    pendingRestoreURL = url
                    showingRestoreConfirm = true
                case .failure(let error):
                    present("Import failed", error.localizedDescription)
                }
            }
            .alert("Replace all data?", isPresented: $showingRestoreConfirm) {
                Button("Cancel", role: .cancel) { pendingRestoreURL = nil }
                Button("Replace", role: .destructive) { performRestore() }
            } message: {
                Text("This replaces your contract settings and every reading with the contents of the backup.")
            }
            .alert(resultTitle, isPresented: $showingResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(resultMessage)
            }
        }
    }

    // MARK: - Backup actions

    private func exportBackup() {
        do {
            exportDocument = JSONDocument(data: try store.exportData())
            showingExporter = true
        } catch {
            present("Export failed", error.localizedDescription)
        }
    }

    private func performRestore() {
        guard let url = pendingRestoreURL else { return }
        pendingRestoreURL = nil

        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let count = try store.replaceAll(withBackupData: data)
            present("Restore complete", "Loaded \(count) reading\(count == 1 ? "" : "s").")
        } catch {
            present("Import failed", "That file isn't a X7 Mileage backup, or it's damaged.")
        }
    }

    private func present(_ title: String, _ message: String) {
        resultTitle = title
        resultMessage = message
        showingResult = true
    }

    private func numberField(_ label: String,
                             value: Binding<Double>,
                             suffix: String,
                             format: FloatingPointFormatStyle<Double> = .number) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: format)
                .labelsHidden()
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
                .focused($numberFieldFocused)
            Text(suffix)
                .foregroundStyle(.secondary)
        }
    }
}

/// Minimal wrapper so `.fileExporter` can write raw JSON data.
struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
