import Foundation

@MainActor
final class BambuConnection: PrinterConnection {
    var onStatus: ((PrintStatus) -> Void)?
    private let config: PrinterConfig
    private var client: MQTTClient?
    private var merged: [String: Any] = [:]
    private var refreshTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var stopped = true

    init(config: PrinterConfig) { self.config = config }

    private var serial: String { config.serial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }

    func start() {
        stop()
        stopped = false
        merged = [:]
        onStatus?(PrintStatus(state: .connecting))
        let client = MQTTClient(
            host: config.host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: 8883,
            clientID: "print-live-\(UUID().uuidString.prefix(8))",
            username: "bblp",
            password: config.accessCode.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        self.client = client
        client.connect { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    func stop() {
        stopped = true
        refreshTask?.cancel(); refreshTask = nil
        retryTask?.cancel(); retryTask = nil
        client?.disconnect()
        client = nil
    }

    private func handle(_ event: MQTTClient.Event) {
        guard !stopped else { return }
        switch event {
        case .connected:
            client?.subscribe("device/\(serial)/report")
            requestFullStatus()
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 120_000_000_000)
                    self?.requestFullStatus()
                }
            }
        case .message(_, let payload):
            guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                  let print = json["print"] as? [String: Any] else { return }
            merged.merge(print) { _, new in new }
            onStatus?(status(from: merged))
        case .disconnected(let reason):
            client = nil
            refreshTask?.cancel()
            let message = reason.contains("refused") ? L.s("err.accessCode") : L.s("err.unreachable")
            onStatus?(PrintStatus(state: .offline, message: message))
            retryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self, !Task.isCancelled, !self.stopped else { return }
                self.start()
            }
        }
    }

    private func requestFullStatus() {
        let body = #"{"pushing":{"sequence_id":"0","command":"pushall","version":1,"push_target":1}}"#
        client?.publish("device/\(serial)/request", Data(body.utf8))
    }

    private func status(from p: [String: Any]) -> PrintStatus {
        var s = PrintStatus()
        switch (p["gcode_state"] as? String ?? "").uppercased() {
        case "RUNNING": s.state = .printing
        case "PREPARE", "SLICING", "INIT": s.state = .preparing
        case "PAUSE": s.state = .paused
        case "FINISH": s.state = .finished
        case "FAILED": s.state = .failed
        case "IDLE", "": s.state = .idle
        default: s.state = .idle
        }
        if let percent = number(p["mc_percent"]) { s.progress = percent / 100 }
        if let minutes = number(p["mc_remaining_time"]) { s.remaining = minutes * 60 }
        s.layer = number(p["layer_num"]).map(Int.init)
        s.totalLayers = number(p["total_layer_num"]).map(Int.init)
        s.fileName = ((p["subtask_name"] as? String) ?? (p["gcode_file"] as? String)).cleanedFileName
        s.nozzle = number(p["nozzle_temper"])
        s.nozzleTarget = number(p["nozzle_target_temper"])
        s.bed = number(p["bed_temper"])
        s.bedTarget = number(p["bed_target_temper"])
        if s.state == .finished { s.progress = 1; s.remaining = 0 }
        s.updated = Date()
        return s
    }

    private func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
