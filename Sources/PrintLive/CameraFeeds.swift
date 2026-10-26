import Foundation

@MainActor
final class SnapshotCameraFeed: CameraFeed {
    var onFrame: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    private let url: URL
    private let headers: [String: String]
    private let interval: TimeInterval
    private var task: Task<Void, Never>?
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 6
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    init(url: URL, headers: [String: String] = [:], interval: TimeInterval = 1) {
        self.url = url
        self.headers = headers
        self.interval = interval
    }

    func start() {
        stop()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                var request = URLRequest(url: self.url)
                for (k, v) in self.headers { request.setValue(v, forHTTPHeaderField: k) }
                if let (data, response) = try? await self.session.data(for: request),
                   (response as? HTTPURLResponse)?.statusCode ?? 200 < 400, !data.isEmpty {
                    self.onFrame?(data)
                } else {
                    self.onError?(L.s("cam.unavailable"))
                }
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

@MainActor
final class MJPEGCameraFeed: NSObject, CameraFeed, URLSessionDataDelegate {
    var onFrame: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    private let url: URL
    private let headers: [String: String]
    private var session: URLSession?
    private var buffer = Data()
    private var lastFrame = Date.distantPast

    init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }

    func start() {
        stop()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.session = session
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        session.dataTask(with: request).resume()
    }

    func stop() {
        session?.invalidateAndCancel()
        session = nil
        buffer.removeAll()
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        MainActor.assumeIsolated { self.consume(data) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            guard self.session === session else { return }
            self.onError?(L.s("cam.unavailable"))
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        if buffer.count > 8_000_000 { buffer.removeAll() }
        while let start = buffer.range(of: Data([0xFF, 0xD8])),
              let end = buffer.range(of: Data([0xFF, 0xD9]), in: start.upperBound..<buffer.endIndex) {
            let frame = buffer.subdata(in: start.lowerBound..<end.upperBound)
            buffer.removeSubrange(buffer.startIndex..<end.upperBound)
            if Date().timeIntervalSince(lastFrame) > 0.2 {
                lastFrame = Date()
                onFrame?(frame)
            }
        }
    }
}
