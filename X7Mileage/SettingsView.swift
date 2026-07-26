import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: MileageStore
    @State private var showingResetAlert = false

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
                    Button("Reset all data", role: .destructive) {
                        showingResetAlert = true
                    }
                } footer: {
                    Text("Everything is stored on this device only. Nothing is uploaded.")
                }
            }
            .navigationTitle("Settings")
            .alert("Reset all data?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    store.entries = []
                    store.settings = .standard
                }
            } message: {
                Text("This deletes every reading and restores the default contract settings.")
            }
        }
    }

    private func numberField(_ label: String,
                             value: Binding<Double>,
                             suffix: String,
                             format: FloatingPointFormatStyle<Double> = .number) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: format)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
            Text(suffix)
                .foregroundStyle(.secondary)
        }
    }
}
