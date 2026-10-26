import DroppyKit
import SwiftUI

enum Format {
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func temp(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded()))°"
    }

    static func state(_ state: PrintState) -> String {
        L.s("state.\(state.rawValue)")
    }

    static func color(_ state: PrintState) -> Color {
        switch state {
        case .printing: return .green
        case .preparing: return .blue
        case .paused: return .orange
        case .finished: return .green
        case .failed, .stopped: return .red
        case .idle: return .secondary
        case .offline, .connecting: return .gray
        }
    }
}

struct ProgressRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat
    var symbol: String?
    var symbolSize: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: symbolSize, weight: .bold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            }
        }
    }
}

struct PrintCompactLeading: View {
    @ObservedObject var droplet: PrintLiveDroplet

    var body: some View {
        let featured = droplet.featured
        let state = featured?.status.state ?? .idle
        ProgressRing(
            progress: featured?.status.progress ?? 0,
            tint: Format.color(state),
            lineWidth: DroppyLiveActivityMetrics.progressRingLineWidth,
            symbol: state == .finished ? "checkmark" : (state == .paused ? "pause.fill" : "printer.fill"),
            symbolSize: DroppyLiveActivityMetrics.progressRingGlyphSize
        )
        .frame(width: DroppyLiveActivityMetrics.progressRingSize, height: DroppyLiveActivityMetrics.progressRingSize)
    }
}

struct PrintCompactTrailing: View {
    @ObservedObject var droplet: PrintLiveDroplet

    var body: some View {
        ViewThatFits(in: .horizontal) {
            label(full)
            label(short)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            .lineLimit(1)
            .fixedSize()
    }

    private var short: String {
        guard let f = droplet.featured else { return "" }
        if f.status.state == .finished { return "✓" }
        return "\(Int(((f.status.progress ?? 0) * 100).rounded()))%"
    }

    private var full: String {
        guard let f = droplet.featured else { return "" }
        if f.status.state == .finished { return L.s("state.finished") }
        if let left = droplet.remaining(f.status) { return "\(short) · \(Format.duration(left))" }
        return short
    }
}

struct PrintShelfWidget: View {
    @ObservedObject var droplet: PrintLiveDroplet
    let context: ShelfWidgetContext

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            if droplet.printers.isEmpty {
                VStack(spacing: DroppySpacing.sm) {
                    Image(systemName: "printer.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    Text(L.s("widget.empty"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(droplet.printers.prefix(3)) { printer in
                    PrinterRow(droplet: droplet, printer: printer, compact: context.isPaired)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(context.contentInsets)
    }
}

struct PrinterRow: View {
    @ObservedObject var droplet: PrintLiveDroplet
    let printer: PrinterConfig
    let compact: Bool

    var body: some View {
        let s = droplet.status(of: printer.id)
        HStack(spacing: DroppySpacing.md) {
            ProgressRing(progress: s.state.isActive || s.state == .finished ? (s.progress ?? 0) : 0,
                         tint: Format.color(s.state), lineWidth: 4,
                         symbol: s.state == .finished ? "checkmark" : printer.kind.symbol, symbolSize: 13)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DroppySpacing.xs) {
                    Text(printer.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                        .lineLimit(1)
                    StateBadge(state: s.state)
                    Spacer(minLength: 0)
                    if s.state.isActive, let p = s.progress {
                        Text("\(Int((p * 100).rounded()))%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    }
                }
                Text(detail(s))
                    .font(.system(size: 11))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                    .lineLimit(1)
                if !compact {
                    HStack(spacing: DroppySpacing.md) {
                        Label(tempText(s.nozzle, s.nozzleTarget), systemImage: "flame")
                        Label(tempText(s.bed, s.bedTarget), systemImage: "square.3.layers.3d.bottom.filled")
                        if let layer = s.layer, let total = s.totalLayers, total > 0, s.state.isActive {
                            Label("\(layer)/\(total)", systemImage: "square.stack.3d.up")
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .labelStyle(CompactLabelStyle())
                }
            }
        }
        .frame(height: 70)
    }

    private func detail(_ s: PrintStatus) -> String {
        if let message = s.message, s.state == .offline { return message }
        var parts: [String] = []
        if let file = s.fileName, s.state.isActive || s.state == .finished { parts.append(file) }
        if s.state.isActive, let left = droplet.remaining(s) {
            parts.append(L.f("widget.left", Format.duration(left)))
            if !compact, s.state != .paused { parts.append(L.f("widget.done", Format.clock(droplet.now.addingTimeInterval(left)))) }
        }
        if parts.isEmpty { parts.append(Format.state(s.state)) }
        return parts.joined(separator: " · ")
    }

    private func tempText(_ value: Double?, _ target: Double?) -> String {
        if let target, target > 0 { return "\(Format.temp(value)) / \(Format.temp(target))" }
        return Format.temp(value)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

struct StateBadge: View {
    let state: PrintState

    var body: some View {
        Text(Format.state(state))
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(Format.color(state))
            .background(Capsule().fill(Format.color(state).opacity(0.16)))
    }
}

struct PrintHUDStrip: View {
    let state: PrintState

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Format.color(state))
            Spacer(minLength: DroppySpacing.sm)
            Text(Format.state(state))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, DroppySpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var symbol: String {
        switch state {
        case .finished: return "checkmark.circle.fill"
        case .paused: return "pause.circle.fill"
        case .failed, .stopped: return "xmark.octagon.fill"
        default: return "printer.fill"
        }
    }
}

struct PrintHUDCard: View {
    let state: PrintState
    let printer: String
    let file: String?
    let elapsed: TimeInterval?
    @State private var bounce = 0

    var body: some View {
        HStack(spacing: DroppySpacing.lg) {
            ZStack {
                ProgressRing(progress: state == .finished ? 1 : 0.5, tint: Format.color(state), lineWidth: 5, symbol: nil)
                    .frame(width: 54, height: 54)
                Image(systemName: state == .finished ? "checkmark" : (state == .paused ? "pause.fill" : "xmark"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Format.color(state))
                    .symbolEffect(.bounce, value: bounce)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DroppySpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { bounce += 1 }
    }

    private var title: String {
        switch state {
        case .finished: return L.f("hud.finished", file ?? printer)
        case .paused: return L.f("hud.paused", printer)
        default: return L.f("hud.failed", printer)
        }
    }

    private var subtitle: String {
        var parts = [printer]
        if state == .finished, let elapsed { parts.append(L.f("hud.took", Format.duration(elapsed))) }
        return parts.joined(separator: " · ")
    }
}
