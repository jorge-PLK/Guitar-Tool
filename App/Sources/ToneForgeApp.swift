import AppKit
import SwiftUI

@main
struct ToneForgeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 700)
                .task {
                    await model.start()
                    #if DEBUG
                    model.scheduleSnapshot()
                    #endif
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.flushForTermination()
                }
        }
        .defaultSize(width: 1440, height: 900)
    }
}
