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
    private var isConnected = false
    private var sequence = 20_000
    private var pending: [String: (action: PrintAction, continuation: CheckedContinuation<Bool, Never>)] = [:]

    init(config: PrinterConfig) { self.config = config }

    private var serial: String { config.serial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    private var host: String { config.host.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var accessCode: String { config.accessCode.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isP1OrA1: Bool { ["01S", "01P", "030", "039"].contains(where: serial.hasPrefix) }

    var supportedActions: Set<PrintAction> { [.pause, .resume, .stop] }

    func start() {
        stop()
        stopped = false
        merged = [:]
        onStatus?(PrintStatus(state: .connecting))
        let client = MQTTClient(
            host: host,
            port: 8883,
            clientID: "print-live-\(UUID().uuidString.prefix(8))",
            username: "bblp",
            password: accessCode
        )
        self.client = client
        client.connect { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    func stop() {
        stopped = true
        isConnected = false
        refreshTask?.cancel(); refreshTask = nil
        retryTask?.cancel(); retryTask = nil
        client?.disconnect()
        client = nil
        failPending()
    }

    func makeCamera() -> CameraFeed? {
        if let ipcam = merged["ipcam"] as? [String: Any],
           let rtsp = ipcam["rtsp_url"] as? String, rtsp.lowercased().hasPrefix("rtsp") {
            return nil
        }
        guard !host.isEmpty, !accessCode.isEmpty else { return nil }
        return BambuCameraFeed(host: host, accessCode: accessCode)
    }

    func perform(_ action: PrintAction) async -> Bool {
        guard isConnected, let client else { return false }
        sequence += 1
        let seq = String(sequence)
        let body: [String: Any] = ["print": ["sequence_id": seq, "command": action.rawValue, "param": ""]]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return false }
        client.publish("device/\(serial)/request", payload)
        return await withCheckedContinuation { continuation in
            pending[seq] = (action, continuation)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard let self else { return }
                self.resolve(seq, self.stateMatches(action))
            }
        }
    }

    private func resolve(_ seq: String, _ result: Bool) {
        guard let entry = pending.removeValue(forKey: seq) else { return }
        entry.continuation.resume(returning: result)
    }

    private func failPending() {
        let all = pending
        pending = [:]
        for entry in all.values { entry.continuation.resume(returning: false) }
    }

    private func stateMatches(_ action: PrintAction) -> Bool {
        let state = (merged["gcode_state"] as? String ?? "").uppercased()
        switch action {
        case .pause: return state == "PAUSE"
        case .resume: return state == "RUNNING"
        case .stop: return ["IDLE", "FINISH", "FAILED"].contains(state)
        }
    }

    private func handle(_ event: MQTTClient.Event) {
        guard !stopped else { return }
        switch event {
        case .connected:
            isConnected = true
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
            if let seq = print["sequence_id"].map({ "\($0)" }), let entry = pending[seq],
               (print["command"] as? String) == entry.action.rawValue,
               let result = print["result"] as? String {
                resolve(seq, result.lowercased() == "success")
            }
            if (print["command"] as? String) == "push_status" || print["gcode_state"] != nil || print["ams"] != nil {
                merged = Self.deepMerge(merged, print)
                onStatus?(status(from: merged))
            }
        case .disconnected(let reason):
            client = nil
            isConnected = false
            refreshTask?.cancel()
            failPending()
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
        if !isP1OrA1, let chamber = number(p["chamber_temper"]), chamber > 0 { s.chamber = chamber }
        s.jobID = jobID(from: p)
        s.slots = slots(from: p)
        if s.state == .finished { s.progress = 1; s.remaining = 0 }
        s.updated = Date()
        return s
    }

    private func jobID(from p: [String: Any]) -> String? {
        for key in ["job_id", "task_id", "subtask_id"] {
            if let value = p[key].map({ "\($0)" }), !value.isEmpty, value != "0", value != "<null>" {
                return value
            }
        }
        return nil
    }

    private func slots(from p: [String: Any]) -> [FilamentSlot] {
        var result: [FilamentSlot] = []
        let ams = p["ams"] as? [String: Any]
        let trayNow = ams?["tray_now"].map { "\($0)" }.flatMap { Int($0) }
        let units = (ams?["ams"] as? [[String: Any]]) ?? []
        for unit in units {
            guard let unitID = number(unit["id"]).map(Int.init) else { continue }
            let isHT = unitID >= 128
            let letter = isHT ? "HT\(unitID - 127)" : String(UnicodeScalar(UInt8(65 + min(unitID, 25))))
            let trays = (unit["tray"] as? [[String: Any]]) ?? []
            for tray in trays {
                guard let trayID = number(tray["id"]).map(Int.init) else { continue }
                let globalIndex = isHT ? unitID : unitID * 4 + trayID
                var slot = slot(from: tray, id: "\(letter)\(trayID + 1)", unit: "AMS \(letter)")
                slot.isActive = trayNow == globalIndex
                result.append(slot)
            }
        }
        if let ext = p["vt_tray"] as? [String: Any] {
            var slot = slot(from: ext, id: "Ext", unit: nil)
            slot.isActive = trayNow == 254
            if !slot.isEmpty || slot.isActive { result.append(slot) }
        }
        return result
    }

    private func slot(from tray: [String: Any], id: String, unit: String?) -> FilamentSlot {
        let material = (tray["tray_type"] as? String)?.trimmingCharacters(in: .whitespaces)
        var slot = FilamentSlot(id: id, unit: unit)
        guard let material, !material.isEmpty else {
            slot.isEmpty = true
            return slot
        }
        slot.material = material
        if let color = tray["tray_color"] as? String, color.count >= 6 {
            let rgb = String(color.prefix(6)).uppercased()
            if rgb.allSatisfy(\.isHexDigit) { slot.colorHex = rgb }
        }
        if let remain = number(tray["remain"]), remain >= 0 { slot.remaining = min(remain, 100) / 100 }
        return slot
    }

    static func deepMerge(_ base: [String: Any], _ update: [String: Any]) -> [String: Any] {
        var out = base
        for (key, new) in update {
            if let newDict = new as? [String: Any], let oldDict = out[key] as? [String: Any] {
                out[key] = deepMerge(oldDict, newDict)
            } else if let newArray = new as? [[String: Any]], let oldArray = out[key] as? [[String: Any]],
                      !newArray.isEmpty, newArray.allSatisfy({ $0["id"] != nil }) {
                var merged = oldArray
                for element in newArray {
                    let id = "\(element["id"]!)"
                    if let i = merged.firstIndex(where: { $0["id"].map { "\($0)" } == id }) {
                        merged[i] = key == "tray" ? element : deepMerge(merged[i], element)
                    } else {
                        merged.append(element)
                    }
                }
                out[key] = merged
            } else {
                out[key] = new
            }
        }
        return out
    }

    private func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
