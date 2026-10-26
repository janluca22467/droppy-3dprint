import AppKit
import Combine
import DroppyKit
import SwiftUI

@objc(PrintLivePrincipal)
public final class PrintLivePrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { PrintLiveDroplet() }
}

@MainActor
public final class PrintLiveDroplet: NSObject, ObservableObject, Droplet {
    public nonisolated static let id: DropletID = "print-live"

    static let widgetID: ShelfWidgetID = "printers"
    private static let hudID = "print-live-hud"

    private var host: DropletHost?
    private var connections: [UUID: PrinterConnection] = [:]
    private let activitySubject = CurrentValueSubject<LiveActivityState?, Never>(nil)
    private let lockScreenSubject = CurrentValueSubject<LockScreenStatusEntry?, Never>(nil)
    private var tickTask: Task<Void, Never>?
    private var recentlyDone: [UUID: Date] = [:]

    @Published private(set) var printers: [PrinterConfig] = []
    @Published private(set) var statuses: [UUID: PrintStatus] = [:]
    @Published private(set) var now = Date()

    public func activate(host: DropletHost) throws {
        self.host = host
        if host.environment.isHarness, ProcessInfo.processInfo.environment["PRINT_LIVE_DEMO"] != nil {
            loadDemo()
        } else {
            printers = loadPrinters()
            for printer in printers where printer.isEnabled { connect(printer) }
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.tick()
            }
        }
        publishSurfaces()
    }

    public func deactivate() {
        tickTask?.cancel(); tickTask = nil
        for connection in connections.values { connection.stop() }
        connections = [:]
        host?.hud.dismiss(id: Self.hudID)
        activitySubject.send(nil)
        lockScreenSubject.send(nil)
        host = nil
    }

    private func tick() {
        now = Date()
        publishSurfaces()
    }

    private func loadPrinters() -> [PrinterConfig] {
        guard let data = host?.preferences.value(forKey: "printers", as: Data.self),
              var list = try? JSONDecoder().decode([PrinterConfig].self, from: data) else { return [] }
        for i in list.indices {
            list[i].apiKey = SecretStore.get("\(list[i].id)-apiKey")
            list[i].accessCode = SecretStore.get("\(list[i].id)-accessCode")
        }
        return list
    }

    private func savePrinters() {
        var stripped = printers
        for i in stripped.indices {
            SecretStore.set(stripped[i].apiKey, for: "\(stripped[i].id)-apiKey")
            SecretStore.set(stripped[i].accessCode, for: "\(stripped[i].id)-accessCode")
            stripped[i].apiKey = ""
            stripped[i].accessCode = ""
        }
        if let data = try? JSONEncoder().encode(stripped) {
            host?.preferences.setValue(data, forKey: "printers")
        }
    }

    func save(_ printer: PrinterConfig) {
        if let i = printers.firstIndex(where: { $0.id == printer.id }) {
            printers[i] = printer
        } else {
            printers.append(printer)
        }
        savePrinters()
        disconnect(printer.id)
        if printer.isEnabled { connect(printer) }
        publishSurfaces()
    }

    func remove(_ id: UUID) {
        disconnect(id)
        printers.removeAll { $0.id == id }
        statuses[id] = nil
        SecretStore.remove("\(id)-apiKey")
        SecretStore.remove("\(id)-accessCode")
        savePrinters()
        publishSurfaces()
    }

    func reconnect(_ id: UUID) {
        guard let printer = printers.first(where: { $0.id == id }) else { return }
        disconnect(id)
        if printer.isEnabled { connect(printer) }
    }

    private func connect(_ printer: PrinterConfig) {
        guard printer.isComplete else {
            statuses[printer.id] = PrintStatus(state: .offline, message: L.s("err.incomplete"))
            return
        }
        let connection: PrinterConnection
        switch printer.kind {
        case .octoprint: connection = OctoPrintConnection(config: printer)
        case .bambu: connection = BambuConnection(config: printer)
        case .anycubic: connection = AnycubicConnection(config: printer)
        }
        let id = printer.id
        connection.onStatus = { [weak self] status in self?.update(id, status) }
        connections[id] = connection
        connection.start()
    }

    private func disconnect(_ id: UUID) {
        connections[id]?.stop()
        connections[id] = nil
    }

    private func update(_ id: UUID, _ status: PrintStatus) {
        let old = statuses[id]
        statuses[id] = status
        if let old, old.state != status.state { transition(id, from: old.state, to: status.state, status: status) }
        publishSurfaces()
    }

    private func transition(_ id: UUID, from old: PrintState, to new: PrintState, status: PrintStatus) {
        guard old.isActive else { return }
        switch new {
        case .finished, .failed, .stopped, .paused:
            if new == .finished { recentlyDone[id] = Date() }
            presentHUD(for: id, state: new, status: status)
        default:
            break
        }
    }

    func name(of id: UUID) -> String { printers.first { $0.id == id }?.name ?? "" }

    func kind(of id: UUID) -> PrinterKind { printers.first { $0.id == id }?.kind ?? .octoprint }

    func status(of id: UUID) -> PrintStatus { statuses[id] ?? PrintStatus(state: .connecting) }

    var featured: (id: UUID, status: PrintStatus)? {
        let active = printers.compactMap { p -> (UUID, PrintStatus)? in
            guard let s = statuses[p.id], s.state.isActive else { return nil }
            return (p.id, s)
        }
        if let first = active.min(by: { ($0.1.remaining ?? .infinity) < ($1.1.remaining ?? .infinity) }) { return first }
        let done = recentlyDone.filter { now.timeIntervalSince($0.value) < 600 }
        if let (id, _) = done.max(by: { $0.value < $1.value }), let s = statuses[id], s.state == .finished { return (id, s) }
        return nil
    }

    var activeCount: Int { statuses.values.filter { $0.state.isActive }.count }

    func remaining(_ status: PrintStatus) -> TimeInterval? {
        guard let finish = status.finishDate else { return nil }
        return max(0, finish.timeIntervalSince(status.state == .paused ? status.updated : now))
    }

    private func publishSurfaces() {
        guard let featured else {
            activitySubject.send(nil)
            lockScreenSubject.send(nil)
            return
        }
        let s = featured.status
        let name = name(of: featured.id)
        let percent = Int(((s.progress ?? 0) * 100).rounded())
        let label = "\(name), \(Format.state(s.state)), \(percent) %"
        activitySubject.send(LiveActivityState(
            priority: s.state == .printing ? 60 : 40,
            accessibilityTitle: label,
            isInteractive: false,
            joinsPersistentActivitySet: true,
            compactPresentation: CompactLiveActivityPresentationMetadata(
                id: "print-\(featured.id.uuidString)",
                accessibilityLabel: name,
                accessibilityValue: label
            ),
            expandedWidgetID: Self.widgetID.rawValue
        ))
        let timeText = remaining(s).map(Format.duration) ?? Format.state(s.state)
        lockScreenSubject.send(LockScreenStatusEntry(
            id: "print",
            systemImage: s.state == .finished ? "checkmark.circle.fill" : (s.state == .paused ? "pause.circle.fill" : "printer.fill"),
            text: "\(name) · \(percent) %",
            detail: s.state == .finished ? L.s("state.finished") : timeText,
            roundedCenterText: "\(percent)",
            roundedBottomText: s.state == .finished ? L.s("state.finished") : timeText,
            progress: s.progress ?? 0
        ))
    }

    private func presentHUD(for id: UUID, state: PrintState, status: PrintStatus) {
        guard let host else { return }
        let name = name(of: id)
        let file = status.fileName
        let elapsed = status.elapsed
        let request = DropletHUDRequest(
            id: Self.hudID,
            duration: state == .paused ? 6 : 12,
            priority: state == .failed ? .high : .normal,
            accessibilityLabel: "\(name): \(Format.state(state))",
            isExpanded: true,
            expandedContentHeight: 96
        ) {
            PrintHUDStrip(state: state)
        } expanded: {
            PrintHUDCard(state: state, printer: name, file: file, elapsed: elapsed)
        }
        _ = host.hud.present(request)
    }

    private func loadDemo() {
        let a = PrinterConfig(name: "Kobra S1", kind: .anycubic, host: "192.168.1.40")
        let b = PrinterConfig(name: "P1S", kind: .bambu, host: "192.168.1.41", serial: "01P00A000000000", accessCode: "12345678")
        let c = PrinterConfig(name: "Ender 3", kind: .octoprint, host: "octopi.local", apiKey: "demo")
        printers = [a, b, c]
        statuses[a.id] = PrintStatus(state: .printing, progress: 0.62, remaining: 4920, elapsed: 7800, layer: 186, totalLayers: 300,
                                     fileName: "Benchy", nozzle: 220, nozzleTarget: 220, bed: 60, bedTarget: 60)
        statuses[b.id] = PrintStatus(state: .printing, progress: 0.18, remaining: 9300, elapsed: 2000, layer: 41, totalLayers: 230,
                                     fileName: "Planter", nozzle: 218, nozzleTarget: 220, bed: 55, bedTarget: 55)
        statuses[c.id] = PrintStatus(state: .idle, nozzle: 24, nozzleTarget: 0, bed: 23, bedTarget: 0)
        if ProcessInfo.processInfo.environment["PRINT_LIVE_DEMO"] == "done" {
            presentHUD(for: a.id, state: .finished, status: PrintStatus(state: .finished, progress: 1, elapsed: 12720, fileName: "Benchy"))
        }
    }
}

extension PrintLiveDroplet: HUDPresenting {}

extension PrintLiveDroplet: LockScreenStatusProviding {
    public var lockScreenStatus: AnyPublisher<LockScreenStatusEntry?, Never> { lockScreenSubject.eraseToAnyPublisher() }
}

extension PrintLiveDroplet: LiveActivityProviding {
    public var liveActivityState: AnyPublisher<LiveActivityState?, Never> { activitySubject.eraseToAnyPublisher() }

    public func liveActivitySeatDidChange(_ seat: DropletLiveActivitySeat) {}

    public func makeCompactLeading() -> AnyView { AnyView(PrintCompactLeading(droplet: self)) }

    public func makeCompactTrailing() -> AnyView { AnyView(PrintCompactTrailing(droplet: self)) }

    public func makeExpanded(context: LiveActivityContext) -> AnyView { AnyView(EmptyView()) }
}

extension PrintLiveDroplet: ShelfWidgetProviding {
    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        let rows = max(1, min(printers.count, 3))
        return [
            ShelfWidgetDescriptor(
                id: Self.widgetID,
                title: "Print Live",
                systemImage: "printer.fill",
                layoutTraits: ShelfWidgetLayoutTraits(
                    preferredSoloWidth: 440,
                    preferredPairedWidth: 230,
                    contentHeight: .fixed(CGFloat(rows) * 78 + 12)
                )
            )
        ]
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        AnyView(PrintShelfWidget(droplet: self, context: context))
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
}

extension PrintLiveDroplet: SettingsPaneProviding {
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView { AnyView(PrintLiveSettings(droplet: self)) }

    public var settingsSearchEntries: [SettingsSearchEntry] {
        [SettingsSearchEntry(title: L.s("set.printers"), keywords: ["octoprint", "bambu", "anycubic", "printer", "3d"])]
    }
}
