import Foundation

@MainActor
final class OctoPrintConnection: PrinterConnection {
    var onStatus: ((PrintStatus) -> Void)?
    private let config: PrinterConfig
    private var task: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
    private var streamURL: URL?
    private var thumbnails: [String: URL?] = [:]
    private var currentJob: (file: String, id: String, printTime: Double)?
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 6
        return URLSession(configuration: c)
    }()

    init(config: PrinterConfig) { self.config = config }

    var supportedActions: Set<PrintAction> { [.pause, .resume, .stop] }

    var baseURL: URL? {
        var host = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.hasPrefix("http://") && !host.hasPrefix("https://") { host = "http://" + host }
        while host.hasSuffix("/") { host.removeLast() }
        return URL(string: host)
    }

    func start() {
        stop()
        onStatus?(PrintStatus(state: .connecting))
        settingsTask = Task { [weak self] in
            guard let self else { return }
            let (_, settings) = await self.get("api/settings")
            guard !Task.isCancelled else { return }
            let webcam = settings?["webcam"] as? [String: Any]
            if let stream = webcam?["streamUrl"] as? String {
                self.streamURL = self.resolve(stream)
            }
        }
        runLoop()
    }

    func stop() {
        task?.cancel()
        task = nil
        settingsTask?.cancel()
        settingsTask = nil
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

    var snapshotURL: URL? { baseURL?.appendingPathComponent("webcam/").appending(queryItems: [URLQueryItem(name: "action", value: "snapshot")]) }

    var fallbackStreamURL: URL? { baseURL?.appendingPathComponent("webcam/").appending(queryItems: [URLQueryItem(name: "action", value: "stream")]) }

    func makeCamera() -> CameraFeed? {
        guard let url = streamURL ?? fallbackStreamURL else { return nil }
        return MJPEGCameraFeed(url: url, headers: ["X-Api-Key": config.apiKey])
    }

    func perform(_ action: PrintAction) async -> Bool {
        let body: [String: String]
        switch action {
        case .pause: body = ["command": "pause", "action": "pause"]
        case .resume: body = ["command": "pause", "action": "resume"]
        case .stop: body = ["command": "cancel"]
        }
        let code = await post("api/job", body: body)
        let ok = (200..<300).contains(code)
        if ok, task != nil { runLoop() }
        return ok
    }

    private func resolve(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let base = baseURL, let root = URL(string: base.absoluteString + "/") else { return nil }
        let text = URL(string: trimmed) != nil ? trimmed : (trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? trimmed)
        guard let url = URL(string: text, relativeTo: root)?.absoluteURL, url.scheme == "http" || url.scheme == "https" else { return nil }
        return url
    }

    private func get(_ path: String) async -> (Int, [String: Any]?) {
        guard let url = baseURL?.appendingPathComponent(path) else { return (0, nil) }
        var request = URLRequest(url: url)
        request.setValue(config.apiKey, forHTTPHeaderField: "X-Api-Key")
        guard let (data, response) = try? await session.data(for: request) else { return (0, nil) }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (code, try? JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func post(_ path: String, body: [String: String]) async -> Int {
        guard let url = baseURL?.appendingPathComponent(path) else { return 0 }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, response) = try? await session.data(for: request) else { return 0 }
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    private func thumbnail(for path: String) async -> URL? {
        if let cached = thumbnails[path] { return cached }
        let (code, json) = await get("api/files/local/" + path)
        guard code != 0 else { return nil }
        let url = (json?["thumbnail"] as? String).flatMap(resolve)
        thumbnails[path] = url
        return url
    }

    private func poll() async -> PrintStatus {
        let (jobCode, job) = await get("api/job")
        if jobCode == 0 { return PrintStatus(state: .offline, message: L.s("err.unreachable")) }
        if jobCode == 401 || jobCode == 403 { return PrintStatus(state: .offline, message: L.s("err.apiKey")) }
        guard let job else { return PrintStatus(state: .offline, message: L.f("err.http", jobCode)) }
        let (_, printer) = await get("api/printer")

        var status = PrintStatus()
        let stateText = (job["state"] as? String ?? "").lowercased()
        if stateText.contains("offline") || stateText.contains("error") && !stateText.contains("printing") {
            status.state = stateText.contains("error") ? .failed : .offline
        } else if stateText.contains("pausing") || stateText.contains("paused") {
            status.state = .paused
        } else if stateText.contains("printing") {
            status.state = .printing
        } else if stateText.contains("cancelling") {
            status.state = .stopped
        } else if stateText.contains("starting") {
            status.state = .preparing
        } else {
            status.state = .idle
        }

        let progress = job["progress"] as? [String: Any]
        if let completion = progress?["completion"] as? Double { status.progress = completion / 100 }
        status.remaining = progress?["printTimeLeft"] as? Double
        status.elapsed = progress?["printTime"] as? Double
        let jobInfo = job["job"] as? [String: Any]
        let file = jobInfo?["file"] as? [String: Any]
        status.fileName = ((file?["display"] as? String) ?? (file?["name"] as? String)).cleanedFileName

        if status.state == .idle, (status.progress ?? 0) >= 0.999, status.fileName != nil {
            status.state = .finished
        }

        if let tools = jobInfo?["filament"] as? [String: Any] {
            var grams = 0.0
            for case let tool as [String: Any] in tools.values {
                if let weight = number(tool["weight"]), weight > 0 {
                    grams += weight
                } else if let length = number(tool["length"]), length > 0 {
                    grams += length / 1000 * 2.98
                }
            }
            if grams > 0 { status.filamentNeeded = grams }
        }

        let path = file?["path"] as? String
        if let path, !path.isEmpty {
            if (file?["origin"] as? String ?? "local") == "local", let url = await thumbnail(for: path) {
                status.preview = .url(url, headers: ["X-Api-Key": config.apiKey])
            }
            status.jobID = jobID(file: path, state: status.state, printTime: status.elapsed)
        } else {
            currentJob = nil
        }

        if let temps = printer?["temperature"] as? [String: Any] {
            let tool = temps["tool0"] as? [String: Any]
            let bed = temps["bed"] as? [String: Any]
            status.nozzle = tool?["actual"] as? Double
            status.nozzleTarget = tool?["target"] as? Double
            status.bed = bed?["actual"] as? Double
            status.bedTarget = bed?["target"] as? Double
            if let chamber = temps["chamber"] as? [String: Any] {
                status.chamber = chamber["actual"] as? Double
            }
        }
        status.updated = Date()
        return status
    }

    private func jobID(file: String, state: PrintState, printTime: Double?) -> String? {
        let time = printTime ?? 0
        if let current = currentJob, current.file == file, time + 30 >= current.printTime {
            currentJob?.printTime = max(current.printTime, time)
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
