import SwiftData
import SwiftUI

@main
struct DailyFinanceTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await NotificationService.requestAuthorization() }
        }
        .modelContainer(AppModelContainer.shared)
    }
}
