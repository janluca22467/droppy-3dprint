import Foundation

@MainActor
final class OctoPrintConnection: PrinterConnection {
    var onStatus: ((PrintStatus) -> Void)?
    private let config: PrinterConfig
    private var task: Task<Void, Never>?
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 6
        return URLSession(configuration: c)
    }()

    init(config: PrinterConfig) { self.config = config }

    var baseURL: URL? {
        var host = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.hasPrefix("http://") && !host.hasPrefix("https://") { host = "http://" + host }
        while host.hasSuffix("/") { host.removeLast() }
        return URL(string: host)
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

    var snapshotURL: URL? { baseURL?.appendingPathComponent("webcam/").appending(queryItems: [URLQueryItem(name: "action", value: "snapshot")]) }

    private func get(_ path: String) async -> (Int, [String: Any]?) {
        guard let url = baseURL?.appendingPathComponent(path) else { return (0, nil) }
        var request = URLRequest(url: url)
        request.setValue(config.apiKey, forHTTPHeaderField: "X-Api-Key")
        guard let (data, response) = try? await session.data(for: request) else { return (0, nil) }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (code, try? JSONSerialization.jsonObject(with: data) as? [String: Any])
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
        let file = (job["job"] as? [String: Any])?["file"] as? [String: Any]
        status.fileName = ((file?["display"] as? String) ?? (file?["name"] as? String)).cleanedFileName

        if status.state == .idle, (status.progress ?? 0) >= 0.999, status.fileName != nil {
            status.state = .finished
        }

        if let temps = printer?["temperature"] as? [String: Any] {
            let tool = temps["tool0"] as? [String: Any]
            let bed = temps["bed"] as? [String: Any]
            status.nozzle = tool?["actual"] as? Double
            status.nozzleTarget = tool?["target"] as? Double
            status.bed = bed?["actual"] as? Double
            status.bedTarget = bed?["target"] as? Double
        }
        status.updated = Date()
        return status
    }
}
