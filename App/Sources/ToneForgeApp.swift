import AppKit
import SwiftUI

/// Tamaño mínimo de la ventana de toda la app (banco de pruebas de la adaptación; las pantallas deben caber sin desbordar).
enum WindowMetrics {
    static let minWidth: CGFloat = 1100
    static let minHeight: CGFloat = 680
}

@main
struct ToneForgeApp: App {
    @State private var model = AppModel()

    init() {
        #if DEBUG
        // Las capturas no heredan el estado restaurado (SceneStorage: rejilla expandida, tamaño de ventana…).
        if LaunchOptions().snapshot != nil {
            UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
            // Captura en segundo plano: sin Dock ni activación, para no robar la pantalla (`--foreground` lo desactiva).
            if !CommandLine.arguments.contains("--foreground") { NSApplication.shared.setActivationPolicy(.accessory) }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: WindowMetrics.minWidth, minHeight: WindowMetrics.minHeight)
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
