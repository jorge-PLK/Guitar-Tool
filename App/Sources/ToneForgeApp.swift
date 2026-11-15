import AppKit
import SwiftUI

@main
struct ToneForgeApp: App {
    @State private var model = AppModel()

    init() {
        #if DEBUG
        // Las capturas no heredan el estado restaurado (SceneStorage: rejilla expandida, tamaño de ventana…).
        if LaunchOptions().snapshot != nil { UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true]) }
        #endif
    }

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
