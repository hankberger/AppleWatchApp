import SwiftUI

@main
struct FirstWatchApp_iOSApp: App {
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(authManager)
        }
    }
}
