import DroppyKit
import DroppyKitHarness
import PrintLive

@main
struct PrintLiveHarness: DropletHarnessApp {
    static func makeDroplet() -> any Droplet { PrintLiveDroplet() }
}
