import CryptoKit
import Foundation

@MainActor
final class AnycubicCloudConnection: PrinterConnection {
    var onStatus: ((PrintStatus) -> Void)?
    private let config: PrinterConfig
    private var task: Task<Void, Never>?
    private var tokenChecked = false
    private var current: PrintStatus?
    private var printerID: String?
    private var projectID: String?

    private static let imageBase = "https://workbentch.s3.us-east-2.amazonaws.com/"

    private static let base = "https://cloud-universe.anycubic.com/p/p/workbench/api"
    private static let appID = "f9b3528877c94d5c9c5af32245db46ef"
    private static let appSecret = "0cf75926606049a3937f56b0373b99fb"
    private static let version = "1.0.0"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"

    private enum Reply { case data(Any?), busy, denied, unreachable }

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        return URLSession(configuration: c)
    }()

    init(config: PrinterConfig) { self.config = config }

    var supportedActions: Set<PrintAction> { [.pause, .resume, .stop] }

    func makeCamera() -> CameraFeed? { nil }

    func perform(_ action: PrintAction) async -> Bool {
        guard let current, current.state.isActive,
              let printer = printerID.flatMap({ Int64($0) }),
              let project = projectID.flatMap({ Int64($0) }) else { return false }
        let order: Int
        switch action {
        case .pause: order = 2
        case .resume: order = 3
        case .stop: order = 4
        }
        let body: [String: Any] = [
            "order_id": order,
            "printer_id": printer,
            "project_id": project,
            "data": NSNull(),
            "ams_info": NSNull(),
            "settings": NSNull(),
        ]
        guard case .data(let data) = await request("work/operation/sendOrder", body: body),
              let reply = data as? [String: Any],
              let msgid = reply["msgid"], !(msgid is NSNull) else { return false }
        return true
    }

    private var token: String {
        config.apiKey.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
    }

    func start() {
        stop()
        tokenChecked = false
        current = nil
        onStatus?(PrintStatus(state: .connecting))
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let (status, delay) = await self.poll()
                guard !Task.isCancelled else { return }
                if let status {
                    self.current = status
                    self.onStatus?(status)
                }
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func get(_ path: String, query: [URLQueryItem] = []) async -> Reply {
        await request(path, query: query)
    }

    private func request(_ path: String, query: [URLQueryItem] = [], body: [String: Any]? = nil) async -> Reply {
        guard var components = URLComponents(string: "\(Self.base)/\(path)") else { return .unreachable }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { return .unreachable }
        let nonce = UUID().uuidString.lowercased()
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        let signed = Self.appID + timestamp + Self.version + Self.appSecret + nonce + Self.appID
        let signature = Insecure.MD5.hash(data: Data(signed.utf8)).map { String(format: "%02x", $0) }.joined()
        let headers = [
            "Xx-Device-Type": "web",
            "Xx-Is-Cn": "1",
            "Xx-Nonce": nonce,
            "Xx-Timestamp": timestamp,
            "Xx-Version": Self.version,
            "Xx-Signature": signature,
            "Content-Type": "application/json",
            "XX-Token": token,
            "XX-LANGUAGE": "US",
            "Origin": "https://uc.makeronline.com",
            "User-Agent": Self.userAgent,
        ]
        var request = URLRequest(url: url)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let body {
            guard let encoded = try? JSONSerialization.data(withJSONObject: body) else { return .unreachable }
            request.httpMethod = "POST"
            request.httpBody = encoded
        }
        guard let (data, response) = try? await session.data(for: request) else { return .unreachable }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { return .denied }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return code == 429 || code >= 500 ? .busy : .unreachable
        }
        if (json["msg"] as? String)?.lowercased() == "request error" { return .busy }
        let payload = json["data"]
        return .data(payload is NSNull ? nil : payload)
    }

    private func poll() async -> (PrintStatus?, UInt64) {
        if !tokenChecked {
            switch await get("user/profile/userInfo") {
            case .data(let data):
                guard let id = (data as? [String: Any])?["id"], !(id is NSNull) else { return (offline("err.token"), 120) }
                tokenChecked = true
            case let reply:
                return failure(reply)
            }
        }

        let printers: [[String: Any]]
        switch await get("work/printer/getPrinters") {
        case .data(let data):
            guard let list = data as? [[String: Any]] else {
                tokenChecked = false
                return (offline("err.noPrinter"), 60)
            }
            printers = list
        case let reply:
            return failure(reply)
        }

        let wanted = config.serial.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let match = wanted.isEmpty ? printers.first : printers.first { ($0["name"] as? String ?? "").lowercased() == wanted }
        guard let printer = match, let printerID = text(printer["id"]) else { return (offline("err.noPrinter"), 60) }
        self.printerID = printerID
        projectID = nil

        var s = PrintStatus()
        var deviceStatus = number(printer["device_status"])
        switch await get("v2/printer/info", query: [URLQueryItem(name: "id", value: printerID)]) {
        case .data(let data):
            let info = data as? [String: Any] ?? [:]
            let parameter = info["parameter"] as? [String: Any] ?? [:]
            s.nozzle = number(parameter["curr_nozzle_temp"])
            s.bed = number(parameter["curr_hotbed_temp"])
            deviceStatus = number(info["device_status"]) ?? deviceStatus
            s.slots = AnycubicConnection.aceSlots(info["multi_color_box"])
        case let reply:
            return failure(reply)
        }
        guard deviceStatus == 1 else { return (offline("err.unreachable"), 60) }

        switch await get("work/project/getProjects", query: [URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "limit", value: "10")]) {
        case .data(let data):
            let jobs = data as? [[String: Any]] ?? []
            if let job = jobs.first(where: { text($0["printer_id"]) == printerID }) {
                apply(job, to: &s)
                if s.state.isActive { projectID = text(job["id"]) }
                if s.state.isActive, let projectID = text(job["id"]),
                   case .data(let data) = await get("v2/project/info", query: [URLQueryItem(name: "id", value: projectID)]),
                   let temp = (data as? [String: Any])?["temp"] as? [String: Any] {
                    s.nozzleTarget = number(temp["target_nozzle_temp"])
                    s.bedTarget = number(temp["target_hotbed_temp"])
                }
            } else {
                s.state = .idle
            }
        case let reply:
            return failure(reply)
        }
        s.updated = Date()
        return (s, s.state.isActive ? 30 : 60)
    }

    private func apply(_ job: [String: Any], to s: inout PrintStatus) {
        switch Int(number(job["print_status"]) ?? 0) {
        case 1: s.state = .printing
        case 2: s.state = .finished
        case 3: s.state = .stopped
        case 4, 5, 6, 7, 9: s.state = .preparing
        default: s.state = .idle
        }
        if s.state.isActive, (number(job["pause"]) ?? 0) != 0 { s.state = .paused }

        var end = number(job["end_time"]) ?? 0
        if end > 1_000_000_000_000 { end /= 1000 }
        if s.state == .finished || s.state == .stopped, end > 0, Date().timeIntervalSince1970 - end > 1800 { s.state = .idle }
        guard s.state != .idle else { return }

        s.fileName = (job["gcode_name"] as? String).cleanedFileName
        s.progress = number(job["progress"]).map { min(max($0 / 100, 0), 1) }
        s.remaining = number(job["remain_time"]).map { $0 * 60 }
        s.elapsed = number(job["print_time"]).map { $0 * 60 }

        let settings = (job["settings"] as? [String: Any])
            ?? (job["settings"] as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        s.layer = number(settings?["curr_layer"]).map { Int($0) }
        s.totalLayers = number(settings?["total_layers"]).map { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
        s.jobID = text(job["id"]) ?? text(job["taskid"])

        let slice = (job["slice_param"] as? [String: Any])
            ?? (job["slice_param"] as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        s.preview = previewURL(job["img"] as? String) ?? previewURL(slice?["image_id"] as? String)
        s.filamentNeeded = grams(in: slice)
        if s.state == .finished { s.progress = 1; s.remaining = 0 }
    }

    private func previewURL(_ path: String?) -> PreviewImage? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return nil }
        let link = path.lowercased().hasPrefix("http") ? path : Self.imageBase + (path.hasPrefix("/") ? String(path.dropFirst()) : path)
        return URL(string: link).map { .url($0) }
    }

    private func grams(in slice: [String: Any]?) -> Double? {
        guard let slice else { return nil }
        let keys = ["filament_weight", "filament_used_g", "used_g", "total_weight", "weight"]
        for key in keys {
            if let g = number(slice[key]), g > 0 { return g }
        }
        if let materials = slice["paint_infos"] as? [[String: Any]] {
            let total = materials.compactMap { m in keys.lazy.compactMap { self.number(m[$0]) }.first }.reduce(0, +)
            if total > 0 { return total }
        }
        return nil
    }

    private func failure(_ reply: Reply) -> (PrintStatus?, UInt64) {
        switch reply {
        case .busy:
            if let current, current.state != .offline { return (nil, 120) }
            return (offline("err.cloudBusy"), 120)
        case .denied:
            tokenChecked = false
            return (offline("err.token"), 120)
        case .unreachable, .data:
            return (offline("err.unreachable"), 60)
        }
    }

    private func offline(_ key: String) -> PrintStatus {
        PrintStatus(state: .offline, message: L.s(key))
    }

    private func text(_ value: Any?) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
