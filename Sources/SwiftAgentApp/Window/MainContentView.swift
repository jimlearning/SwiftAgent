import SwiftUI

struct MainContentView: View {
    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        } content: {
            ContentView()
                .navigationSplitViewColumnWidth(min: 480, ideal: 720)
        } detail: {
            RightTabsView()
                .navigationSplitViewColumnWidth(min: 380, ideal: 420, max: 520)
        }
        .preferredColorScheme(.dark)
    }
}
