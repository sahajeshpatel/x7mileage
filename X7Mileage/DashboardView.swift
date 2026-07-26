import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var store: MileageStore
    @State private var showingAddEntry = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let snap = store.latestSnapshot {
                        headline(snap)
                        headlineStats(snap)
                        allowanceBar(snap)
                        projection(snap)
                        if store.sortedEntries.count > 1 {
                            chart
                        }
                    } else {
                        emptyState
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("X7 Mileage")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddEntry = true
                    } label: {
                        Label("Add reading", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddEntry) {
                EntryEditor(entry: nil)
            }
        }
    }

    // MARK: - Sections

    private func headline(_ snap: MileageSnapshot) -> some View {
        VStack(spacing: 6) {
            Text(snap.isOver ? "OVER ALLOWANCE" : "UNDER ALLOWANCE")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(snap.isOver ? Color.red : Color.green)

            Text(percentString(snap.percentVsExpected))
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundStyle(snap.isOver ? Color.red : Color.green)
                .contentTransition(.numericText())

            Text("vs. expected mileage as at \(snap.date.formatted(date: .abbreviated, time: .omitted))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func headlineStats(_ snap: MileageSnapshot) -> some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Excess miles",
                value: signedMiles(snap.excessMiles),
                caption: snap.isOver ? "above pro-rata" : "in hand",
                tint: snap.isOver ? .red : .green
            )
            StatCard(
                title: "Excess cost",
                value: snap.excessCost.formatted(.currency(code: "GBP").precision(.fractionLength(0))),
                caption: "at \(store.settings.excessPencePerMile.formatted())p/mile",
                tint: snap.excessCost > 0 ? .red : .green
            )
        }
    }

    private func allowanceBar(_ snap: MileageSnapshot) -> some View {
        Card(title: "Allowance used") {
            VStack(alignment: .leading, spacing: 10) {
                let used = snap.milesDriven
                let total = store.settings.totalAllowanceMiles
                let usedFraction = total > 0 ? min(1.5, used / total) : 0

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                        Capsule()
                            .fill(snap.isOver ? Color.red : Color.green)
                            .frame(width: geo.size.width * min(1.0, usedFraction))
                        // Marker for where you should be by now.
                        Rectangle()
                            .fill(Color.primary)
                            .frame(width: 2)
                            .offset(x: geo.size.width * min(1.0, snap.elapsedFraction))
                    }
                }
                .frame(height: 14)

                HStack {
                    Text("\(Int(used.rounded())) of \(Int(total.rounded())) miles")
                    Spacer()
                    Text("\(Int(max(0, snap.allowanceRemaining).rounded())) left")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)

                Text("The vertical line marks where you should be at \(Int((snap.elapsedFraction * 100).rounded()))% through the contract.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func projection(_ snap: MileageSnapshot) -> some View {
        Card(title: "Projected at contract end") {
            VStack(spacing: 0) {
                Row(label: "Projected total miles",
                    value: "\(Int(snap.projectedTotalMiles.rounded()))")
                Divider()
                Row(label: "Projected over / under",
                    value: signedMiles(snap.projectedExcessMiles),
                    tint: snap.projectedExcessMiles > 0 ? .red : .green)
                Divider()
                Row(label: "Projected excess charge",
                    value: snap.projectedExcessCost.formatted(.currency(code: "GBP").precision(.fractionLength(0))),
                    tint: snap.projectedExcessCost > 0 ? .red : .green)
                Divider()
                Row(label: "Budget from here",
                    value: "\(Int(max(0, snap.sustainableMilesPerMonth).rounded())) mi/mo")
            }
        }
    }

    private var chart: some View {
        Card(title: "Actual vs expected") {
            Chart {
                ForEach(store.sortedEntries) { entry in
                    LineMark(
                        x: .value("Date", entry.date),
                        y: .value("Miles", max(0, entry.odometer - store.settings.startOdometer))
                    )
                    .foregroundStyle(by: .value("Series", "Actual"))
                    .symbol(by: .value("Series", "Actual"))
                }
                ForEach(store.sortedEntries) { entry in
                    LineMark(
                        x: .value("Date", entry.date),
                        y: .value("Miles", store.expectedMiles(at: entry.date))
                    )
                    .foregroundStyle(by: .value("Series", "Expected"))
                }
            }
            .chartForegroundStyleScale([
                "Actual": Color.blue,
                "Expected": Color.gray
            ])
            .frame(height: 220)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "speedometer")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No readings yet")
                .font(.headline)
            Text("Check your contract details in Settings, then add your first monthly mileage reading.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add a reading") { showingAddEntry = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 60)
    }

    // MARK: - Formatting helpers

    private func percentString(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let sign = rounded > 0 ? "+" : ""
        return "\(sign)\(rounded.formatted(.number.precision(.fractionLength(1))))%"
    }

    private func signedMiles(_ value: Double) -> String {
        let rounded = value.rounded()
        let sign = rounded > 0 ? "+" : ""
        return "\(sign)\(Int(rounded))"
    }
}

// MARK: - Small reusable pieces

struct StatCard: View {
    let title: String
    let value: String
    let caption: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }
}

struct Row: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.vertical, 10)
    }
}
