import SwiftUI

@main
struct NaiKangApp: App {
    @StateObject private var model = NaiKangAppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
