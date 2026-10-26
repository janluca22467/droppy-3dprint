import DroppyKit
import SwiftUI

struct PrintCameraWidget: View {
    @ObservedObject var droplet: PrintLiveDroplet
    let context: ShelfWidgetContext

    var body: some View {
        let target = droplet.cameraTarget
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            HStack(spacing: DroppySpacing.xsm) {
                Image(systemName: "video.fill").font(.system(size: 12, weight: .medium))
                Text(target.map { droplet.name(of: $0) } ?? L.s("cam.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let target {
                    StateBadge(state: droplet.status(of: target).state).fixedSize()
                }
                Spacer(minLength: DroppySpacing.sm)
                switcher(target)
            }
            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            .frame(height: 20)

            ZStack {
                if let frame = droplet.cameraFrame, droplet.cameraMessage == nil {
                    Image(nsImage: frame)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous))
                } else {
                    VStack(spacing: DroppySpacing.sm) {
                        Image(systemName: droplet.printers.isEmpty ? "printer.fill" : "video.slash.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                        Text(message)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, DroppySpacing.md)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(context.contentInsets)
        .onAppear { droplet.cameraAppeared() }
        .onDisappear { droplet.cameraDisappeared() }
    }

    private var message: String {
        if droplet.printers.isEmpty { return L.s("widget.empty") }
        return droplet.cameraMessage ?? L.s("cam.loading")
    }

    @ViewBuilder
    private func switcher(_ target: UUID?) -> some View {
        let candidates = droplet.cameraCandidates
        if candidates.count > 1 {
            Menu {
                ForEach(candidates, id: \.self) { id in
                    Button {
                        droplet.selectCamera(id)
                    } label: {
                        if id == target {
                            Label(droplet.name(of: id), systemImage: "checkmark")
                        } else {
                            Text(droplet.name(of: id))
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(DroppyCircleButtonStyle(size: 20))
            .fixedSize()
            .help(L.s("cam.switch"))
            .accessibilityLabel(L.s("cam.switch"))
        }
    }
}
