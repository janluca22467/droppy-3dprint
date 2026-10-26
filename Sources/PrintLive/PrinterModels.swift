import Foundation

enum PrinterKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case octoprint, bambu, anycubic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .octoprint: return "OctoPrint"
        case .bambu: return "Bambu Lab"
        case .anycubic: return "Anycubic"
        }
    }

    var symbol: String {
        switch self {
        case .octoprint: return "server.rack"
        case .bambu: return "cube.fill"
        case .anycubic: return "printer.fill"
        }
    }
}

struct PrinterConfig: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var kind: PrinterKind
    var host: String
    var apiKey: String = ""
    var serial: String = ""
    var accessCode: String = ""
    var isEnabled = true

    var isComplete: Bool {
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch kind {
        case .octoprint: return !apiKey.isEmpty
        case .bambu: return !serial.isEmpty && !accessCode.isEmpty
        case .anycubic: return true
        }
    }
}

enum PrintState: String, Sendable, Equatable {
    case offline, connecting, idle, preparing, printing, paused, finished, failed, stopped

    var isActive: Bool { self == .printing || self == .preparing || self == .paused }
}

struct PrintStatus: Equatable, Sendable {
    var state: PrintState = .connecting
    var progress: Double?
    var remaining: TimeInterval?
    var elapsed: TimeInterval?
    var layer: Int?
    var totalLayers: Int?
    var fileName: String?
    var nozzle: Double?
    var nozzleTarget: Double?
    var bed: Double?
    var bedTarget: Double?
    var message: String?
    var updated = Date()

    var finishDate: Date? { remaining.map { updated.addingTimeInterval($0) } }

    static let offline = PrintStatus(state: .offline)
}

@MainActor
protocol PrinterConnection: AnyObject {
    var onStatus: ((PrintStatus) -> Void)? { get set }
    func start()
    func stop()
}

extension Optional where Wrapped == String {
    var cleanedFileName: String? {
        guard let self, !self.isEmpty else { return nil }
        var name = (self as NSString).lastPathComponent
        for ext in [".gcode.3mf", ".3mf", ".gcode", ".gco", ".bgcode"] where name.lowercased().hasSuffix(ext) {
            name = String(name.dropLast(ext.count))
        }
        return name
    }
}
