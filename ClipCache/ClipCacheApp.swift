import SwiftUI

@main
struct ClipCacheApp: App {
    @StateObject private var manager = ClipCacheManager()
    

    var body: some Scene {
        MenuBarExtra {
            ClipCacheMenu()
                .environmentObject(manager)
                .onAppear {
                    setupGlobalHotKeyHandler(manager: manager)
                    manager.checkAndPromptForPermissionsIfNeeded()
                }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                    .imageScale(.small)
                if !manager.menuBarTitle.isEmpty {
                    Text(manager.menuBarTitle)
                        .font(.system(size: 11))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
