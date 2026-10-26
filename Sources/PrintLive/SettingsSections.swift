import DroppyKit
import SwiftUI

struct SpoolmanSection: View {
    @ObservedObject var droplet: PrintLiveDroplet
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle, running, ok, failed
    }

    var body: some View {
        DropletSettingsSection {
            VStack(alignment: .leading, spacing: 2) {
                settingsSectionHeader("Spoolman")
                Text(L.s("spoolman.detail"))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        } content: {
            DropletSettingsCard {
                DropletControlRow(title: L.s("spoolman.address"), icon: "circle.circle", iconColor: .orange) {
                    HStack(spacing: DroppySpacing.sm) {
                        TextField("", text: $droplet.spoolmanAddress, prompt: Text(verbatim: "http://192.168.1.11:3001"))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 220)
                            .onChange(of: droplet.spoolmanAddress) { _, _ in testState = .idle }
                        Button(L.s("spoolman.test")) { runTest() }
                            .buttonStyle(.bordered)
                            .disabled(testState == .running || droplet.spoolmanAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if testState != .idle || droplet.spoolmanState != .off {
                    DropletControlRow(title: statusTitle, icon: statusIcon, iconColor: statusColor) {
                        if droplet.spoolmanState == .ok {
                            DropletValuePill(text: L.f("spoolman.count", droplet.spools.count))
                        }
                    }
                }
            }
        }
    }

    private func runTest() {
        testState = .running
        let address = droplet.spoolmanAddress
        Task {
            let ok = await droplet.testSpoolman(address)
            guard address == droplet.spoolmanAddress else { return }
            testState = ok ? .ok : .failed
            if ok { await droplet.refreshSpools() }
        }
    }

    private var statusTitle: String {
        switch testState {
        case .running: return L.s("spoolman.testing")
        case .ok: return L.s("spoolman.ok")
        case .failed: return L.s("spoolman.failed")
        case .idle: return droplet.spoolmanState == .ok ? L.s("spoolman.ok") : L.s("spoolman.failed")
        }
    }

    private var isGood: Bool {
        testState == .ok || (testState == .idle && droplet.spoolmanState == .ok)
    }

    private var statusIcon: String {
        if testState == .running { return "hourglass" }
        return isGood ? "checkmark.circle.fill" : "exclamationmark.circle"
    }

    private var statusColor: Color {
        if testState == .running { return .gray }
        return isGood ? .green : .orange
    }
}

struct HistorySection: View {
    @ObservedObject var droplet: PrintLiveDroplet
    @ObservedObject var history: PrintHistory

    var body: some View {
        let stats = history.stats()
        DropletSettingsSection {
            VStack(alignment: .leading, spacing: 2) {
                settingsSectionHeader(LocalizedStringKey(L.s("set.history")))
                Text(L.s("set.historyDetail"))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        } content: {
            DropletSettingsCard {
                DropletControlRow(title: L.s("hist.prints"), icon: "printer.fill", iconColor: .blue) {
                    DropletValuePill(text: "\(stats.count)")
                }
                DropletControlRow(title: L.s("hist.success"), icon: "checkmark.seal.fill", iconColor: .green) {
                    DropletValuePill(text: stats.successRate.map { "\(Int(($0 * 100).rounded())) %" } ?? "–")
                }
                DropletControlRow(title: L.s("hist.time"), icon: "clock.fill", iconColor: .orange) {
                    DropletValuePill(text: Format.duration(stats.totalDuration))
                }
                DropletControlRow(title: L.s("hist.filament"), icon: "circle.circle", iconColor: .pink) {
                    DropletValuePill(text: Format.weight(stats.totalFilament))
                }
                DropletStackedRow(title: L.s("hist.week"), icon: "chart.bar.fill", iconColor: .purple) {
                    WeekBars(days: history.perWeekday())
                }
            }

            if !history.entries.isEmpty {
                DropletSettingsCard {
                    ForEach(history.entries.prefix(10)) { entry in
                        DropletControlRow(title: entry.fileName ?? entry.printerName, icon: icon(entry.result), iconColor: color(entry.result)) {
                            Text(detail(entry))
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    DropletControlRow(title: L.s("hist.clear"), icon: "trash.fill", iconColor: .red) {
                        Button(L.s("hist.clearButton"), role: .destructive) {
                            if DropletConfirmationDialog.present(
                                title: L.s("hist.clearTitle"),
                                message: L.f("hist.clearMessage", history.entries.count),
                                confirmTitle: L.s("hist.clearButton"),
                                symbol: "trash.fill"
                            ) {
                                history.clear()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func icon(_ result: String) -> String {
        switch result {
        case "finished": return "checkmark.circle.fill"
        case "stopped": return "stop.circle.fill"
        default: return "xmark.octagon.fill"
        }
    }

    private func color(_ result: String) -> Color {
        switch result {
        case "finished": return .green
        case "stopped": return .gray
        default: return .red
        }
    }

    private func detail(_ entry: HistoryEntry) -> String {
        var parts = [entry.printerName]
        if let duration = entry.duration { parts.append(Format.duration(duration)) }
        if let grams = entry.filamentGrams, grams > 0 { parts.append(Format.weight(grams)) }
        parts.append(entry.ended.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
        return parts.joined(separator: " · ")
    }
}

struct WeekBars: View {
    let days: [(day: Date, duration: TimeInterval)]
    private let chartHeight: CGFloat = 72

    var body: some View {
        let peak = max(days.map(\.duration).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: DroppySpacing.sm) {
            ForEach(days, id: \.day) { item in
                VStack(spacing: DroppySpacing.xs) {
                    Text(item.duration > 0 ? Format.duration(item.duration) : "")
                        .font(.system(size: 9, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    UnevenRoundedRectangle(topLeadingRadius: DroppyRadius.xs, topTrailingRadius: DroppyRadius.xs, style: .continuous)
                        .fill(item.duration > 0 ? AdaptiveColors.selectionBlueAuto : Color.secondary.opacity(0.18))
                        .frame(height: max(2, chartHeight * item.duration / peak))
                        .frame(maxWidth: 36)
                    Text(item.day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .help("\(item.day.formatted(date: .abbreviated, time: .omitted)): \(Format.duration(item.duration))")
                .accessibilityElement()
                .accessibilityLabel("\(item.day.formatted(date: .abbreviated, time: .omitted)), \(Format.duration(item.duration))")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DroppySpacing.xs)
    }
}
