import Foundation

struct Spool: Identifiable, Equatable, Sendable {
    var id: Int
    var name: String
    var vendor: String?
    var material: String?
    var colorHex: String?
    var remainingWeight: Double?
    var usedWeight: Double?
    var initialWeight: Double?
    var location: String?
    var archived: Bool
}

enum SpoolmanError: Error, Equatable, Sendable {
    case unreachable, badResponse
}

@MainActor
final class SpoolmanClient {
    let baseURL: URL?
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 6
        c.timeoutIntervalForResource = 6
        return URLSession(configuration: c)
    }()

    init(baseURL: String) { self.baseURL = Self.normalize(baseURL) }

    static func normalize(_ value: String) -> URL? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let hasScheme = text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://")
        if !hasScheme { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard var components = URLComponents(string: text), let host = components.host, !host.isEmpty else { return nil }
        if components.port == nil && !hasScheme { components.port = 7912 }
        if components.path.lowercased().hasSuffix("/api/v1") { components.path = String(components.path.dropLast(7)) }
        components.query = nil
        components.fragment = nil
        return components.url
    }

    func spools() async -> Result<[Spool], SpoolmanError> {
        let (code, data) = await get("api/v1/spool", query: [URLQueryItem(name: "allow_archived", value: "false")])
        guard code != 0, let data else { return .failure(.unreachable) }
        guard (200..<300).contains(code), let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return .failure(.badResponse)
        }
        return .success(list.compactMap(Self.parse))
    }

    func spool(id: Int) async -> Spool? {
        let (code, data) = await get("api/v1/spool/\(id)")
        guard (200..<300).contains(code), let data, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return Self.parse(json)
    }

    func health() async -> Bool {
        let (code, data) = await get("api/v1/health")
        guard (200..<300).contains(code) else { return false }
        guard let data, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let status = json["status"] as? String else { return true }
        return status.lowercased() == "healthy"
    }

    static func fits(needed: Double?, spool: Spool?) -> Bool? {
        guard let needed, needed > 0, let remaining = spool?.remainingWeight else { return nil }
        return remaining >= needed * 1.05
    }

    static func parse(_ json: [String: Any]) -> Spool? {
        guard let id = (json["id"] as? NSNumber)?.intValue else { return nil }
        let filament = json["filament"] as? [String: Any] ?? [:]
        let vendor = clean((filament["vendor"] as? [String: Any])?["name"] as? String)
        let material = clean(filament["material"] as? String)
        let fallback = [vendor, material].compactMap { $0 }.joined(separator: " ")
        let name = clean(filament["name"] as? String) ?? (fallback.isEmpty ? "#\(id)" : fallback)
        return Spool(
            id: id,
            name: name,
            vendor: vendor,
            material: material,
            colorHex: hex(filament["color_hex"] as? String) ?? hex((filament["multi_color_hexes"] as? String)?.split(separator: ",").first.map(String.init)),
            remainingWeight: number(json["remaining_weight"]),
            usedWeight: number(json["used_weight"]),
            initialWeight: number(json["initial_weight"]) ?? number(filament["weight"]),
            location: clean(json["location"] as? String),
            archived: json["archived"] as? Bool ?? false
        )
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, !(value is Bool) else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }

    private static func hex(_ value: String?) -> String? {
        guard var text = clean(value) else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 8 { text = String(text.prefix(6)) }
        guard text.count == 6, text.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + text.uppercased()
    }

    private func get(_ path: String, query: [URLQueryItem] = []) async -> (Int, Data?) {
        guard var url = baseURL?.appendingPathComponent(path) else { return (0, nil) }
        if !query.isEmpty { url = url.appending(queryItems: query) }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request) else { return (0, nil) }
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}
