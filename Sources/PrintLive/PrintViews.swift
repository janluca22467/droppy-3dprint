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

    static func weight(_ grams: Double) -> String {
        if grams >= 1000 { return String(format: "%.1f kg", grams / 1000) }
        return "\(Int(grams.rounded())) g"
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
                    PrinterRow(droplet: droplet, printer: printer, compact: context.isCompact)
                        .frame(height: droplet.rowHeight(for: printer))
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
        HStack(alignment: .top, spacing: DroppySpacing.md) {
            PreviewThumbnail(preview: s.state.isActive || s.state == .finished ? s.preview : nil, size: 46) {
                ProgressRing(progress: s.state.isActive || s.state == .finished ? (s.progress ?? 0) : 0,
                             tint: Format.color(s.state), lineWidth: 4,
                             symbol: s.state == .finished ? "checkmark" : printer.kind.symbol, symbolSize: 13)
                    .frame(width: 46, height: 46)
            }
            .overlay(alignment: .bottom) {
                if s.preview != nil, s.state.isActive, let p = s.progress {
                    ProgressBar(progress: p, tint: Format.color(s.state))
                        .padding(.horizontal, DroppySpacing.xs)
                        .padding(.bottom, DroppySpacing.xs)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DroppySpacing.xs) {
                    Text(printer.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                        .lineLimit(1)
                    StateBadge(state: s.state)
                        .fixedSize()
                    Spacer(minLength: DroppySpacing.xs)
                    if !compact { controls(s) }
                    if s.state.isActive, let p = s.progress {
                        Text("\(Int((p * 100).rounded()))%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                            .fixedSize()
                    }
                }
                .frame(height: 20)
                Text(detail(s))
                    .font(.system(size: 11))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                    .lineLimit(1)
                HStack(spacing: DroppySpacing.md) {
                    if !compact {
                        Label(tempText(s.nozzle, s.nozzleTarget), systemImage: "flame")
                        Label(tempText(s.bed, s.bedTarget), systemImage: "square.3.layers.3d.bottom.filled")
                        if let layer = s.layer, let total = s.totalLayers, total > 0, s.state.isActive {
                            Label("\(layer)/\(total)", systemImage: "square.stack.3d.up")
                        }
                    }
                    Spacer(minLength: 0)
                    if !s.slots.isEmpty { FilamentDots(slots: s.slots, maxCount: compact ? 5 : 8) }
                }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                .labelStyle(CompactLabelStyle())
                .lineLimit(1)
                if let spool = droplet.linkedSpool(for: printer.id) {
                    spoolLine(spool, fits: droplet.spoolFits(for: printer.id))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func controls(_ s: PrintStatus) -> some View {
        let actions = droplet.actions(for: printer.id)
        let busy = droplet.busy.contains(printer.id)
        if s.state.isActive, !actions.isEmpty {
            HStack(spacing: DroppySpacing.xs) {
                if s.state == .paused, actions.contains(.resume) {
                    controlButton("play.fill", label: L.s("ctl.resume"), destructive: false) { droplet.requestAction(.resume, for: printer.id) }
                } else if s.state == .printing, actions.contains(.pause) {
                    controlButton("pause.fill", label: L.s("ctl.pause"), destructive: false) { droplet.requestAction(.pause, for: printer.id) }
                }
                if actions.contains(.stop) {
                    controlButton("stop.fill", label: L.s("ctl.stop"), destructive: true) { droplet.requestAction(.stop, for: printer.id) }
                }
            }
            .disabled(busy)
            .opacity(busy ? 0.5 : 1)
        }
    }

    private func controlButton(_ symbol: String, label: String, destructive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(DroppyCircleButtonStyle(size: 20, destructive: destructive, solidFill: nil, foregroundColorOverride: nil))
        .help(label)
        .accessibilityLabel(label)
    }

    private func spoolLine(_ spool: Spool, fits: Bool?) -> some View {
        HStack(spacing: DroppySpacing.xs) {
            Circle()
                .fill(FilamentColor.color(spool.colorHex) ?? AdaptiveColors.notchSurfaceTertiaryText)
                .overlay(Circle().stroke(Color.white.opacity(FilamentColor.isDark(spool.colorHex) ? 0.45 : 0), lineWidth: 1))
                .frame(width: 7, height: 7)
            Text(spool.name)
                .lineLimit(1)
                .truncationMode(.tail)
            if let grams = spool.remainingWeight {
                Text(compact ? Format.weight(grams) : L.f("spool.left", Int(grams.rounded())))
                    .monospacedDigit()
                    .fixedSize()
            }
            Spacer(minLength: DroppySpacing.xs)
            if fits == false {
                Label(compact ? L.s("spool.lowShort") : L.s("spool.low"), systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(CompactLabelStyle())
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(Color.orange)
                    .background(Capsule().fill(Color.orange.opacity(0.16)))
                    .fixedSize()
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
        .frame(height: 14)
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

struct ProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.55))
                Capsule().fill(tint)
                    .frame(width: max(3, proxy.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 3)
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
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(Format.color(state))
            .background(Capsule().fill(Format.color(state).opacity(0.16)))
    }
}

struct PrintHUDStrip: View {
    let content: HUDContent

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: content.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(content.tint)
            Spacer(minLength: DroppySpacing.sm)
            Text(content.stripText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, DroppySpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PrintHUDCard: View {
    let content: HUDContent
    @State private var bounce = 0

    var body: some View {
        HStack(spacing: DroppySpacing.lg) {
            PreviewThumbnail(preview: content.preview, size: 54) {
                ZStack {
                    ProgressRing(progress: content.progress, tint: content.tint, lineWidth: 5, symbol: nil)
                        .frame(width: 54, height: 54)
                    Image(systemName: content.symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(content.tint)
                        .symbolEffect(.bounce, value: bounce)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if content.preview != nil {
                    Image(systemName: content.symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(content.tint)
                        .background(Circle().fill(Color.black).padding(1))
                        .offset(x: 5, y: 5)
                        .symbolEffect(.bounce, value: bounce)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(content.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .lineLimit(1)
                Text(content.subtitle)
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
}

struct PrintMenuBarContent: View {
    @ObservedObject var droplet: PrintLiveDroplet

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            ForEach(droplet.printers) { printer in
                let s = droplet.status(of: printer.id)
                HStack(spacing: DroppySpacing.sm) {
                    Image(systemName: s.state == .finished ? "checkmark.circle.fill" : printer.kind.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Format.color(s.state))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: printer.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Text(verbatim: Format.state(s.state))
                            .font(.system(size: 11))
                            .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                            .lineLimit(1)
                    }
                    Spacer(minLength: DroppySpacing.xl)
                    VStack(alignment: .trailing, spacing: 1) {
                        if s.state.isActive, let p = s.progress {
                            Text(verbatim: "\(Int((p * 100).rounded())) %")
                                .font(.system(size: 13, weight: .semibold))
                                .monospacedDigit()
                        }
                        if s.state.isActive, let left = droplet.remaining(s) {
                            Text(verbatim: L.f("widget.left", Format.duration(left)))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                        }
                    }
                    .fixedSize()
                }
            }
        }
        .foregroundStyle(AdaptiveColors.primaryTextAuto)
        .padding(.vertical, DroppySpacing.xs)
        .frame(minWidth: 240, alignment: .leading)
    }
}
