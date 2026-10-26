import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var printerID: UUID
    var printerName: String
    var fileName: String?
    var result: String
    var started: Date?
    var ended: Date
    var duration: TimeInterval?
    var filamentGrams: Double?
}

struct HistoryStats: Equatable, Sendable {
    var count = 0
    var finished = 0
    var failed = 0
    var successRate: Double?
    var totalDuration: TimeInterval = 0
    var totalFilament: Double = 0
    var last7DaysDuration: TimeInterval = 0
}

@MainActor
final class PrintHistory: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    static let limit = 500
    static let duplicateWindow: TimeInterval = 120
    private let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: fileURL), let list = try? Self.decoder.decode([HistoryEntry].self, from: data) {
            entries = Array(list.sorted { $0.ended > $1.ended }.prefix(Self.limit))
        }
    }

    func record(_ entry: HistoryEntry) {
        let duplicate = entries.contains {
            $0.printerID == entry.printerID && $0.fileName == entry.fileName && $0.result == entry.result
                && abs($0.ended.timeIntervalSince(entry.ended)) < Self.duplicateWindow
        }
        guard !duplicate else { return }
        var list = entries
        list.append(entry)
        list.sort { $0.ended > $1.ended }
        if list.count > Self.limit { list = Array(list.prefix(Self.limit)) }
        entries = list
        save()
    }

    func clear() {
        entries = []
        save()
    }

    func stats(since: Date? = nil) -> HistoryStats {
        let scoped = since.map { date in entries.filter { $0.ended >= date } } ?? entries
        let weekStart = Date().addingTimeInterval(-7 * 86_400)
        var stats = HistoryStats()
        stats.count = scoped.count
        stats.finished = scoped.filter { $0.result == "finished" }.count
        stats.failed = scoped.filter { $0.result == "failed" }.count
        stats.successRate = scoped.isEmpty ? nil : Double(stats.finished) / Double(scoped.count)
        stats.totalDuration = scoped.reduce(0) { $0 + max(0, $1.duration ?? 0) }
        stats.totalFilament = scoped.reduce(0) { $0 + max(0, $1.filamentGrams ?? 0) }
        stats.last7DaysDuration = scoped.filter { $0.ended >= weekStart }.reduce(0) { $0 + max(0, $1.duration ?? 0) }
        return stats
    }

    func perWeekday(now: Date = Date(), calendar: Calendar = .current) -> [(day: Date, duration: TimeInterval)] {
        let today = calendar.startOfDay(for: now)
        let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        var totals: [Date: TimeInterval] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.ended)
            guard let first = days.first, day >= first, day <= today else { continue }
            totals[day, default: 0] += max(0, entry.duration ?? 0)
        }
        return days.map { (day: $0, duration: totals[$0] ?? 0) }
    }

    private func save() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? Self.encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
