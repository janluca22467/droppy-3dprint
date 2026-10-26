import Foundation

enum PrinterKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case octoprint, bambu, anycubic, moonraker, anycubicCloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .octoprint: return "OctoPrint"
        case .bambu: return "Bambu Lab"
        case .anycubic: return "Anycubic"
        case .moonraker: return "Klipper"
        case .anycubicCloud: return "Anycubic Cloud"
        }
    }

    var symbol: String {
        switch self {
        case .octoprint: return "server.rack"
        case .bambu: return "cube.fill"
        case .anycubic: return "printer.fill"
        case .moonraker: return "bolt.horizontal.fill"
        case .anycubicCloud: return "cloud.fill"
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
        if kind != .anycubicCloud, host.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        switch kind {
        case .octoprint: return !apiKey.isEmpty
        case .bambu: return !serial.isEmpty && !accessCode.isEmpty
        case .anycubic, .moonraker: return true
        case .anycubicCloud: return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

enum PrintState: String, Sendable, Equatable {
    case offline, connecting, idle, preparing, printing, paused, finished, failed, stopped

    var isActive: Bool { self == .printing || self == .preparing || self == .paused }
}

struct FilamentSlot: Equatable, Sendable, Identifiable {
    var id: String
    var unit: String?
    var material: String?
    var colorHex: String?
    var remaining: Double?
    var isActive = false
    var isEmpty = false
}

enum PreviewImage: Equatable, Sendable {
    case url(URL, headers: [String: String] = [:])
    case data(Data)
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
    var chamber: Double?
    var preview: PreviewImage?
    var slots: [FilamentSlot] = []
    var filamentNeeded: Double?
    var jobID: String?
    var message: String?
    var updated = Date()

    var finishDate: Date? { remaining.map { updated.addingTimeInterval($0) } }

    static let offline = PrintStatus(state: .offline)
}

enum PrintAction: String, Sendable, CaseIterable, Hashable {
    case pause, resume, stop
}

@MainActor
protocol CameraFeed: AnyObject {
    var onFrame: ((Data) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    func start()
    func stop()
}

@MainActor
protocol PrinterConnection: AnyObject {
    var onStatus: ((PrintStatus) -> Void)? { get set }
    var supportedActions: Set<PrintAction> { get }
    func start()
    func stop()
    func makeCamera() -> CameraFeed?
    func perform(_ action: PrintAction) async -> Bool
}

extension PrinterConnection {
    var supportedActions: Set<PrintAction> { [] }
    func makeCamera() -> CameraFeed? { nil }
    func perform(_ action: PrintAction) async -> Bool { false }
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
