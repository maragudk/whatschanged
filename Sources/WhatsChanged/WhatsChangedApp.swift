import SwiftUI

@main
struct WhatsChangedApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate()
                }
        }
        .defaultSize(width: 1200, height: 800)
    }
}
