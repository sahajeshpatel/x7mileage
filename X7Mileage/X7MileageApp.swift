import SwiftUI

@main
struct X7MileageApp: App {
    @StateObject private var store = MileageStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                #if os(macOS)
                // A fixed minimum keeps the window from resizing itself to fit
                // content whose size depends on the window width (the adaptive grid).
                .frame(minWidth: 640, minHeight: 560)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 720)
        .windowResizability(.contentMinSize)
        #endif
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent") }

            EntriesView()
                .tabItem { Label("Readings", systemImage: "list.bullet") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
