import DroppyKit
import SwiftUI

struct PrintLiveSettings: View {
    @ObservedObject var droplet: PrintLiveDroplet
    @State private var draft: PrinterConfig?
    @State private var showsSecret = false

    var body: some View {
        DropletSettingsPane {
            DropletSettingsSection {
                VStack(alignment: .leading, spacing: 2) {
                    settingsSectionHeader(LocalizedStringKey(L.s("set.printers")))
                    Text(L.s("set.printersDetail"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            } content: {
                DropletSettingsCard {
                    if droplet.printers.isEmpty {
                        DropletControlRow(title: L.s("set.none"), icon: "printer", iconColor: .gray) { EmptyView() }
                    }
                    ForEach(droplet.printers) { printer in
                        PrinterListRow(droplet: droplet, printer: printer) {
                            showsSecret = false
                            withAnimation { draft = printer }
                        }
                    }
                    if draft == nil {
                        DropletControlRow(title: L.s("set.add"), icon: "plus.circle.fill", iconColor: .green) {
                            HStack(spacing: DroppySpacing.xs) {
                                ForEach(PrinterKind.allCases) { kind in
                                    Button(kind.title) {
                                        showsSecret = false
                                        withAnimation { draft = PrinterConfig(name: kind.title, kind: kind, host: "") }
                                    }
                                    .buttonStyle(DroppyQuietButtonStyle(size: .small))
                                }
                            }
                        }
                    }
                }
                .droppyFlatGlassControls()
            }

            if let binding = draftBinding {
                DropletSettingsSection {
                    VStack(alignment: .leading, spacing: 2) {
                        settingsSectionHeader(LocalizedStringKey(binding.wrappedValue.kind.title))
                        Text(L.s("help.\(binding.wrappedValue.kind.rawValue)"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                } content: {
                    PrinterEditor(
                        draft: binding,
                        showsSecret: $showsSecret,
                        isNew: !droplet.printers.contains { $0.id == binding.wrappedValue.id },
                        onSave: {
                            droplet.save(binding.wrappedValue)
                            withAnimation { draft = nil }
                        },
                        onCancel: { withAnimation { draft = nil } },
                        onDelete: {
                            droplet.remove(binding.wrappedValue.id)
                            withAnimation { draft = nil }
                        }
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader(LocalizedStringKey(L.s("set.where")))
            } content: {
                DropletSettingsCard {
                    DropletControlRow(title: L.s("set.whereNotch"), icon: "rectangle.topthird.inset.filled", iconColor: .blue) {
                        Text(L.s("set.whereNotchValue")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    DropletControlRow(title: L.s("set.whereShelf"), icon: "square.grid.2x2.fill", iconColor: .purple) {
                        Text(L.s("set.whereShelfValue")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    DropletControlRow(title: L.s("set.whereHUD"), icon: "bell.badge.fill", iconColor: .orange) {
                        Text(L.s("set.whereHUDValue")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    DropletControlRow(title: L.s("set.whereLock"), icon: "lock.fill", iconColor: .gray) {
                        Text(L.s("set.whereLockValue")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var draftBinding: Binding<PrinterConfig>? {
        guard draft != nil else { return nil }
        return Binding(get: { draft ?? PrinterConfig(name: "", kind: .octoprint, host: "") }, set: { draft = $0 })
    }
}

private struct PrinterListRow: View {
    @ObservedObject var droplet: PrintLiveDroplet
    let printer: PrinterConfig
    let onEdit: () -> Void

    var body: some View {
        let s = droplet.status(of: printer.id)
        DropletControlRow(title: printer.name, icon: printer.kind.symbol, iconColor: kindColor) {
            HStack(spacing: DroppySpacing.sm) {
                HStack(spacing: 6) {
                    Circle().fill(printer.isEnabled ? Format.color(s.state) : .gray).frame(width: 7, height: 7)
                    Text(statusText(s))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button {
                    droplet.reconnect(printer.id)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 24))
                .help(L.s("set.reconnect"))
                Button(L.s("set.edit"), action: onEdit)
                    .buttonStyle(DroppyQuietButtonStyle(size: .small))
            }
        }
    }

    private var kindColor: Color {
        switch printer.kind {
        case .octoprint: return .green
        case .bambu: return .teal
        case .anycubic: return .blue
        case .moonraker: return .red
        case .anycubicCloud: return .indigo
        }
    }

    private func statusText(_ s: PrintStatus) -> String {
        guard printer.isEnabled else { return L.s("set.disabled") }
        if s.state == .offline, let message = s.message { return message }
        if s.state.isActive, let p = s.progress { return "\(Format.state(s.state)) · \(Int((p * 100).rounded()))%" }
        return Format.state(s.state)
    }
}

private struct PrinterEditor: View {
    @Binding var draft: PrinterConfig
    @Binding var showsSecret: Bool
    let isNew: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        DropletSettingsCard {
            field(L.s("field.name"), icon: "tag.fill", color: .gray, text: $draft.name, prompt: draft.kind.title)
            if draft.kind != .anycubicCloud {
                field(L.s("field.host"), icon: "network", color: .blue, text: $draft.host,
                      prompt: draft.kind == .octoprint ? "octopi.local" : (draft.kind == .moonraker ? "mainsailos.local" : "192.168.1.50"))
            }
            switch draft.kind {
            case .octoprint:
                secret(L.s("field.apiKey"), icon: "key.fill", text: $draft.apiKey)
            case .bambu:
                field(L.s("field.serial"), icon: "number", color: .teal, text: $draft.serial, prompt: "01P00A…")
                secret(L.s("field.accessCode"), icon: "lock.fill", text: $draft.accessCode)
            case .anycubic:
                EmptyView()
            case .moonraker:
                secret(L.s("field.apiKeyOptional"), icon: "key.fill", text: $draft.apiKey)
            case .anycubicCloud:
                secret(L.s("field.webToken"), icon: "key.fill", text: $draft.apiKey)
                field(L.s("field.printerName"), icon: "printer.fill", color: .indigo, text: $draft.serial, prompt: "Kobra S1")
            }
            DropletToggleRow(title: L.s("field.enabled"), icon: "power", iconColor: .green, isOn: $draft.isEnabled)
            DropletControlRow(title: draft.isComplete ? L.s("field.ready") : L.s("field.missing"),
                              icon: draft.isComplete ? "checkmark.circle.fill" : "exclamationmark.circle",
                              iconColor: draft.isComplete ? .green : .orange) {
                HStack(spacing: DroppySpacing.xs) {
                    if !isNew {
                        Button(L.s("set.delete"), role: .destructive, action: onDelete)
                            .buttonStyle(DroppyQuietButtonStyle(size: .small, destructive: true))
                    }
                    Button(L.s("set.cancel"), action: onCancel)
                        .buttonStyle(DroppyQuietButtonStyle(size: .small))
                    Button(L.s("set.save"), action: onSave)
                        .buttonStyle(DroppyAccentButtonStyle(size: .small))
                        .disabled(!draft.isComplete)
                }
            }
        }
        .droppyFlatGlassControls()
    }

    private func field(_ title: String, icon: String, color: Color, text: Binding<String>, prompt: String) -> some View {
        DropletControlRow(title: title, icon: icon, iconColor: color) {
            TextField("", text: text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 240)
        }
    }

    private func secret(_ title: String, icon: String, text: Binding<String>) -> some View {
        DropletControlRow(title: title, icon: icon, iconColor: .yellow) {
            HStack(spacing: DroppySpacing.xs) {
                Group {
                    if showsSecret {
                        TextField("", text: text, prompt: Text("••••••••"))
                    } else {
                        SecureField("", text: text, prompt: Text("••••••••"))
                    }
                }
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 220)
                Button {
                    showsSecret.toggle()
                } label: {
                    Image(systemName: showsSecret ? "eye.slash" : "eye")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 24))
            }
        }
    }
}
