import SwiftUI

struct ContentView: View {
    @AppStorage("hasSeenSetup") private var hasSeenSetup = false
    @State private var showingSetup = false

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Today", systemImage: "indianrupeesign.circle") }
            HistoryView()
                .tabItem { Label("History", systemImage: "list.bullet.rectangle") }
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.pie") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onAppear {
            if !hasSeenSetup { showingSetup = true }
        }
        .sheet(isPresented: $showingSetup, onDismiss: { hasSeenSetup = true }) {
            NavigationStack {
                SetupGuideView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSetup = false }
                        }
                    }
            }
        }
    }
}
