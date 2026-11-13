import SwiftUI
import AppKit

private let panelBackground = NSColor(red: 0.085, green: 0.085, blue: 0.11, alpha: 1)

struct MenuBarContentView: View {
    let appModel: AppModel

    var body: some View {
        Group {
            if appModel.isSetupComplete && appModel.setupMode == nil {
                UsageView(appModel: appModel)
            } else {
                SetupView(appModel: appModel)
            }
        }
        .colorScheme(.dark)
        .background(WindowConfigurator())
    }
}

// Reaches into the underlying NSPanel to pin its background color and appearance,
// preventing the system white border and transition flash in light mode.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.backgroundColor = panelBackground
            window.appearance = NSAppearance(named: .darkAqua)
            window.isOpaque = true
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
