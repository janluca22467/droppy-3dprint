import Foundation

@MainActor
final class MoonrakerConnection: PrinterConnection {
    var onStatus: ((PrintStatus) -> Void)?
    private let config: PrinterConfig
    private var task: Task<Void, Never>?
    private var estimates: [String: Double] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 6
        return URLSession(configuration: c)
    }()

    init(config: PrinterConfig) { self.config = config }

    private var baseURL: URL? {
        var host = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.hasPrefix("http://") && !host.hasPrefix("https://") { host = "http://" + host }
        while host.hasSuffix("/") { host.removeLast() }
        guard var components = URLComponents(string: host) else { return nil }
        if components.port == nil { components.port = 7125 }
        return components.url
    }

    func start() {
        stop()
        onStatus?(PrintStatus(state: .connecting))
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let status = await self.poll()
                guard !Task.isCancelled else { return }
                self.onStatus?(status)
                try? await Task.sleep(nanoseconds: status.state.isActive ? 4_000_000_000 : 10_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func get(_ path: String, query: [URLQueryItem] = []) async -> (Int, [String: Any]?) {
        guard let base = baseURL, var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { return (0, nil) }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { return (0, nil) }
        var request = URLRequest(url: url)
        if !config.apiKey.isEmpty { request.setValue(config.apiKey, forHTTPHeaderField: "X-Api-Key") }
        guard let (data, response) = try? await session.data(for: request) else { return (0, nil) }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (code, try? JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func poll() async -> PrintStatus {
        let objects = ["print_stats", "virtual_sdcard", "display_status", "extruder", "heater_bed"]
        let (code, json) = await get("printer/objects/query", query: objects.map { URLQueryItem(name: $0, value: nil) })
        if code == 0 { return PrintStatus(state: .offline, message: L.s("err.unreachable")) }
        if code == 401 || code == 403 { return PrintStatus(state: .offline, message: L.s("err.apiKey")) }
        guard let status = (json?["result"] as? [String: Any])?["status"] as? [String: Any] else {
            return PrintStatus(state: .offline, message: L.s(code == 503 ? "err.klippy" : "err.unreachable"))
        }

        let stats = status["print_stats"] as? [String: Any] ?? [:]
        let sdcard = status["virtual_sdcard"] as? [String: Any] ?? [:]
        let display = status["display_status"] as? [String: Any] ?? [:]
        let extruder = status["extruder"] as? [String: Any] ?? [:]
        let bed = status["heater_bed"] as? [String: Any] ?? [:]

        var s = PrintStatus()
        switch (stats["state"] as? String ?? "").lowercased() {
        case "printing": s.state = .printing
        case "paused": s.state = .paused
        case "complete": s.state = .finished
        case "cancelled": s.state = .stopped
        case "error": s.state = .failed
        default: s.state = .idle
        }

        let file = stats["filename"] as? String
        s.fileName = file.cleanedFileName
        let progress = number(display["progress"]).flatMap { $0 > 0 ? $0 : nil } ?? number(sdcard["progress"])
        s.progress = progress
        let printed = number(stats["print_duration"])
        s.elapsed = number(stats["total_duration"]) ?? printed

        if s.state.isActive, let printed {
            if let file, !file.isEmpty, let estimate = await estimate(for: file), estimate > printed {
                s.remaining = estimate - printed
            } else if let progress, progress > 0.02 {
                s.remaining = printed / progress - printed
            }
        }

        if let info = stats["info"] as? [String: Any] {
            s.layer = number(info["current_layer"]).map(Int.init)
            s.totalLayers = number(info["total_layer"]).map(Int.init)
        }
        s.nozzle = number(extruder["temperature"])
        s.nozzleTarget = number(extruder["target"])
        s.bed = number(bed["temperature"])
        s.bedTarget = number(bed["target"])
        if s.state == .finished { s.progress = 1; s.remaining = 0 }
        s.updated = Date()
        return s
    }

    private func estimate(for file: String) async -> Double? {
        if let cached = estimates[file] { return cached > 0 ? cached : nil }
        let (_, json) = await get("server/files/metadata", query: [URLQueryItem(name: "filename", value: file)])
        let value = number((json?["result"] as? [String: Any])?["estimated_time"]) ?? 0
        estimates[file] = value
        return value > 0 ? value : nil
    }

    private func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
