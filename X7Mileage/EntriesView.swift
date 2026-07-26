import SwiftUI

struct EntriesView: View {
    @EnvironmentObject var store: MileageStore
    @State private var editing: MileageEntry?
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            List {
                if store.entries.isEmpty {
                    Text("No readings yet. Tap + to add your first mileage reading.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.sortedEntries) { entry in
                        Button {
                            editing = entry
                        } label: {
                            row(for: entry)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.delete(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { store.delete(at: $0) }
                }
            }
            .navigationTitle("Readings")
            .toolbar {
                if !store.entries.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNew = true
                    } label: {
                        Label("Add reading", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNew) {
                EntryEditor(entry: nil)
            }
            .sheet(item: $editing) { entry in
                EntryEditor(entry: entry)
            }
        }
    }

    private func row(for entry: MileageEntry) -> some View {
        let snap = store.snapshot(for: entry)
        let thisPeriod = store.milesThisPeriod(for: entry)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.date.formatted(.dateTime.month(.abbreviated).year()))
                    .font(.headline)
                Spacer()
                Text("\(Int(entry.odometer.rounded())) mi")
                    .font(.headline.monospacedDigit())
            }
            HStack(spacing: 10) {
                Label("\(Int(thisPeriod.rounded())) this month", systemImage: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(signed(snap.excessMiles) + " mi")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snap.isOver ? .red : .green)
                Text(percent(snap.percentVsExpected))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snap.isOver ? .red : .green)
            }
            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func signed(_ value: Double) -> String {
        let r = value.rounded()
        return (r > 0 ? "+" : "") + "\(Int(r))"
    }

    private func percent(_ value: Double) -> String {
        let r = (value * 10).rounded() / 10
        return (r > 0 ? "+" : "") + r.formatted(.number.precision(.fractionLength(1))) + "%"
    }
}

// MARK: - Add / edit sheet

struct EntryEditor: View {
    @EnvironmentObject var store: MileageStore
    @Environment(\.dismiss) private var dismiss

    let entry: MileageEntry?

    @State private var date: Date = Date()
    @State private var odometer: Double = 0
    @State private var odometerText: String = ""
    @State private var note: String = ""
    @State private var loaded = false
    @FocusState private var odometerFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Reading") {
                    DatePicker("Month", selection: $date, displayedComponents: .date)
                    HStack {
                        Text("Mileage")
                        Spacer()
                        TextField("miles", text: $odometerText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                            .focused($odometerFocused)
                            .onChange(of: odometerText) { _, newValue in
                                odometer = Double(newValue) ?? 0
                            }
                        Text("mi").foregroundStyle(.secondary)
                    }
                    TextField("Note (optional)", text: $note)
                }

                Section("At this reading") {
                    let preview = store.snapshot(for: MileageEntry(date: date, odometer: odometer))
                    LabeledContent("Miles driven", value: "\(Int(preview.milesDriven.rounded()))")
                    LabeledContent("Expected by now", value: "\(Int(preview.expectedMiles.rounded()))")
                    LabeledContent("Over / under") {
                        Text((preview.excessMiles > 0 ? "+" : "") + "\(Int(preview.excessMiles.rounded())) mi")
                            .foregroundStyle(preview.isOver ? .red : .green)
                    }
                    LabeledContent("Excess cost") {
                        Text(preview.excessCost.formatted(.currency(code: "GBP").precision(.fractionLength(0))))
                            .foregroundStyle(preview.excessCost > 0 ? .red : .green)
                    }
                }
            }
            .navigationTitle(entry == nil ? "New reading" : "Edit reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = entry ?? MileageEntry(date: date, odometer: odometer)
                        updated.date = date
                        updated.odometer = odometer
                        updated.note = note
                        store.addOrUpdate(updated)
                        dismiss()
                    }
                    .disabled(odometer <= 0)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { odometerFocused = false }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let entry {
                    date = entry.date
                    odometer = entry.odometer
                    note = entry.note
                } else {
                    date = Date()
                    odometer = store.latestEntry?.odometer ?? store.settings.startOdometer
                }
                odometerText = odometer == 0 ? "" : odometer.formatted(.number.grouping(.never))
            }
        }
    }
}
