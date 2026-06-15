import SwiftUI

@main
struct SwiftAgentAppEntry: App {
    var body: some Scene {
        Window("SwiftAgent", id: "main") {
            MainContentView()
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
    }
}
