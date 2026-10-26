import Foundation

@MainActor
final class MoonrakerConnection: PrinterConnection {
    var onStatus: ((PrintStatus) -> Void)?
    private let config: PrinterConfig
    private var task: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
    private var streamURL: URL?
    private var metadata: [String: FileMetadata] = [:]
    private var currentJob: (file: String, id: String, duration: Double)?
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 6
        return URLSession(configuration: c)
    }()

    private struct FileMetadata {
        var estimate: Double?
        var weight: Double?
        var preview: URL?
    }

    init(config: PrinterConfig) { self.config = config }

    var supportedActions: Set<PrintAction> { [.pause, .resume, .stop] }

    private var baseURL: URL? {
        var host = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.hasPrefix("http://") && !host.hasPrefix("https://") { host = "http://" + host }
        while host.hasSuffix("/") { host.removeLast() }
        guard var components = URLComponents(string: host) else { return nil }
        if components.port == nil { components.port = 7125 }
        return components.url
    }

    private var webURL: URL? {
        guard let base = baseURL, var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "http"
        components.port = nil
        components.path = "/"
        components.query = nil
        return components.url
    }

    private var headers: [String: String] {
        config.apiKey.isEmpty ? [:] : ["X-Api-Key": config.apiKey]
    }

    func start() {
        stop()
        onStatus?(PrintStatus(state: .connecting))
        settingsTask = Task { [weak self] in
            guard let self else { return }
            let (_, json) = await self.get("server/webcams/list")
            guard !Task.isCancelled else { return }
            let cams = ((json?["result"] as? [String: Any])?["webcams"] as? [[String: Any]] ?? [])
                .filter { ($0["enabled"] as? Bool ?? true) && !($0["stream_url"] as? String ?? "").isEmpty }
            let preferred = cams.first { ($0["service"] as? String ?? "mjpeg").lowercased().contains("mjpeg") } ?? cams.first
            if let stream = preferred?["stream_url"] as? String { self.streamURL = self.resolveWeb(stream) }
        }
        runLoop()
    }

    func stop() {
        task?.cancel()
        task = nil
        settingsTask?.cancel()
        settingsTask = nil
    }

    func makeCamera() -> CameraFeed? {
        guard let url = streamURL ?? webURL.flatMap({ URL(string: "webcam/?action=stream", relativeTo: $0)?.absoluteURL }) else { return nil }
        return MJPEGCameraFeed(url: url)
    }

    func perform(_ action: PrintAction) async -> Bool {
        let path: String
        switch action {
        case .pause: path = "printer/print/pause"
        case .resume: path = "printer/print/resume"
        case .stop: path = "printer/print/cancel"
        }
        guard let url = baseURL?.appendingPathComponent(path) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        guard let (_, response) = try? await session.data(for: request) else { return false }
        let ok = (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0)
        if ok, task != nil { runLoop() }
        return ok
    }

    private func resolveWeb(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let root = webURL else { return nil }
        let text = URL(string: trimmed) != nil ? trimmed : (trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? trimmed)
        guard let url = URL(string: text, relativeTo: root)?.absoluteURL, url.scheme == "http" || url.scheme == "https" else { return nil }
        return url
    }

    private func runLoop() {
        task?.cancel()
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

        var meta: FileMetadata?
        if let file, !file.isEmpty {
            meta = await fileMetadata(for: file)
            s.filamentNeeded = meta?.weight
            if let preview = meta?.preview { s.preview = .url(preview, headers: headers) }
            s.jobID = jobID(file: file, state: s.state, duration: number(stats["total_duration"]))
        } else {
            currentJob = nil
        }

        if s.state.isActive, let printed {
            if let estimate = meta?.estimate, estimate > printed {
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

    private func fileMetadata(for file: String) async -> FileMetadata? {
        if let cached = metadata[file] { return cached }
        let (code, json) = await get("server/files/metadata", query: [URLQueryItem(name: "filename", value: file)])
        guard code != 0 else { return nil }
        let result = json?["result"] as? [String: Any] ?? [:]
        var meta = FileMetadata()
        meta.estimate = number(result["estimated_time"]).flatMap { $0 > 0 ? $0 : nil }
        if let weight = number(result["filament_weight_total"]), weight > 0 {
            meta.weight = weight
        } else if let length = number(result["filament_total"]), length > 0 {
            meta.weight = length / 1000 * 2.98
        }
        let thumbs = result["thumbnails"] as? [[String: Any]] ?? []
        let largest = thumbs
            .filter { !($0["relative_path"] as? String ?? "").isEmpty }
            .max { (number($0["width"]) ?? 0) * (number($0["height"]) ?? 0) < (number($1["width"]) ?? 0) * (number($1["height"]) ?? 0) }
        if let relative = largest?["relative_path"] as? String, let base = baseURL {
            let dir = (file as NSString).deletingLastPathComponent
            let path = (dir.isEmpty ? "" : dir + "/") + relative
            if let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                meta.preview = URL(string: base.absoluteString + "/server/files/gcodes/" + encoded)
            }
        }
        if json?["result"] != nil || code == 404 { metadata[file] = meta }
        return meta
    }

    private func jobID(file: String, state: PrintState, duration: Double?) -> String? {
        let time = duration ?? 0
        if let current = currentJob, current.file == file, time + 30 >= current.duration {
            currentJob?.duration = max(current.duration, time)
            return current.id
        }
        guard state.isActive || currentJob?.file != file else { return currentJob?.id }
        let started = Int(Date().timeIntervalSince1970 - time)
        let id = "\(file)@\(started)"
        currentJob = (file, id, time)
        return id
    }

    private func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
