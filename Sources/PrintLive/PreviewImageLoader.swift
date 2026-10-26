import AppKit
import DroppyKit
import SwiftUI

@MainActor
final class PreviewImageLoader {
    static let shared = PreviewImageLoader()

    private var cache: [String: NSImage] = [:]
    private var order: [String] = []
    private var failed: [String: Date] = [:]
    private var running: [String: Task<Data?, Never>] = [:]
    private let limit = 32
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.timeoutIntervalForResource = 12
        return URLSession(configuration: c)
    }()

    static func key(_ preview: PreviewImage) -> String {
        switch preview {
        case .url(let url, _): return url.absoluteString
        case .data(let data): return "data-\(data.count)-\(data.hashValue)"
        }
    }

    func cached(_ preview: PreviewImage?) -> NSImage? {
        guard let preview else { return nil }
        return cache[Self.key(preview)]
    }

    func load(_ preview: PreviewImage) async -> NSImage? {
        let key = Self.key(preview)
        if let image = cache[key] { return image }
        if let date = failed[key], Date().timeIntervalSince(date) < 120 { return nil }
        let task: Task<Data?, Never>
        if let existing = running[key] {
            task = existing
        } else {
            task = Task<Data?, Never> { [session] in
                switch preview {
                case .data(let data):
                    return data
                case .url(let url, let headers):
                    var request = URLRequest(url: url)
                    for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
                    guard let (data, response) = try? await session.data(for: request),
                          (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { return nil }
                    return data
                }
            }
            running[key] = task
        }
        let data = await task.value
        running[key] = nil
        if let image = cache[key] { return image }
        let image = data.flatMap { NSImage(data: $0) }
        if let image {
            store(image, for: key)
        } else {
            failed[key] = Date()
        }
        return image
    }

    private func store(_ image: NSImage, for key: String) {
        cache[key] = image
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > limit {
            cache[order.removeFirst()] = nil
        }
    }
}

struct PreviewThumbnail<Fallback: View>: View {
    let preview: PreviewImage?
    let size: CGFloat
    @ViewBuilder let fallback: () -> Fallback
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image ?? PreviewImageLoader.shared.cached(preview) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous))
            } else {
                fallback()
            }
        }
        .frame(width: size, height: size)
        .task(id: preview.map(PreviewImageLoader.key)) {
            guard let preview else {
                image = nil
                return
            }
            image = await PreviewImageLoader.shared.load(preview)
        }
    }
}

enum FilamentColor {
    static func normalize(_ value: String?) -> String? {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 8 { text = String(text.prefix(6)) }
        guard text.count == 6, text.allSatisfy(\.isHexDigit) else { return nil }
        return text.uppercased()
    }

    static func isDark(_ value: String?) -> Bool {
        guard let hex = normalize(value), let rgb = UInt32(hex, radix: 16) else { return false }
        let r = Double((rgb >> 16) & 0xFF), g = Double((rgb >> 8) & 0xFF), b = Double(rgb & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255 < 0.3
    }

    static func color(_ value: String?) -> Color? {
        guard let hex = normalize(value), let rgb = UInt32(hex, radix: 16) else { return nil }
        return Color(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct FilamentDots: View {
    let slots: [FilamentSlot]
    var maxCount = 8

    var body: some View {
        HStack(spacing: DroppySpacing.xs) {
            ForEach(slots.prefix(maxCount)) { slot in
                FilamentDot(slot: slot)
            }
            if slots.count > maxCount {
                Text("+\(slots.count - maxCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            }
        }
    }
}

struct FilamentDot: View {
    let slot: FilamentSlot

    var body: some View {
        ZStack {
            if slot.isActive {
                Circle().stroke(AdaptiveColors.notchSurfacePrimaryText, lineWidth: 1.5)
                    .frame(width: 13, height: 13)
            }
            if slot.isEmpty || FilamentColor.color(slot.colorHex) == nil {
                Circle().stroke(AdaptiveColors.notchSurfaceTertiaryText, lineWidth: 1)
                    .frame(width: 8, height: 8)
            } else if let color = FilamentColor.color(slot.colorHex) {
                Circle().fill(color)
                    .overlay(Circle().stroke(Color.white.opacity(FilamentColor.isDark(slot.colorHex) ? 0.45 : 0), lineWidth: 1))
                    .frame(width: 9, height: 9)
            }
        }
        .frame(width: 13, height: 13)
        .help(tooltip)
        .accessibilityElement()
        .accessibilityLabel(tooltip)
    }

    private var tooltip: String {
        var parts = [slot.id]
        if slot.isEmpty {
            parts.append(L.s("slot.empty"))
        } else {
            if let material = slot.material { parts.append(material) }
            if let remaining = slot.remaining { parts.append("\(Int((remaining * 100).rounded())) %") }
        }
        if slot.isActive { parts.append(L.s("slot.active")) }
        return parts.joined(separator: " · ")
    }
}
