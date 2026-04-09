import SwiftUI
import AppKit

@main
struct WhatsChangedApp: App {
    @State private var model = AppModel()
    @FocusedValue(\.openBasePicker) private var openBasePicker
    @FocusedValue(\.openComparePicker) private var openComparePicker

    init() {
        NSApplication.shared.setActivationPolicy(.regular)

        // Render an app icon: SF Symbol on a rounded-rect background.
        let size: CGFloat = 512
        let icon = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // Background rounded rect.
            let radius = size * 0.22
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: radius, yRadius: radius)
            NSColor(red: 0.95, green: 0.3, blue: 0.5, alpha: 1.0).setFill()
            path.fill()

            // Draw SF Symbol centered in white.
            let config = NSImage.SymbolConfiguration(pointSize: size * 0.45, weight: .medium)
                .applying(.init(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil),
               let configured = symbol.withSymbolConfiguration(config) {
                let symbolSize = configured.size
                let drawRect = NSRect(
                    x: (size - symbolSize.width) / 2,
                    y: (size - symbolSize.height) / 2,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                configured.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            return true
        }
        NSApplication.shared.applicationIconImage = icon
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .onAppear {
                    NSApplication.shared.activate()
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Repository...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.message = "Select a git repository"

                    if panel.runModal() == .OK, let url = panel.url {
                        model.openRepo(at: url)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Refresh") {
                    model.loadRefs()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Select Base Ref") {
                    openBasePicker?.wrappedValue = true
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Select Compare Ref") {
                    openComparePicker?.wrappedValue = true
                }
                .keyboardShortcut("l", modifiers: .command)
            }
        }
    }
}
