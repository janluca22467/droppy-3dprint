import AppKit
import Combine
import DroppyKit
import SwiftUI

@objc(PrintLivePrincipal)
public final class PrintLivePrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { PrintLiveDroplet() }
}

enum PrintAlert: String, CaseIterable, Identifiable, Sendable {
    case finished, paused, failed, firstLayer, timeLeft, temperature

    var id: String { rawValue }

    var defaultOn: Bool { self != .temperature }

    var prefKey: String { "alert.\(rawValue)" }

    var symbol: String {
        switch self {
        case .finished: return "checkmark.circle.fill"
        case .paused: return "pause.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .firstLayer: return "square.stack.3d.down.forward.fill"
        case .timeLeft: return "timer"
        case .temperature: return "thermometer.low"
        }
    }

    var tint: Color {
        switch self {
        case .finished, .firstLayer: return .green
        case .paused, .temperature: return .orange
        case .failed: return .red
        case .timeLeft: return .blue
        }
    }
}

struct HUDContent: Sendable {
    var symbol: String
    var tint: Color
    var stripText: String
    var title: String
    var subtitle: String
    var preview: PreviewImage?
    var progress: Double
}

private struct AlertTrack {
    var job = ""
    var lastLayer: Int?
    var lastRemaining: TimeInterval?
    var coldSince: Date?
    var firstLayerDone = false
    var timeLeftDone = false
    var temperatureDone = false
}

@MainActor
public final class PrintLiveDroplet: NSObject, ObservableObject, Droplet {
    public nonisolated static let id: DropletID = "print-live"

    static let widgetID: ShelfWidgetID = "printers"
    static let cameraWidgetID: ShelfWidgetID = "camera"
    private static let hudID = "print-live-hud"

    private var host: DropletHost?
    private var connections: [UUID: PrinterConnection] = [:]
    private let activitySubject = CurrentValueSubject<LiveActivityState?, Never>(nil)
    private let lockScreenSubject = CurrentValueSubject<LockScreenStatusEntry?, Never>(nil)
    private var tickTask: Task<Void, Never>?
    private var spoolTask: Task<Void, Never>?
    private var spoolDebounce: Task<Void, Never>?
    private var recentlyDone: [UUID: Date] = [:]
    private var tracks: [UUID: AlertTrack] = [:]
    private var cameraFeed: CameraFeed?
    private var cameraFeedPrinter: UUID?
    private var cameraVisible = false
    private var lastWidgetHeight: CGFloat = 0
    private(set) var isDemo = false

    @Published private(set) var printers: [PrinterConfig] = []
    @Published private(set) var statuses: [UUID: PrintStatus] = [:]
    @Published private(set) var now = Date()
    @Published private(set) var history: PrintHistory?
    @Published private(set) var spools: [Spool] = []
    @Published private(set) var spoolLinks: [UUID: Int] = [:]
    @Published private(set) var spoolmanState: SpoolmanState = .off
    @Published private(set) var busy: Set<UUID> = []
    @Published private(set) var cameraFrame: NSImage?
    @Published private(set) var cameraMessage: String?
    @Published private(set) var cameraSelection: UUID?
    @Published var spoolmanAddress = "" {
        didSet {
            guard oldValue != spoolmanAddress else { return }
            host?.preferences.setValue(spoolmanAddress, forKey: "spoolmanAddress")
            scheduleSpoolRefresh()
        }
    }

    enum SpoolmanState: Equatable {
        case off, ok, unreachable
    }

    public func activate(host: DropletHost) throws {
        self.host = host
        spoolmanAddress = host.preferences.value(forKey: "spoolmanAddress", default: "")
        if host.environment.isHarness, ProcessInfo.processInfo.environment["PRINT_LIVE_DEMO"] != nil {
            isDemo = true
            loadDemo()
        } else {
            history = PrintHistory(directory: host.environment.containerDirectory)
            printers = loadPrinters()
            spoolLinks = loadSpoolLinks()
            for printer in printers where printer.isEnabled { connect(printer) }
            startSpoolLoop()
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
        spoolTask?.cancel(); spoolTask = nil
        spoolDebounce?.cancel(); spoolDebounce = nil
        stopCamera()
        cameraVisible = false
        for connection in connections.values { connection.stop() }
        connections = [:]
        host?.hud.dismiss(id: Self.hudID)
        activitySubject.send(nil)
        lockScreenSubject.send(nil)
        host = nil
    }

    private func tick() {
        now = Date()
        for id in statuses.keys { checkTemperature(id) }
        if cameraVisible, cameraTarget != cameraFeedPrinter { startCamera() }
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
        tracks[id] = nil
        SecretStore.remove("\(id)-apiKey")
        SecretStore.remove("\(id)-accessCode")
        setSpool(nil, for: id)
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
        case .moonraker: connection = MoonrakerConnection(config: printer)
        case .anycubicCloud: connection = AnycubicCloudConnection(config: printer)
        }
        let id = printer.id
        connection.onStatus = { [weak self] status in self?.update(id, status) }
        connections[id] = connection
        connection.start()
        if cameraFeedPrinter == id { startCamera() }
    }

    private func disconnect(_ id: UUID) {
        if cameraFeedPrinter == id { stopCamera() }
        connections[id]?.stop()
        connections[id] = nil
    }

    private func update(_ id: UUID, _ status: PrintStatus) {
        let old = statuses[id]
        statuses[id] = status
        if let old, old.state != status.state { transition(id, from: old.state, to: status.state, status: status) }
        checkProgressAlerts(id, status)
        publishSurfaces()
    }

    private func transition(_ id: UUID, from old: PrintState, to new: PrintState, status: PrintStatus) {
        guard old.isActive else { return }
        switch new {
        case .finished, .failed, .stopped:
            if new == .finished { recentlyDone[id] = Date() }
            recordHistory(id, state: new, status: status)
            alert(new == .finished ? .finished : .failed, id: id, status: status)
        case .paused:
            alert(.paused, id: id, status: status)
        default:
            break
        }
    }

    private func recordHistory(_ id: UUID, state: PrintState, status: PrintStatus) {
        let ended = Date()
        let duration = status.elapsed.flatMap { $0 > 0 ? $0 : nil }
        history?.record(HistoryEntry(
            printerID: id,
            printerName: name(of: id),
            fileName: status.fileName,
            result: state.rawValue,
            started: duration.map { ended.addingTimeInterval(-$0) },
            ended: ended,
            duration: duration,
            filamentGrams: status.filamentNeeded
        ))
    }

    private func jobKey(_ status: PrintStatus) -> String {
        status.jobID ?? status.fileName ?? ""
    }

    private func checkProgressAlerts(_ id: UUID, _ status: PrintStatus) {
        var track = tracks[id] ?? AlertTrack()
        let key = jobKey(status)
        if track.job != key {
            track = AlertTrack()
            track.job = key
        }
        if let layer = status.layer {
            if track.lastLayer == 1, layer >= 2, !track.firstLayerDone, status.state.isActive {
                track.firstLayerDone = true
                alert(.firstLayer, id: id, status: status)
            }
            track.lastLayer = layer
        }
        if status.state == .printing, let remaining = status.remaining {
            if let last = track.lastRemaining, last > 600, remaining <= 600, remaining > 0, !track.timeLeftDone {
                track.timeLeftDone = true
                alert(.timeLeft, id: id, status: status)
            }
            track.lastRemaining = remaining
        }
        tracks[id] = track
        checkTemperature(id)
    }

    private func checkTemperature(_ id: UUID) {
        guard let status = statuses[id], var track = tracks[id] else { return }
        if status.state == .printing, let nozzle = status.nozzle, let target = status.nozzleTarget, target > 0, nozzle < target - 15 {
            if track.coldSince == nil { track.coldSince = Date() }
            if let since = track.coldSince, Date().timeIntervalSince(since) >= 60, !track.temperatureDone {
                track.temperatureDone = true
                alert(.temperature, id: id, status: status)
            }
        } else {
            track.coldSince = nil
        }
        tracks[id] = track
    }

    func isAlertOn(_ alert: PrintAlert) -> Bool {
        host?.preferences.value(forKey: alert.prefKey, default: alert.defaultOn) ?? alert.defaultOn
    }

    func alertBinding(_ alert: PrintAlert) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.isAlertOn(alert) ?? alert.defaultOn },
            set: { [weak self] value in
                self?.host?.preferences.setValue(value, forKey: alert.prefKey)
                self?.objectWillChange.send()
            }
        )
    }

    private func alert(_ kind: PrintAlert, id: UUID, status: PrintStatus) {
        guard isAlertOn(kind) else { return }
        let printer = name(of: id)
        let file = status.fileName
        var subtitle = [printer]
        let title: String
        switch kind {
        case .finished:
            title = L.f("hud.finished", file ?? printer)
            if let elapsed = status.elapsed, elapsed > 0 { subtitle.append(L.f("hud.took", Format.duration(elapsed))) }
        case .paused:
            title = L.f("hud.paused", printer)
        case .failed:
            title = L.f("hud.failed", printer)
        case .firstLayer:
            title = L.s("hud.firstLayer")
            if let file { subtitle.append(file) }
        case .timeLeft:
            title = L.s("hud.timeLeft")
            if let left = remaining(status) { subtitle.append(L.f("widget.done", Format.clock(Date().addingTimeInterval(left)))) }
        case .temperature:
            title = L.s("hud.temperature")
            subtitle.append("\(Format.temp(status.nozzle)) / \(Format.temp(status.nozzleTarget))")
        }
        let progress: Double = kind == .finished ? 1 : (status.progress ?? 0.5)
        presentHUD(HUDContent(
            symbol: kind.symbol,
            tint: kind.tint,
            stripText: kind == .finished || kind == .paused || kind == .failed ? Format.state(status.state) : L.s("alert.\(kind.rawValue)"),
            title: title,
            subtitle: subtitle.joined(separator: " · "),
            preview: status.preview,
            progress: progress
        ), duration: kind == .paused ? 6 : 12, high: kind == .failed || kind == .temperature)
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

    func actions(for id: UUID) -> Set<PrintAction> {
        if let connection = connections[id] { return connection.supportedActions }
        return isDemo ? [.pause, .resume, .stop] : []
    }

    func requestAction(_ action: PrintAction, for id: UUID) {
        guard !busy.contains(id), actions(for: id).contains(action) else { return }
        let printer = name(of: id)
        let file = status(of: id).fileName ?? printer
        let confirmed: Bool
        switch action {
        case .stop:
            confirmed = DropletConfirmationDialog.present(
                title: L.f("ctl.stopTitle", printer),
                message: L.f("ctl.stopMessage", file),
                confirmTitle: L.s("ctl.stop"),
                symbol: "stop.circle.fill"
            )
        case .pause:
            confirmed = DropletConfirmationDialog.present(
                title: L.f("ctl.pauseTitle", printer),
                message: L.f("ctl.pauseMessage", file),
                confirmTitle: L.s("ctl.pause"),
                symbol: "pause.circle.fill"
            )
        case .resume:
            confirmed = true
        }
        guard confirmed, let connection = connections[id] else { return }
        busy.insert(id)
        Task { [weak self] in
            let ok = await connection.perform(action)
            guard let self else { return }
            self.busy.remove(id)
            if !ok {
                self.presentHUD(HUDContent(
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange,
                    stripText: L.s("ctl.failedShort"),
                    title: L.f("ctl.failed", L.s("ctl.\(action.rawValue)")),
                    subtitle: printer,
                    preview: nil,
                    progress: 0
                ), duration: 5, high: false)
            }
        }
    }

    private func loadSpoolLinks() -> [UUID: Int] {
        var links: [UUID: Int] = [:]
        for printer in printers {
            if let spool = host?.preferences.value(forKey: "spool.\(printer.id)", as: Int.self), spool > 0 { links[printer.id] = spool }
        }
        return links
    }

    func setSpool(_ spoolID: Int?, for printer: UUID) {
        if let spoolID, spoolID > 0 {
            spoolLinks[printer] = spoolID
            host?.preferences.setValue(spoolID, forKey: "spool.\(printer)")
        } else {
            spoolLinks[printer] = nil
            host?.preferences.setValue(Optional<Int>.none, forKey: "spool.\(printer)")
        }
        updateWidgetLayout()
    }

    func linkedSpool(for printer: UUID) -> Spool? {
        guard let id = spoolLinks[printer] else { return nil }
        return spools.first { $0.id == id }
    }

    func spoolFits(for printer: UUID) -> Bool? {
        SpoolmanClient.fits(needed: status(of: printer).filamentNeeded, spool: linkedSpool(for: printer))
    }

    func testSpoolman(_ address: String) async -> Bool {
        if isDemo { return true }
        guard SpoolmanClient.normalize(address) != nil else { return false }
        return await SpoolmanClient(baseURL: address).health()
    }

    private func scheduleSpoolRefresh() {
        guard host != nil, !isDemo else { return }
        spoolDebounce?.cancel()
        spoolDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            self?.startSpoolLoop()
        }
    }

    private func startSpoolLoop() {
        spoolTask?.cancel()
        spoolTask = Task { [weak self] in
            var last = Date.distantPast
            while !Task.isCancelled {
                guard let self else { return }
                let interval: TimeInterval = self.activeCount > 0 ? 60 : 300
                if Date().timeIntervalSince(last) >= interval {
                    last = Date()
                    await self.refreshSpools()
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    func refreshSpools() async {
        let address = spoolmanAddress
        guard SpoolmanClient.normalize(address) != nil else {
            spools = []
            spoolmanState = .off
            updateWidgetLayout()
            return
        }
        switch await SpoolmanClient(baseURL: address).spools() {
        case .success(let list):
            spools = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            spoolmanState = .ok
        case .failure:
            spoolmanState = .unreachable
        }
        updateWidgetLayout()
    }

    var cameraCandidates: [UUID] {
        if isDemo { return printers.filter { $0.kind != .octoprint }.map(\.id) }
        return printers.filter { p in
            guard let connection = connections[p.id] else { return false }
            return connection.makeCamera() != nil
        }.map(\.id)
    }

    var cameraTarget: UUID? {
        if let selection = cameraSelection, printers.contains(where: { $0.id == selection && $0.isEnabled }) { return selection }
        if let featured { return featured.id }
        return cameraCandidates.first ?? printers.first(where: \.isEnabled)?.id
    }

    func selectCamera(_ id: UUID) {
        cameraSelection = id
        if cameraVisible { startCamera() }
    }

    func cameraAppeared() {
        cameraVisible = true
        startCamera()
    }

    func cameraDisappeared() {
        cameraVisible = false
        stopCamera()
    }

    private func startCamera() {
        stopCamera()
        guard let target = cameraTarget else {
            cameraFeedPrinter = nil
            cameraMessage = nil
            return
        }
        cameraFeedPrinter = target
        if isDemo {
            cameraFrame = Demo.cameraFrame(seed: printers.firstIndex { $0.id == target } ?? 0)
            cameraMessage = nil
            return
        }
        cameraFrame = nil
        guard let connection = connections[target] else {
            cameraMessage = L.s("cam.offline")
            return
        }
        guard let feed = connection.makeCamera() else {
            cameraMessage = Self.unsupportedMessage(kind(of: target))
            return
        }
        cameraMessage = L.s("cam.loading")
        feed.onFrame = { [weak self] data in
            guard let self, self.cameraFeedPrinter == target, let image = NSImage(data: data) else { return }
            self.cameraFrame = image
            self.cameraMessage = nil
        }
        feed.onError = { [weak self] message in
            guard let self, self.cameraFeedPrinter == target else { return }
            if self.cameraFrame == nil { self.cameraMessage = message }
        }
        cameraFeed = feed
        feed.start()
    }

    private func stopCamera() {
        cameraFeed?.onFrame = nil
        cameraFeed?.onError = nil
        cameraFeed?.stop()
        cameraFeed = nil
        cameraFeedPrinter = nil
    }

    static func unsupportedMessage(_ kind: PrinterKind) -> String {
        switch kind {
        case .bambu: return L.s("cam.bambuUnsupported")
        case .anycubicCloud: return L.s("cam.anycubicCloudUnsupported")
        case .anycubic: return L.s("cam.anycubicUnsupported")
        default: return L.s("cam.unavailable")
        }
    }

    func rowHeight(for printer: PrinterConfig) -> CGFloat {
        spoolLinks[printer.id] != nil && linkedSpool(for: printer.id) != nil ? 74 : 56
    }

    var printersWidgetHeight: CGFloat {
        let rows = Array(printers.prefix(3))
        guard !rows.isEmpty else { return 93 }
        let content = rows.reduce(0) { $0 + rowHeight(for: $1) } + CGFloat(rows.count - 1) * DroppySpacing.sm
        return content + 16
    }

    private func updateWidgetLayout() {
        let height = printersWidgetHeight
        guard height != lastWidgetHeight else { return }
        let first = lastWidgetHeight == 0
        lastWidgetHeight = height
        if !first { host?.shelf.invalidateLayout(for: Self.widgetID) }
    }

    private func publishSurfaces() {
        updateWidgetLayout()
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

    private func presentHUD(_ content: HUDContent, duration: TimeInterval, high: Bool) {
        guard let host else { return }
        let request = DropletHUDRequest(
            id: Self.hudID,
            duration: duration,
            priority: high ? .high : .normal,
            accessibilityLabel: "\(content.title). \(content.subtitle)",
            isExpanded: true,
            expandedContentHeight: 96
        ) {
            PrintHUDStrip(content: content)
        } expanded: {
            PrintHUDCard(content: content)
        }
        _ = host.hud.present(request)
    }

    private func loadDemo() {
        let a = PrinterConfig(name: "Kobra S1", kind: .anycubic, host: "192.168.1.40")
        let b = PrinterConfig(name: "P1S", kind: .bambu, host: "192.168.1.41", serial: "01P00A000000000", accessCode: "12345678")
        let c = PrinterConfig(name: "Ender 3", kind: .octoprint, host: "octopi.local", apiKey: "demo")
        printers = [a, b, c]
        statuses[a.id] = PrintStatus(state: .printing, progress: 0.62, remaining: 4920, elapsed: 7800, layer: 186, totalLayers: 300,
                                     fileName: "Benchy", nozzle: 220, nozzleTarget: 220, bed: 60, bedTarget: 60,
                                     preview: .data(Demo.preview(hue: 0.08)), slots: Demo.aceSlots, filamentNeeded: 48, jobID: "demo-a")
        statuses[b.id] = PrintStatus(state: .printing, progress: 0.18, remaining: 9300, elapsed: 2000, layer: 41, totalLayers: 230,
                                     fileName: "Planter", nozzle: 218, nozzleTarget: 220, bed: 55, bedTarget: 55,
                                     preview: .data(Demo.preview(hue: 0.33)), slots: Demo.amsSlots, filamentNeeded: 64, jobID: "demo-b")
        statuses[c.id] = PrintStatus(state: .idle, nozzle: 24, nozzleTarget: 0, bed: 23, bedTarget: 0)
        spoolmanAddress = "spoolman.local:7912"
        spools = Demo.spools
        spoolmanState = .ok
        spoolLinks = [a.id: 1, b.id: 2]
        let demoHistory = PrintHistory(directory: FileManager.default.temporaryDirectory.appendingPathComponent("print-live-demo-\(UUID().uuidString)"))
        for entry in Demo.history(printers: [a, b, c]) { demoHistory.record(entry) }
        history = demoHistory
        if ProcessInfo.processInfo.environment["PRINT_LIVE_DEMO"] == "done" {
            let done = PrintStatus(state: .finished, progress: 1, elapsed: 12720, fileName: "Benchy", preview: .data(Demo.preview(hue: 0.08)))
            alert(.finished, id: a.id, status: done)
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
        let list = [
            ShelfWidgetDescriptor(
                id: Self.widgetID,
                title: "Print Live",
                systemImage: "printer.fill",
                layoutTraits: ShelfWidgetLayoutTraits(
                    preferredSoloWidth: 440,
                    preferredPairedWidth: 230,
                    contentHeight: .fixed(printersWidgetHeight)
                )
            ),
            ShelfWidgetDescriptor(
                id: Self.cameraWidgetID,
                title: L.s("cam.title"),
                systemImage: "video.fill",
                layoutTraits: ShelfWidgetLayoutTraits(
                    preferredSoloWidth: 440,
                    preferredPairedWidth: 260,
                    contentHeight: .fixed(250)
                ),
                prewarmPolicy: .never
            )
        ]
        return isDemo && ProcessInfo.processInfo.environment["PRINT_LIVE_DEMO"] == "camera" ? list.reversed() : list
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        if id == Self.cameraWidgetID { return AnyView(PrintCameraWidget(droplet: self, context: context)) }
        return AnyView(PrintShelfWidget(droplet: self, context: context))
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
}

extension PrintLiveDroplet: MenuBarExtraProviding {
    public func makeMenuBarExtra() -> MenuBarExtraDescriptor? {
        guard !printers.isEmpty else { return nil }
        return MenuBarExtraDescriptor(title: "Print Live", systemImage: "printer.fill") { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(PrintMenuBarContent(droplet: self))
        }
    }
}

extension PrintLiveDroplet: SettingsPaneProviding {
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView { AnyView(PrintLiveSettings(droplet: self)) }

    public var settingsSearchEntries: [SettingsSearchEntry] {
        [
            SettingsSearchEntry(title: L.s("set.printers"), keywords: ["octoprint", "bambu", "anycubic", "klipper", "moonraker", "cloud", "printer", "3d"]),
            SettingsSearchEntry(title: "Spoolman", keywords: ["spool", "filament", "spoolman"]),
            SettingsSearchEntry(title: L.s("set.alerts"), keywords: ["alert", "notification", "layer", "temperature"]),
            SettingsSearchEntry(title: L.s("set.history"), keywords: ["history", "statistics", "prints"])
        ]
    }
}
