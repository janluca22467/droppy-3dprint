import AppKit
import Foundation

@MainActor
enum Demo {
    static let aceSlots: [FilamentSlot] = [
        FilamentSlot(id: "1-0", unit: "ACE Pro", material: "PLA", colorHex: "#F2F2F2", remaining: 0.8),
        FilamentSlot(id: "1-1", unit: "ACE Pro", material: "PLA", colorHex: "#1E1E1E", remaining: 0.45, isActive: true),
        FilamentSlot(id: "1-2", unit: "ACE Pro", material: "PETG", colorHex: "#E5482F", remaining: 0.2),
        FilamentSlot(id: "1-3", unit: "ACE Pro", isEmpty: true)
    ]

    static let amsSlots: [FilamentSlot] = [
        FilamentSlot(id: "A1", unit: "AMS A", material: "PLA", colorHex: "FF8A00", remaining: 0.6, isActive: true),
        FilamentSlot(id: "A2", unit: "AMS A", material: "PLA", colorHex: "2F7CF6", remaining: 0.9),
        FilamentSlot(id: "A3", unit: "AMS A", material: "PETG", colorHex: "13C100", remaining: 0.35),
        FilamentSlot(id: "A4", unit: "AMS A", material: "TPU", colorHex: "FFFFFF", remaining: 1)
    ]

    static let spools: [Spool] = [
        Spool(id: 1, name: "PLA Basic Black", vendor: "Anycubic", material: "PLA", colorHex: "#1E1E1E",
              remainingWeight: 412, usedWeight: 588, initialWeight: 1000, location: nil, archived: false),
        Spool(id: 2, name: "PLA Orange", vendor: "Bambu Lab", material: "PLA", colorHex: "#FF8A00",
              remainingWeight: 38, usedWeight: 962, initialWeight: 1000, location: nil, archived: false),
        Spool(id: 3, name: "PETG Red", vendor: "Sunlu", material: "PETG", colorHex: "#E5482F",
              remainingWeight: 760, usedWeight: 240, initialWeight: 1000, location: nil, archived: false)
    ]

    static func history(printers: [PrinterConfig]) -> [HistoryEntry] {
        let files = ["Benchy", "Planter", "Cable clip", "Phone stand", "Gear set", "Lid", "Vase", "Hook", "Bracket", "Calibration cube", "Box", "Coaster"]
        let results = ["finished", "finished", "finished", "failed", "finished", "finished", "stopped", "finished", "finished", "finished", "failed", "finished"]
        let now = Date()
        return files.indices.map { i in
            let printer = printers[i % printers.count]
            let duration = TimeInterval(1800 + (i * 2347) % 14_000)
            let ended = now.addingTimeInterval(-Double(i) * 47_000 - 1200)
            return HistoryEntry(
                printerID: printer.id,
                printerName: printer.name,
                fileName: files[i],
                result: results[i],
                started: ended.addingTimeInterval(-duration),
                ended: ended,
                duration: duration,
                filamentGrams: Double(12 + (i * 17) % 90)
            )
        }
    }

    static func preview(hue: CGFloat) -> Data {
        let size = 96
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return Data() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.16, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
        let body = NSColor(hue: hue, saturation: 0.8, brightness: 0.95, alpha: 1)
        body.setFill()
        let hull = NSBezierPath()
        hull.move(to: NSPoint(x: 14, y: 34))
        hull.line(to: NSPoint(x: 82, y: 34))
        hull.line(to: NSPoint(x: 72, y: 18))
        hull.line(to: NSPoint(x: 24, y: 18))
        hull.close()
        hull.fill()
        body.blended(withFraction: 0.25, of: .black)?.setFill()
        NSBezierPath(roundedRect: NSRect(x: 36, y: 34, width: 30, height: 26), xRadius: 4, yRadius: 4).fill()
        body.blended(withFraction: 0.45, of: .black)?.setFill()
        NSBezierPath(rect: NSRect(x: 44, y: 60, width: 10, height: 14)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    static func cameraFrame(seed: Int) -> NSImage? {
        let width = 640, height = 360
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.12, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSColor(white: 0.22, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: 110)).fill()
        NSColor(white: 0.3, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 120, y: 90, width: 400, height: 22)).fill()
        let tint = NSColor(hue: seed == 0 ? 0.08 : 0.33, saturation: 0.8, brightness: 0.95, alpha: 1)
        tint.setFill()
        NSBezierPath(roundedRect: NSRect(x: 260, y: 112, width: 120, height: 70), xRadius: 6, yRadius: 6).fill()
        NSColor(white: 0.55, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 250, width: width, height: 14)).fill()
        NSColor(white: 0.7, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 290, y: 200, width: 60, height: 70), xRadius: 4, yRadius: 4).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        return NSImage(data: jpeg)
    }
}
